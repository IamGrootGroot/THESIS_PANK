# PANK Thesis Project - Cell Analysis Pipeline

This repository contains a comprehensive pipeline for cell analysis in H&E stained images, including cell segmentation, tile extraction, feature extraction, and clustering analysis using deep learning models.

## Project Structure

```
.
├── 01_he_stardist_cell_segmentation_shell_compatible.groovy
├── 02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy
├── 03_uni2_feature_extraction_NEW2.py
├── 04_05_umap_3d_kmeans30.py
├── run_pipeline_01_02.sh
├── run_pipeline_03.sh
└── logs/
```

## Pipeline Components

### 1. Cell Segmentation and Tile Extraction (Steps 1-2)
- Uses QuPath and StarDist for cell segmentation
- Extracts 224x224 pixel tiles around detected cells
- Implemented in Groovy scripts for QuPath
- Automated via `run_pipeline_01_02.sh`

### 2. Feature Extraction (Step 3)
- Uses UNI2-h model from HuggingFace for feature extraction
- Processes image tiles in batches
- Saves embeddings to CSV format
- Implemented in Python
- Automated via `run_pipeline_03.sh`

### 3. Dimensionality Reduction and Clustering (Steps 4-5)
- Uses UMAP for dimensionality reduction to 3D space
- Performs K-means clustering (30 clusters)
- Generates interactive 3D visualizations
- Saves cluster assignments and visualization plots
- Implemented in Python (`04_05_umap_3d_kmeans30.py`)

## Prerequisites

### System Requirements
- Linux/Unix-based system or macOS
- NVIDIA GPU with CUDA support (recommended)
- Python 3.8+
- QuPath 0.5.0+

### Python Dependencies
```bash
torch
timm
PIL
pandas
tqdm
huggingface_hub
umap-learn
scikit-learn
plotly
```

### External Dependencies
- QuPath installation
- StarDist model file (e.g., `he_heavy_augment.pb`)
- HuggingFace account and API token

## Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd <repository-name>
```

2. Install Python dependencies:
```bash
pip install -r requirements.txt
```

3. Configure the pipeline:
   - Create a QuPath project and add your images through the QuPath GUI
   - Ensure you have a StarDist model file

## Usage

### Running Cell Segmentation and Tile Extraction
```bash
chmod +x run_pipeline_01_02.sh
./run_pipeline_01_02.sh -p /path/to/project.qpproj -m /path/to/model.pb
```

This will:
- Process all images already added to the QuPath project
- Perform cell segmentation using StarDist
- Extract 224x224 pixel tiles around detected cells
- Save logs in the `logs/` directory

### Running Feature Extraction
```bash
chmod +x run_pipeline_03.sh
./run_pipeline_03.sh
```

This will:
- Process all image tiles in the specified directory
- Extract features using the UNI2-h model
- Save embeddings to a CSV file
- Generate a timestamped log file

### Running UMAP and Clustering
```bash
python 04_05_umap_3d_kmeans30.py --input_csv output_embeddings.csv --output_dir results/
```

This will:
- Load feature embeddings from the CSV file
- Perform UMAP dimensionality reduction to 3D
- Apply K-means clustering with 30 clusters
- Generate interactive 3D visualization
- Save cluster assignments and plots

## Important Workflow Changes

### QuPath Image Loading
- Images must be added to the QuPath project **before** running the pipeline
- This must be done through the QuPath GUI due to limitations with processing NDPI files in headless mode
- The pipeline will automatically detect and process all images in the project

### Script Improvements
- Improved error handling and logging
- Separate log files for general execution, errors, and QuPath output
- Progress tracking with visual indicators
- Better command-line argument parsing

## Output

### Cell Segmentation and Tile Extraction
- Processed QuPath project with cell annotations
- Extracted cell tiles in JPG format
- Log files in `logs/` directory:
  - `pipeline_YYYYMMDD_HHMMSS.log`: General execution log
  - `pipeline_YYYYMMDD_HHMMSS_error.log`: Error log
  - `qupath_YYYYMMDD_HHMMSS.log`: QuPath verbose output

### Feature Extraction
- CSV file containing feature embeddings
- Log file with execution details
- Each row in the CSV contains:
  - Filename
  - Feature dimensions (1536 dimensions per image)

### UMAP and Clustering
- Interactive 3D visualization (HTML format)
- Cluster assignments CSV file
- Static visualization plots (PNG format)
- UMAP coordinates and cluster labels

## Error Handling

Both scripts include comprehensive error handling:
- Automatic logging of all operations
- Detailed error messages
- Graceful failure handling
- Log files for debugging

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

Copyright (c) 2024 Maxence PELLOUX
All rights reserved.

## Contact

For questions or support, please contact mpelloux1@chu-grenoble.fr