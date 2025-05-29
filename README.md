# PANK Thesis Project - Cell Analysis Pipeline

A comprehensive pipeline for cell analysis in H&E stained images, including tissue segmentation, cell detection, tile extraction, feature extraction, and clustering analysis using deep learning models.

## Overview

This pipeline processes whole-slide images through several automated steps:

1. **Tissue Segmentation** (TRIDENT) - Identifies tissue regions
2. **Cell Detection** (StarDist) - Detects individual cells within tissue
3. **Tile Extraction** - Extracts 224x224 patches around each cell
4. **Feature Extraction** (UNI2-h) - Generates embeddings for each tile
5. **Clustering & Visualization** (UMAP + K-means) - Groups similar cells

## Quick Start

### Prerequisites
- Linux/Unix system with Python 3.8+
- QuPath 0.5.1+ installed
- NVIDIA GPU with CUDA (recommended)
- HuggingFace account and API token

### Installation
```bash
git clone <repository-url>
cd <repository-name>
pip install -r requirements.txt
```

### Basic Usage

#### 1. Test Your Setup
```bash
./test_unified_pipeline.sh -v
```

#### 2. Run Complete Pipeline
```bash
# Process test project (5 images)
./run_pipeline_01_unified_stardist.sh -s

# Process all projects
./run_pipeline_01_unified_stardist.sh -a

# Extract features
./run_pipeline_03.sh -i output/tiles -o features.csv -t YOUR_HF_TOKEN

# Generate visualizations
python 04_05_umap_3d_kmeans30.py --input_csv features.csv --output_dir results/
```

## Pipeline Steps

### Step 0: Tissue Segmentation (TRIDENT)

Automatically segments tissue regions from whole-slide images.

![03000664-00781901-22HI053912-1-A01-6_qc_thumbnail](https://github.com/user-attachments/assets/eed93c55-66a1-4d6a-a7d5-95d15c9dd0cb)

```bash
python run_trident_segmentation.py \
    --image_dir /path/to/slides \
    --trident_output_dir ./trident_output \
    --trident_script_path /path/to/trident/run_batch_of_slides.py
```

### Step 1: Cell Detection (StarDist)

Detects individual cells within TRIDENT-defined tissue regions using StarDist.

![03000664-00781897-22HI053907-1-A02-6_cell_detection_qc](https://github.com/user-attachments/assets/a6257ce2-f873-4079-8f64-611c9820cbe3)

**Automatic Configuration:**
- **GPU Mode**: QuPath 0.5.1 + CUDA → Faster processing
- **CPU Mode**: QuPath 0.6 + Multi-core → High compatibility

```bash
# Automatic detection (recommended)
./run_pipeline_01_unified_stardist.sh -s

# Force specific mode
./run_pipeline_01_unified_stardist.sh -s -m gpu
./run_pipeline_01_unified_stardist.sh -s -m cpu
```

### Step 2: Tile Extraction

Extracts 224x224 pixel patches centered around each detected cell:

![ROI_1_30826_26867_057335](https://github.com/user-attachments/assets/67a0403d-af2a-4ae9-9462-abe360d36593)
![ROI_1_34975_7797_057278](https://github.com/user-attachments/assets/3c7a637b-0033-40de-b1d9-c32a034669ac)
![ROI_1_35206_7874_057376](https://github.com/user-attachments/assets/1d789512-85a8-478f-96ae-45b742b763bc)


```bash
# Extract tiles from detected cells
./run_pipeline_02_batch_tiling.sh -s

# Or run both steps together (convenience)
./run_pipeline_01_unified_stardist.sh -s  # Includes both cell detection and tiling
```

### Step 3: Feature Extraction

Extracts 1536-dimensional features from each tile using UNI2-h model.

```bash
./run_pipeline_03.sh \
    -i output/tiles \
    -o features.csv \
    -t YOUR_HUGGINGFACE_TOKEN \
    -b 32
```

### Step 4: Clustering & Visualization

Performs dimensionality reduction and clustering analysis.

![umap_3d_visualization](https://github.com/user-attachments/assets/b56f97fd-5802-402b-b004-3fbc8b316998)


```bash
python 04_05_umap_3d_kmeans30.py \
    --input_csv features.csv \
    --output_dir results/
```

## Quality Control

### Google Drive Integration

Upload results to Google Drive for collaborative review:

```bash
# Setup authentication
python generate_drive_token.py --credentials_file drive_credentials.json

# Upload QC thumbnails
./run_pipeline_01_unified_qc_export.sh -s -u
```

### QC Outputs
- **Tissue segmentation thumbnails** with contour overlays
- **Cell detection thumbnails** showing detected cells
- **Summary reports** with statistics and warnings

## Project Structure

```
.
├── 00_create_project.groovy              # QuPath project creation
├── 00a_import_trident_geojson.groovy     # Import tissue segmentations
├── 01_he_stardist_cell_segmentation*.groovy  # Cell detection scripts
├── 02_he_wsubfolder_jpg_cell_tile*.groovy    # Tile extraction scripts
├── 03_uni2_feature_extraction_NEW2.py    # Feature extraction
├── 04_05_umap_3d_kmeans30.py            # Clustering and visualization
├── run_trident_segmentation.py           # TRIDENT wrapper
├── run_pipeline_01_unified_stardist.sh   # Main pipeline script
├── run_pipeline_03.sh                    # Feature extraction script
└── logs/                                 # Execution logs
```

## Configuration

### Hardware Optimization
The pipeline automatically detects and optimizes for your hardware:

- **GPU Servers**: Uses CUDA acceleration with QuPath 0.5.1
- **CPU Servers**: Optimizes for multi-core processing with QuPath 0.6
- **Memory Management**: Adjusts batch sizes based on available resources

### Custom Paths
```bash
# Custom QuPath installation
export QUPATH_PATH=/path/to/your/QuPath

# Custom model path (in scripts)
MODEL_PATH="/path/to/he_heavy_augment.pb"
```

## Troubleshooting

### Common Issues

**"QuPath not found"**
```bash
# Specify custom QuPath path
./run_pipeline_01_unified_stardist.sh -q /path/to/QuPath -s
```

**"No TRIDENT annotations found"**
```bash
# Import tissue segmentations first
./run_pipeline_00a_import_trident_geojson.sh -t ./trident_output -s
```

**"CUDA not available"**
```bash
# Use CPU mode
./run_pipeline_01_unified_stardist.sh -s -m cpu
```

### Log Files
All operations generate detailed logs in the `logs/` directory:
- `pipeline_*.log` - Main execution logs
- `qupath_*.log` - QuPath-specific output
- `*_error.log` - Error details

## Output

### Generated Files
- **Cell tiles**: 224x224 pixel images around detected cells
- **Feature embeddings**: CSV with 1536-dimensional vectors
- **Cluster assignments**: Cell groupings and UMAP coordinates
- **QC thumbnails**: Visual validation images
- **Interactive visualizations**: 3D UMAP plots

### Directory Structure
```
output/
├── tiles/                    # Extracted cell patches
├── features.csv             # Feature embeddings
├── umap_results.csv         # Cluster assignments
├── qc_thumbnails/           # Quality control images
└── visualizations/          # UMAP plots and reports
```

## Citation

If you use this pipeline in your research, please cite:

```
PANK Thesis Project - Cell Analysis Pipeline
Copyright (c) 2024 Maxence PELLOUX
```

## Contact

For questions or support: mpelloux1@chu-grenoble.fr

## License

Copyright (c) 2024 Maxence PELLOUX. All rights reserved.
