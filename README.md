# THESIS_PANK - Cell Segmentation and Analysis Pipeline

This repository contains a complete pipeline for cell segmentation, feature extraction, and analysis of H&E stained tissue images using QuPath and deep learning models.

## Repository Description

This repository implements a comprehensive workflow for analyzing histopathological images, specifically designed for H&E stained tissue sections. The pipeline combines traditional image processing with state-of-the-art deep learning techniques to perform cell segmentation, feature extraction, and clustering analysis. The code is modular, well-documented, and designed to be easily adaptable to different tissue types and staining protocols.

## Configuration System

The pipeline uses a centralized configuration system (`config.py`) that manages all paths and parameters. This makes it easy to:
- Adapt the pipeline to different environments
- Change parameters without modifying the scripts
- Maintain consistent settings across the pipeline

Key configuration options include:
- Base directories for models, data, and output
- Processing parameters (patch size, magnification, etc.)
- Feature extraction settings
- UMAP parameters

## Pipeline Overview

The analysis pipeline consists of five main steps:

### 1. Cell Segmentation (StarDist)
- **Script**: `01_he_stardist_cell_segmentation_0.23_um_per_pixel_qupath_NEW.txt`
- **Description**: Performs nucleus segmentation using StarDist, a deep learning-based segmentation model
- **Features**:
  - Automatic detection of cell nuclei
  - Works with or without predefined annotations
  - Configurable detection threshold and pixel size
  - Includes shape and intensity measurements
  - Progress tracking for large images
<img width="807" alt="Screenshot 2025-04-16 at 21 49 12" src="https://github.com/user-attachments/assets/1333fd42-a9cd-4d6a-87b3-e1361cd1c143" />


### 2. Cell-Centered Tiling
- **Script**: `02_he_wsubfolder_jpg_cell_tile_224x224_qupath_NEW2.txt`
- **Description**: Extracts 224x224 pixel patches centered around detected cell centroids
- **Features**:
  - Organizes patches in subfolders by ROI
  - Maintains 40x magnification resolution
  - Includes boundary checking
  - Progress tracking for large datasets
  - Supports multiple image formats
![ROI_1_54001_28458_010583](https://github.com/user-attachments/assets/1c6a8d3f-0261-47d3-8a64-fdbbfb056ff6)
![ROI_1_13946_8093_039127](https://github.com/user-attachments/assets/1fdb616d-7e26-4c41-9613-8fb96fe65382)


### 3. Feature Extraction (UNI2)
- **Script**: `03_uni2_feature_extraction.py` and variants
- **Description**: Extracts 1536-dimensional feature vectors from cell patches using UNI2-h model
- **Features**:
  - Utilizes state-of-the-art vision transformer
  - Mixed precision processing for efficiency
  - Batch processing with progress tracking
  - Saves features in CSV format
  - GPU acceleration support

### 4. Dimensionality Reduction (UMAP)
- **Script**: `04_05_umap_3d_kmeans30.py` and variants
- **Description**: Reduces feature dimensions and performs clustering
- **Features**:
  - 3D UMAP visualization
  - K-means clustering
  - Memory-efficient processing options
  - Interactive visualization with Plotly
  - Multiple clustering configurations

### 5. Analysis and Visualization
- **Scripts**: Various analysis scripts
- **Description**: Performs statistical analysis and generates visualizations
- **Features**:
  - Cluster analysis
  - Spatial distribution mapping
  - Statistical comparisons
  - Custom visualization tools

## Requirements

- QuPath 0.5.1 or later
- StarDist extension for QuPath
- Python 3.x with the following packages:
  - torch
  - timm
  - huggingface_hub
  - pandas
  - umap-learn
  - scikit-learn
  - plotly
  - tqdm

## Installation

1. Install QuPath from [qupath.github.io](https://qupath.github.io)
2. Install StarDist extension through QuPath's Extension Manager
3. Install Python dependencies:
   ```bash
   pip install torch timm huggingface-hub pandas umap-learn scikit-learn plotly tqdm
   ```
4. Place the model file `he_heavy_augment.pb` in the `models` directory
5. Configure paths and parameters in `config.py`

## Usage

1. Configure your environment in `config.py`
2. Run the StarDist segmentation script in QuPath
3. Run the tiling script in QuPath
4. Run the feature extraction script:
   ```bash
   python 03_uni2_feature_extraction.py
   ```
5. Run the UMAP and clustering script:
   ```bash
   python 04_05_umap_3d_kmeans30.py
   ```

## Directory Structure

```
THESIS_PANK/
├── config.py              # Configuration file
├── models/                # Model files
├── data/                  # Input data
│   ├── patches/          # Extracted patches
│   ├── embeddings/       # Feature embeddings
│   └── visualizations/   # Generated visualizations
├── output/               # Output directories
│   ├── tiles/           # Extracted tiles
│   ├── features/        # Extracted features
│   └── umap/            # UMAP visualizations
└── scripts/             # Analysis scripts
```

## Performance Considerations

- The pipeline is optimized for GPU acceleration
- Memory-efficient options are available for large datasets
- Progress tracking is implemented for long-running processes
- Batch processing is used for feature extraction

## License

[Add your license here]

## Contact

[Add your contact information here]

## Acknowledgments

- StarDist for cell segmentation
- UNI2-h model for feature extraction
- QuPath for image analysis platform 
