# PANK Thesis Project - Cell Analysis Pipeline

This repository contains a comprehensive pipeline for cell analysis in H&E stained images, including cell segmentation, tile extraction, feature extraction, and clustering analysis using deep learning models.

## Project Structure

```
.
├── 00_create_project.groovy
├── 00a_import_trident_geojson.groovy
├── 01_he_stardist_cell_segmentation_shell_compatible.groovy
├── 02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy
├── 03_uni2_feature_extraction_NEW2.py
├── 04_05_umap_3d_kmeans30.py
├── run_trident_segmentation.py
├── run_pipeline_01_02.sh
├── run_pipeline_03.sh
└── logs/
```

## Project Creation

The `00_create_project.groovy` script automates the creation of a QuPath project from a directory of images. It can be run either from the QuPath GUI or from the command line.

### Features
- Creates a new QuPath project in a specified directory
- Automatically detects and adds supported image formats
- Handles multi-scene images (e.g., VSI files)
- Supports pyramidalization of images for better performance
- Generates thumbnails for quick preview
- Estimates image type (e.g., Brightfield H&E)

### Usage

#### From Command Line
```bash
qupath script 00_create_project.groovy --args /path/to/image/directory
```

#### From QuPath GUI
1. Open QuPath
2. Go to Script -> Run...
3. Select `00_create_project.groovy`
4. Choose your image directory when prompted

### Configuration
The script includes a `pyramidalizeImages` flag (default: `true`) that determines whether images should be pyramidalized when added to the project. Pyramidalization improves performance for large images but requires more disk space.

## Pipeline Components

### 0. TRIDENT Tissue Segmentation (New Preliminary Step)
- Uses the [TRIDENT toolkit](https://github.com/mahmoodlab/TRIDENT) for initial tissue segmentation on whole-slide images.
- This step is performed by a standalone Python script (`run_trident_segmentation.py`) that processes a directory of images.
- TRIDENT's `run_single_slide.py` is called for each image with the `--task segment` argument.
- Output: GeoJSON files containing tissue polygons, saved in a structured output directory:
  `<trident_base_output_dir>/<slide_name_without_extension>/segmentations/<slide_name_without_extension>.geojson`.
- These GeoJSON files are then imported into the QuPath project using the `00a_import_trident_geojson.groovy` script.

#### TRIDENT Prerequisites:
- **Python Environment:** Python 3.8+ is recommended.
- **TRIDENT Toolkit Installation:** 
    1. Clone the TRIDENT repository: `git clone https://github.com/mahmoodlab/TRIDENT.git`
    2. Navigate into the cloned directory: `cd TRIDENT`
    3. Install TRIDENT and its dependencies (preferably in a virtual environment): `pip install -e .`
    This will install PyTorch and other necessary libraries. The `run_single_slide.py` script will be in the root of this cloned TRIDENT directory.
- **CUDA-Enabled GPU:** While TRIDENT (via PyTorch) might technically run on a CPU, a CUDA-enabled NVIDIA GPU is **highly recommended** for acceptable performance. Processing whole-slide images for segmentation is computationally intensive and will be extremely slow on a CPU.
- **Model Dependencies:** Specific TRIDENT models might have additional dependencies. TRIDENT typically notifies you if these are missing.

### 1. Cell Segmentation and Tile Extraction (Steps 1-2)
- Uses QuPath and StarDist for cell segmentation **within the TRIDENT-defined tissue regions** (annotations with class "Tissue (TRIDENT)").
- Extracts 224x224 pixel tiles around detected cells.
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
- TRIDENT toolkit installation (see TRIDENT Prerequisites above) and its `run_single_slide.py` script accessible.

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

### Step 0a: Run TRIDENT Tissue Segmentation (Python Script)

This script processes all whole-slide images in a specified input directory using TRIDENT to generate tissue segmentation GeoJSON files. This step should be run **before** importing into QuPath or running the main QuPath pipeline.

```bash
chmod +x run_trident_segmentation.py
python run_trident_segmentation.py \
    --image_dir /path/to/your/wsi_files \
    --trident_output_dir /path/to/trident_outputs \
    --trident_script_path /path/to/TRIDENT/run_single_slide.py
```

- `--image_dir`: Directory containing your raw whole-slide image files (e.g., .ndpi, .svs).
- `--trident_output_dir`: Base directory where TRIDENT will create subdirectories for each slide's output (including the GeoJSON files).
- `--trident_script_path`: Full path to TRIDENT's `run_single_slide.py`.

### Step 0b: Import TRIDENT GeoJSON into QuPath (Groovy Script)

After running TRIDENT segmentation, use this QuPath script to import the generated GeoJSON files into your QuPath project. Ensure your QuPath project is open and contains the images processed by TRIDENT.

```bash
/path/to/QuPath script 00a_import_trident_geojson.groovy --args /path/to/trident_outputs/
```

- Replace `/path/to/QuPath` with your QuPath executable path.
- The argument `/path/to/trident_outputs/` must be the **same** directory used as `--trident_output_dir` in the Python script.
- This will add the TRIDENT segmentations as annotations with the class "Tissue (TRIDENT)" to the corresponding images in QuPath.

### Step 1 & 2: Running Cell Segmentation and Tile Extraction (QuPath pipeline)

After importing TRIDENT annotations, run the existing `run_pipeline_01_02.sh` script. This script will perform cell segmentation using StarDist (now configured to run specifically within the imported "Tissue (TRIDENT)" annotations) and then extract cell tiles.

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
- Enhanced image loading and processing capabilities
- Improved cell segmentation accuracy with StarDist
- Optimized tile extraction process
- Better memory management for large datasets

### Recent Updates
- Enhanced compatibility with different image formats
- Improved error handling for image loading failures
- Better progress reporting during long operations
- Optimized memory usage during tile extraction
- Enhanced logging system with more detailed information
- Improved handling of QuPath project structure
- Better integration with StarDist model
- Enhanced support for batch processing
- **Added preliminary tissue segmentation step using TRIDENT toolkit.**
- **Added Python script to run TRIDENT and Groovy script to import its GeoJSON output into QuPath.**
- **Modified StarDist script (`01_he_stardist_cell_segmentation_shell_compatible.groovy`) to process only within "Tissue (TRIDENT)" annotations.**

## Output

### QuPath Project after TRIDENT Import
- QuPath project images will have tissue areas annotated with the class "Tissue (TRIDENT)".

### Cell Segmentation and Tile Extraction
- Processed QuPath project with cell annotations
- Extracted cell tiles in JPG format
- Log files in `logs/` directory:
  - `pipeline_YYYYMMDD_HHMMSS.log`: General execution log
  - `pipeline_YYYYMMDD_HHMMSS_error.log`: Error log
  - `qupath_YYYYMMDD_HHMMSS.log`: QuPath verbose output

### TRIDENT Segmentation Output (prior to QuPath import)
- GeoJSON files located at `<trident_output_dir>/<slide_name_no_ext>/segmentations/<slide_name_no_ext>.geojson`

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