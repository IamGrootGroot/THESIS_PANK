# Cellular Level Analysis Pipeline For Pathology Diagnosis and Prognosis Prediction

![ChatGPT Image May 30, 2025 at 04_04_05 PM](https://github.com/user-attachments/assets/7d9c9036-5df3-4d95-879d-a9203c68da14)

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

### Environment Setup
```bash
# Required
export HUGGING_FACE_TOKEN="your_hf_token_here"
export MODEL_PATH="./models/he_heavy_augment.pb"

# Optional - QuPath paths (if not in default locations)
export QUPATH_06_PATH="/path/to/qupath_0.6/bin/QuPath"
export QUPATH_051_PATH="/path/to/qupath_0.5.1/bin/QuPath"
```

### Basic Usage

#### Test Your Setup
```bash
./test_unified_pipeline.sh -p /path/to/project.qpproj -v
```

#### Complete Pipeline
The pipeline requires multiple steps to be run sequentially:

```bash
# Step 1: Cell Detection + Tile Extraction
./run_pipeline_01_unified_stardist.sh -p /path/to/project.qpproj

# Step 2: Feature Extraction  
./run_pipeline_03.sh \
    -i output/tiles \
    -o features.csv \
    -t $HUGGING_FACE_TOKEN \
    -b 32

# Step 3: Clustering & Visualization
python 04_05_umap_3d_kmeans30.py \
    --input_csv features.csv \
    --output_dir results/
```

**Note:** The "unified" pipeline (`run_pipeline_01_unified_stardist.sh`) only handles cell detection and tile extraction. You must run feature extraction and clustering as separate steps.

## Pipeline Steps

### Step 0: Tissue Segmentation (TRIDENT) - Optional

Automatically segments tissue regions from whole-slide images.

![03000664-00781901-22HI053912-1-A01-6_qc_thumbnail](https://github.com/user-attachments/assets/eed93c55-66a1-4d6a-a7d5-95d15c9dd0cb)

```bash
# Process images from QuPath project
python run_trident_segmentation.py \
    --qupath_project /path/to/project \
    --trident_output_dir ./trident_output \
    --trident_script_path /path/to/trident/run_batch_of_slides.py

# Import results into QuPath
./run_pipeline_00a_import_trident_geojson.sh -t ./trident_output -p /path/to/project
```

### Step 1: Cell Detection (StarDist)

Detects individual cells within tissue regions using StarDist.

![03000664-00781897-22HI053907-1-A02-6_cell_detection_qc](https://github.com/user-attachments/assets/a6257ce2-f873-4079-8f64-611c9820cbe3)

**Automatic Configuration:**
- **GPU Mode**: QuPath 0.5.1 + CUDA → Faster processing
- **CPU Mode**: QuPath 0.6 + Multi-core → High compatibility

```bash
# Automatic detection (recommended)
./run_pipeline_01_unified_stardist.sh -p /path/to/project.qpproj

# Force specific mode
./run_pipeline_01_unified_stardist.sh -p /path/to/project.qpproj -m gpu
./run_pipeline_01_unified_stardist.sh -p /path/to/project.qpproj -m cpu
```

### Step 2: Tile Extraction

Extracts 224x224 pixel patches centered around each detected cell:

![ROI_1_30826_26867_057335](https://github.com/user-attachments/assets/67a0403d-af2a-4ae9-9462-abe360d36593)
![ROI_1_34975_7797_057278](https://github.com/user-attachments/assets/3c7a637b-0033-40de-b1d9-c32a034669ac)
![ROI_1_35206_7874_057376](https://github.com/user-attachments/assets/1d789512-85a8-478f-96ae-45b742b763bc)

**Note**: Tile extraction is automatically included in Step 1, or can be run separately:

```bash
./run_pipeline_02_batch_tiling.sh -p /path/to/project.qpproj
```

### Step 3: Feature Extraction

Extracts 1536-dimensional features from each tile using UNI2-h model.

```bash
./run_pipeline_03.sh \
    -i output/tiles \
    -o features.csv \
    -t $HUGGING_FACE_TOKEN \
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

### Generate QC Thumbnails
```bash
# Export QC images
./run_pipeline_01_unified_qc_export.sh -p /path/to/project.qpproj

# Upload to Google Drive (optional)
./run_pipeline_01_unified_qc_export.sh -p /path/to/project.qpproj -u
```

### QC Outputs
- **Tissue segmentation thumbnails** with contour overlays
- **Cell detection thumbnails** showing detected cells
- **Summary reports** with statistics and warnings

## Usage Examples

### Cell Detection & Tile Extraction
```bash
# Single project with GPU acceleration
./run_pipeline_01_unified_stardist.sh -p /path/to/project.qpproj -m gpu

# Process all projects in directory
./run_pipeline_01_unified_stardist.sh -a -m cpu

# With quality control export
./run_pipeline_01_unified_qc_export.sh -p /path/to/project.qpproj -n 10 -u
```

### Complete Pipeline Workflow
```bash
# 1. Cell detection + tile extraction
./run_pipeline_01_unified_stardist.sh -p /path/to/project.qpproj -m gpu

# 2. Feature extraction
./run_pipeline_03.sh -i output/tiles -o features.csv -t $HUGGING_FACE_TOKEN -b 32

# 3. Clustering & visualization
python 04_05_umap_3d_kmeans30.py --input_csv features.csv --output_dir results/
```

### Custom Configurations
```bash
# Custom QuPath installation
./run_pipeline_01_unified_stardist.sh -q /path/to/QuPath -p /path/to/project.qpproj

# Specify output directory
export TILES_OUTPUT="/custom/tiles/path"
./run_pipeline_01_unified_stardist.sh -p /path/to/project.qpproj
```

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

## Output Structure

```
output/
├── tiles/                    # Extracted cell patches
├── features.csv             # Feature embeddings
├── umap_results.csv         # Cluster assignments
├── qc_thumbnails/           # Quality control images
└── visualizations/          # UMAP plots and reports
```

## Hardware Optimization

The pipeline automatically detects and optimizes for your hardware:

- **GPU Servers**: Uses CUDA acceleration with QuPath 0.5.1
- **CPU Servers**: Optimizes for multi-core processing with QuPath 0.6
- **Memory Management**: Adjusts batch sizes based on available resources

## Troubleshooting

### Common Issues

**"QuPath not found"**
```bash
./run_pipeline_01_unified_stardist.sh -q /path/to/QuPath -p /path/to/project.qpproj
```

**"No TRIDENT annotations found"**
```bash
./run_pipeline_00a_import_trident_geojson.sh -t ./trident_output -p /path/to/project.qpproj
```

**"CUDA not available"**
```bash
./run_pipeline_01_unified_stardist.sh -p /path/to/project.qpproj -m cpu
```

### Log Files
All operations generate detailed logs in the `logs/` directory:
- `pipeline_*.log` - Main execution logs
- `qupath_*.log` - QuPath-specific output
- `*_error.log` - Error details

## Google Drive Integration

Upload QC results for collaborative review:

```bash
# Setup authentication
python generate_drive_token.py --credentials_file drive_credentials.json

# Upload thumbnails with QC export
./run_pipeline_01_unified_qc_export.sh -p /path/to/project.qpproj -u
```

See [GDRIVE_SETUP.md](GDRIVE_SETUP.md) for detailed setup instructions.

## Citation

If you use this pipeline in your research, please cite:

```
PANK Thesis Project - Cell Analysis Pipeline
Copyright (c) 2024 Maxence PELLOUX
```

## License

Copyright (c) 2024 Maxence PELLOUX. All rights reserved.

## Contact

For questions or support: mpelloux1@chu-grenoble.fr
