import pandas as pd
import numpy as np
from sklearn.cluster import KMeans
import umap
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
from pathlib import Path
import sys

# Add the parent directory to the path so we can import config
sys.path.append(str(Path(__file__).parent.parent))
from config import (
    FEATURES_OUTPUT, UMAP_OUTPUT, N_NEIGHBORS, MIN_DIST, N_COMPONENTS,
    get_os_path, setup_directories
)

# Ensure directories exist
setup_directories()

def load_features():
    """Load features from CSV file"""
    features_path = get_os_path(FEATURES_OUTPUT / "features.csv")
    df = pd.read_csv(features_path)
    features = df.drop('path', axis=1).values
    paths = df['path'].values
    return features, paths

def perform_umap(features):
    """Perform UMAP dimensionality reduction"""
    reducer = umap.UMAP(
        n_neighbors=N_NEIGHBORS,
        min_dist=MIN_DIST,
        n_components=N_COMPONENTS,
        random_state=42
    )
    embedding = reducer.fit_transform(features)
    return embedding

def perform_clustering(embedding, n_clusters=30):
    """Perform K-means clustering"""
    kmeans = KMeans(n_clusters=n_clusters, random_state=42)
    clusters = kmeans.fit_predict(embedding)
    return clusters

def plot_3d_umap(embedding, clusters, output_path):
    """Create 3D UMAP visualization"""
    fig = plt.figure(figsize=(10, 8))
    ax = fig.add_subplot(111, projection='3d')
    
    scatter = ax.scatter(
        embedding[:, 0],
        embedding[:, 1],
        embedding[:, 2],
        c=clusters,
        cmap='Spectral',
        s=5
    )
    
    plt.colorbar(scatter)
    ax.set_title('3D UMAP Visualization with K-means Clustering')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()

def save_results(embedding, clusters, paths):
    """Save UMAP coordinates and cluster assignments"""
    results = pd.DataFrame({
        'path': paths,
        'umap_x': embedding[:, 0],
        'umap_y': embedding[:, 1],
        'umap_z': embedding[:, 2],
        'cluster': clusters
    })
    
    output_path = get_os_path(UMAP_OUTPUT / "umap_results.csv")
    results.to_csv(output_path, index=False)

def main():
    print("Loading features...")
    features, paths = load_features()
    
    print("Performing UMAP dimensionality reduction...")
    embedding = perform_umap(features)
    
    print("Performing K-means clustering...")
    clusters = perform_clustering(embedding)
    
    print("Creating visualization...")
    output_path = get_os_path(UMAP_OUTPUT / "umap_3d.png")
    plot_3d_umap(embedding, clusters, output_path)
    
    print("Saving results...")
    save_results(embedding, clusters, paths)
    
    print("Done!")

if __name__ == "__main__":
    main()