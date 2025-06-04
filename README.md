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

### Basic Usage

#### 1. Test Your Setup
```bash
# Test with QuPath_MP_PDAC100 project
./test_unified_pipeline.sh -p ../QuPath_MP_PDAC100 -v
```

#### 2. Run Complete Pipeline for QuPath_MP_PDAC100

The pipeline consists of multiple steps that must be run sequentially:

```bash
# Step 0: Tissue Segmentation (TRIDENT) - Optional, only if needed
python run_trident_segmentation.py \
    --qupath_project ../QuPath_MP_PDAC100 \
    --trident_output_dir ./trident_output_pdac100 \
    --trident_script_path /path/to/trident/run_batch_of_slides.py

# Import TRIDENT results into QuPath (if Step 0 was performed)
./run_pipeline_00a_import_trident_geojson.sh -t ./trident_output_pdac100 -p ../QuPath_MP_PDAC100

# Step 1: Cell Detection (StarDist) - Process QuPath_MP_PDAC100 project
./run_pipeline_01_unified_stardist.sh -p ../QuPath_MP_PDAC100

# Step 2: Tile Extraction (automatically included in Step 1)
# ./run_pipeline_02_batch_tiling.sh -p ../QuPath_MP_PDAC100  # Only if running separately

# Step 3: Feature Extraction
./run_pipeline_03.sh \
    -i output/tiles \
    -o features_pdac100.csv \
    -t $HUGGING_FACE_TOKEN \
    -b 32

# Step 4: Clustering & Visualization
python 04_05_umap_3d_kmeans30.py \
    --input_csv features_pdac100.csv \
    --output_dir results_pdac100/

# Optional: Generate QC thumbnails and upload to Google Drive
./run_pipeline_01_unified_qc_export.sh -p ../QuPath_MP_PDAC100 -u
```

**Project-specific outputs:**
- **QuPath Project**: `../QuPath_MP_PDAC100/`
- **Tiles**: `output/tiles/` (extracted from PDAC100 cells)
- **Features**: `features_pdac100.csv` (1536-dimensional embeddings)
- **Results**: `results_pdac100/` (clustering and visualizations)
- **QC Images**: `qc_thumbnails/` (quality control outputs)

**What each script does:**
- `run_trident_segmentation.py`: Tissue segmentation only
- `run_pipeline_01_unified_stardist.sh`: Cell detection + tile extraction
- `run_pipeline_03.sh`: Feature extraction only  
- `04_05_umap_3d_kmeans30.py`: Clustering and visualization only

## Pipeline Steps

### Step 0: Tissue Segmentation (TRIDENT)

Automatically segments tissue regions from whole-slide images. Supports both directory-based and QuPath project-based input.

![03000664-00781901-22HI053912-1-A01-6_qc_thumbnail](https://github.com/user-attachments/assets/eed93c55-66a1-4d6a-a7d5-95d15c9dd0cb)

**Directory-based approach:**
```bash
python run_trident_segmentation.py \
    --image_dir /path/to/slides \
    --trident_output_dir ./trident_output \
    --trident_script_path /path/to/trident/run_batch_of_slides.py
```

**QuPath project-based approach (NEW):**
```bash
# Process images from a specific QuPath project
python run_trident_segmentation.py \
    --qupath_project ../QuPath_MP_PDAC100 \
    --trident_output_dir ./trident_output_pdac100 \
    --trident_script_path /path/to/trident/run_batch_of_slides.py \
    --gpu 0

# With custom temporary directory
python run_trident_segmentation.py \
    --qupath_project ../QuPath_MP_PDAC100 \
    --trident_output_dir ./trident_output_pdac100 \
    --trident_script_path /path/to/trident/run_batch_of_slides.py \
    --temp_dir /tmp/trident_work \
    --keep_temp
```

**Features:**
- **Directory Input**: Process all supported WSI files in a directory
- **QuPath Project Input**: Extract and process images directly from QuPath projects
- **Automatic Image Discovery**: Reads `server.json` files to locate actual image paths
- **Temporary Symlinks**: Creates temporary directory with symbolic links for seamless processing
- **Flexible Cleanup**: Option to preserve temporary files for debugging

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
```

**Note**: Tile extraction can be run as a separate step or is automatically included when using the unified StarDist pipeline.

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

## Environment Variables

Set the following environment variables before running the pipeline:

```bash
# Required
export HUGGING_FACE_TOKEN="your_hf_token_here"
export MODEL_PATH="/path/to/your/he_heavy_augment.pb"

# Optional - QuPath paths (if not in default locations)
export QUPATH_06_PATH="/path/to/qupath_0.6/bin/QuPath"
export QUPATH_051_PATH="/path/to/qupath_0.5.1/bin/QuPath"

# Optional - Output directories
export TILES_OUTPUT="/path/to/tiles/output"
export OUTPUT_DIR="/path/to/general/output"
```

## Quick Start

1. **Set up environment:**
   ```bash
   # Set required environment variables
   export HUGGING_FACE_TOKEN="your_token_here"
   export MODEL_PATH="./models/he_heavy_augment.pb"
   
   # Install Python dependencies
   pip install -r requirements_gdrive.txt
   ```

2. **Run the complete pipeline:**
   ```bash
   ./run_pipeline_01_unified_stardist.sh -p /path/to/project.qpproj -m gpu
   ```

## Pipeline Overview

The pipeline consists of several stages:

1. **Import TRIDENT annotations** (`00a_import_trident_geojson.groovy`)
2. **Cell segmentation** (`01_he_stardist_cell_segmentation_*.groovy`)
3. **Tile extraction** (`02_he_wsubfolder_jpg_cell_tile_224x224_*.groovy`)
4. **Feature extraction** (`03_uni2_feature_extraction*.py`)
5. **Analysis and visualization** (`04_05_umap_3d_kmeans30*.py`)

## Usage Examples

### Basic cell segmentation:
```bash
./run_pipeline_01_unified_stardist.sh -p project.qpproj -m cpu
```

### Process all projects with GPU acceleration:
```bash
./run_pipeline_01_unified_stardist.sh -a -m gpu
```

### With quality control and upload:
```bash
./run_pipeline_01_unified_qc_export.sh -p project.qpproj -n 10 -u -t token.json -m gpu
```
