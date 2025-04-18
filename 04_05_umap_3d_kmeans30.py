
import cudf
import cuml
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D  # Required for 3D plotting
from cuml.manifold import UMAP

def umap_3d_visualization(input_file, output_image):
    # 1. Load embeddings
    gdf = cudf.read_csv(input_file)

    # 2. Prepare data
    embeddings = gdf.drop(['element'], axis=1).values

    # 3. Create and fit 3D UMAP model
    umap_3d = UMAP(
        n_components=3,  # Changed to 3 dimensions
        n_neighbors=15,
        min_dist=0.1,
        random_state=42
    )

    # 4. Perform dimensionality reduction
    print("Computing 3D UMAP projection...")
    embeddings_3d = umap_3d.fit_transform(embeddings)


    print("Performing K-Means with 30 clusters...")
    kmeans = KMeans(n_clusters=30, random_state=42)
    kmeans.fit(embeddings_3d)
    cluster_labels = kmeans.predict(embeddings_3d)

    # 5. Convert to DataFrame
    df_3d = cudf.DataFrame({
        'x': embeddings_3d[:, 0],
        'y': embeddings_3d[:, 1],
        'z': embeddings_3d[:, 2],
        'cluster': cluster_labels
    })

    # 6. Create 3D visualization
    plt.figure(figsize=(16, 12))
    ax = plt.axes(projection='3d')

    # Create 3D scatter plot
    scatter = ax.scatter3D(
        df_3d['x'].to_numpy(),
        df_3d['y'].to_numpy(),
        df_3d['z'].to_numpy(),
        c=df_3d['z'].to_numpy(),  # Color by Z-value
        cmap='tab20',
        s=20,
        alpha=0.7,
        depthshade=True
    )
    # Use subsampling for very large datasets
    sample_size = 100000  # Adjust based on GPU memory
    if len(embeddings_3d) > sample_size:
        df_3d = df_3d.sample(n=sample_size)


    # Add labels and colorbar
    ax.set_title("3D UMAP Projection (30 clusters)", fontsize=14)
    ax.set_xlabel("UMAP 1", labelpad=10)
    ax.set_ylabel("UMAP 2", labelpad=10)
    ax.set_zlabel("UMAP 3", labelpad=10)

    # Add colorbar (continuous scale for cluster IDs)
    cbar = plt.colorbar(scatter, ax=ax, pad=0.1)
    cbar.set_label('Cluster ID')

    # Adjust viewing angle
    ax.view_init(elev=20, azim=45)  # Experiment with these values

    plt.show()

    # 7. Save image
    plt.savefig(output_image, dpi=350, bbox_inches='tight')
    print(f"3D visualization saved to {output_image}")


if __name__ == "__main__":
    umap_3d_visualization(
        input_file="/mnt/c/Users/LA0122630/Documents/Khellaf_Kassab_Brassard_UniClusteringColon/4_codes/py_clustering/output_embeddings/embeddings_pancreas.csv",  # Your embeddings file
        output_image="/mnt/c/Users/LA0122630/Documents/Khellaf_Kassab_Brassard_UniClusteringColon/UNI_embeddings/umap_3d_pancreas.png"  # Output image name
    )