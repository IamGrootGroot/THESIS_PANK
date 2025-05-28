import cudf
import cuml
import numpy as np
import matplotlib.pyplot as plt
import plotly.express as px
import plotly.io as pio
from cuml.manifold import UMAP
from cuml.cluster import KMeans
import os
import gc
import torch
from PIL import Image
import random
from pathlib import Path

def display_cluster_tiles(embeddings_df, cluster_labels, output_dir, n_tiles_per_cluster=4):
    """
    Display representative tiles for each cluster in a grid layout.
    
    Args:
        embeddings_df: DataFrame containing the embeddings and filenames
        cluster_labels: Array of cluster labels
        output_dir: Directory to save the grid visualization
        n_tiles_per_cluster: Number of tiles to display per cluster
    """
    # Create a figure with subplots for each cluster
    n_clusters = len(np.unique(cluster_labels))
    n_cols = 2  # Number of columns in the grid for each cluster
    n_rows = 2  # Number of rows in the grid for each cluster
    spacing = 10  # Pixels of spacing between images
    border_size = 2  # Size of the border around each image
    tile_size = 224  # Base size of each tile
    
    # Calculate total figure size
    fig_width = 20
    fig_height = 5 * ((n_clusters + 1) // 2)  # 2 clusters per row
    fig, axes = plt.subplots((n_clusters + 1) // 2, 2, figsize=(fig_width, fig_height))
    axes = axes.flatten()
    
    # Convert embeddings_df to pandas if it's a cuDF DataFrame
    if isinstance(embeddings_df, cudf.DataFrame):
        embeddings_df = embeddings_df.to_pandas()
    
    # For each cluster
    for cluster_id in range(n_clusters):
        # Get indices of samples in this cluster
        cluster_indices = np.where(cluster_labels == cluster_id)[0]
        
        # Randomly select n_tiles_per_cluster samples
        if len(cluster_indices) >= n_tiles_per_cluster:
            selected_indices = np.random.choice(cluster_indices, n_tiles_per_cluster, replace=False)
        else:
            selected_indices = cluster_indices
        
        # Create a subplot for this cluster
        ax = axes[cluster_id]
        
        # Calculate total size including borders
        total_tile_size = tile_size + 2 * border_size
        
        # Create a grid of tiles for this cluster with spacing
        total_width = total_tile_size * n_cols + spacing * (n_cols - 1)
        total_height = total_tile_size * n_rows + spacing * (n_rows - 1)
        tile_grid = np.ones((total_height, total_width, 3), dtype=np.uint8) * 255  # White background
        
        # Load and place each tile
        for i, idx in enumerate(selected_indices):
            try:
                # Get the filename from the original DataFrame
                filename = embeddings_df.iloc[idx]['filename']
                if isinstance(filename, str):
                    img_path = Path(filename)
                    
                    if img_path.exists():
                        # Load the image
                        img = Image.open(img_path)
                        
                        # Convert to RGB if needed
                        if img.mode != 'RGB':
                            img = img.convert('RGB')
                        
                        # Resize to target size
                        img = img.resize((tile_size, tile_size), Image.Resampling.LANCZOS)
                        img_array = np.array(img)
                        
                        # Calculate position in grid (including border)
                        row = i // n_cols
                        col = i % n_cols
                        y_start = row * (total_tile_size + spacing)
                        x_start = col * (total_tile_size + spacing)
                        
                        # Create border
                        img_with_border = np.ones((total_tile_size, total_tile_size, 3), dtype=np.uint8) * 0  # Black border
                        img_with_border[border_size:-border_size, border_size:-border_size] = img_array
                        
                        # Place in the grid
                        tile_grid[y_start:y_start+total_tile_size, x_start:x_start+total_tile_size] = img_with_border
                    else:
                        print(f"File not found: {filename}")
                else:
                    print(f"Invalid filename type for cluster {cluster_id}, tile {i}: {type(filename)}")
            except Exception as e:
                print(f"Error loading image for cluster {cluster_id}, tile {i}: {e}")
        
        # Display the grid
        ax.imshow(tile_grid)
        ax.set_title(f'Cluster {cluster_id}', fontsize=12, pad=20)
        ax.axis('off')
    
    # Hide empty subplots
    for i in range(n_clusters, len(axes)):
        axes[i].axis('off')
    
    plt.tight_layout()
    
    # Save the figure
    output_path = os.path.join(output_dir, 'cluster_tiles_grid.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"Cluster tiles grid saved to {output_path}")
    
    plt.close()

def visualize_features(input_file, output_image, interactive_html, batch_size=100000):
    """
    Visualize features using UMAP and K-means clustering, optimized for A100 GPU
    """
    # Check if the file exists
    if not os.path.exists(input_file):
        raise FileNotFoundError(f"Error: The file '{input_file}' does not exist.")

    # Clear GPU memory
    torch.cuda.empty_cache()
    gc.collect()

    # 1. Load embeddings from CSV file in batches
    print(f"Loading embeddings from {input_file} ...")
    gdf = cudf.read_csv(input_file)
    
    # Print column names and memory usage
    print("Columns in CSV:", gdf.columns)
    print(f"Memory usage: {gdf.memory_usage(deep=True).sum() / 1e9:.2f} GB")

    # 2. Drop all non-numeric columns
    non_numeric_columns = ['filename', 'element']  # Adjust if needed
    for col in non_numeric_columns:
        if col in gdf.columns:
            gdf = gdf.drop([col], axis=1)

    # Convert data to float32 for better memory efficiency
    gdf = gdf.astype('float32')

    # 3. Convert to NumPy array
    print("Converting to NumPy array...")
    embeddings = gdf.to_pandas().values
    del gdf  # Free GPU memory
    torch.cuda.empty_cache()
    gc.collect()

    # 4. Apply UMAP for 3D dimensionality reduction
    print("Computing 3D UMAP projection...")
    umap_3d = UMAP(
        n_components=3,
        n_neighbors=15,
        min_dist=0.1,
        random_state=42,
        verbose=True  # Show progress
    )
    embeddings_3d = umap_3d.fit_transform(embeddings)
    del embeddings  # Free memory
    torch.cuda.empty_cache()
    gc.collect()

    # 5. Apply K-Means Clustering with 30 clusters
    print("Performing K-Means with 30 clusters...")
    kmeans = KMeans(
        n_clusters=30,
        random_state=42,
        verbose=True  # Show progress
    )
    kmeans.fit(embeddings_3d)
    cluster_labels = kmeans.predict(embeddings_3d)

    # 6. Convert results to cuDF DataFrame
    print("Preparing visualization data...")
    df_3d = cudf.DataFrame({
        'x': embeddings_3d[:, 0],
        'y': embeddings_3d[:, 1],
        'z': embeddings_3d[:, 2],
        'cluster': cluster_labels
    })

    # 7. Create interactive 3D scatter plot
    print("Generating interactive 3D scatter plot...")
    fig = px.scatter_3d(
        df_3d.to_pandas(),
        x='x', y='y', z='z',
        color='cluster',
        title="Interactive 3D UMAP Projection (30 Clusters)",
        labels={'x': "UMAP 1", 'y': "UMAP 2", 'z': "UMAP 3"},
        opacity=0.7
    )

    # Save interactive plot
    pio.write_html(fig, interactive_html)
    print(f"Interactive 3D visualization saved to {interactive_html}")

    # 8. Create static plot
    print("Generating static 3D scatter plot...")
    plt.figure(figsize=(16, 12))
    ax = plt.axes(projection='3d')

    scatter = ax.scatter3D(
        df_3d['x'].to_numpy(),
        df_3d['y'].to_numpy(),
        df_3d['z'].to_numpy(),
        c=df_3d['cluster'].to_numpy(),
        cmap='tab20',
        s=20,
        alpha=0.7,
        depthshade=True
    )

    ax.set_title("3D UMAP Projection (30 Clusters)", fontsize=14)
    ax.set_xlabel("UMAP 1", labelpad=10)
    ax.set_ylabel("UMAP 2", labelpad=10)
    ax.set_zlabel("UMAP 3", labelpad=10)

    cbar = plt.colorbar(scatter, ax=ax, pad=0.1)
    cbar.set_label('Cluster ID')

    ax.view_init(elev=20, azim=45)

    plt.savefig(output_image, dpi=350, bbox_inches='tight')
    print(f"Static 3D visualization saved to {output_image}")

    plt.show()

    # 9. Display cluster tiles
    print("Generating cluster tiles visualization...")
    display_cluster_tiles(
        embeddings_df=cudf.read_csv(input_file),  # Reload original data to get filenames
        cluster_labels=cluster_labels,
        output_dir=os.path.dirname(output_image)
    )

    # Final cleanup
    del df_3d
    torch.cuda.empty_cache()
    gc.collect()

if __name__ == "__main__":
    # Define paths
    input_file = "output/features/output_embeddings_new2.csv"
    output_image = "output/umap/umap_3d_visualization.png"
    interactive_html = "output/umap/umap_3d_interactive.html"

    # Create output directory if it doesn't exist
    os.makedirs(os.path.dirname(output_image), exist_ok=True)

    # Run visualization
    visualize_features(input_file, output_image, interactive_html) 