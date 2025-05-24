# PANK Thesis Project - Cell Analysis Pipeline

This repository contains a comprehensive pipeline for cell analysis in H&E stained images, including cell segmentation, tile extraction, feature extraction, and clustering analysis using deep learning models.

## Project Structure

```
.
├── 00_create_project.groovy
├── 00a_import_trident_geojson.groovy
├── 00b_export_annotated_thumbnails_qc.groovy
├── 01_he_stardist_cell_segmentation_shell_compatible.groovy
├── 02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy
├── 03_uni2_feature_extraction_NEW2.py
├── 04_05_umap_3d_kmeans30.py
├── run_trident_segmentation.py
├── generate_drive_token.py
├── upload_contours_to_drive.py
├── upload_qc_thumbnails_to_drive.py
├── run_import_trident_geojson.sh
├── run_qc_thumbnail_export.sh
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

### 0. TRIDENT Tissue Segmentation
Uses the [TRIDENT toolkit](https://github.com/mahmoodlab/TRIDENT) for initial tissue segmentation on whole-slide images.

#### Features
- Automated batch processing of whole-slide images
- Hole removal in segmentation results (`--remove_holes` option)
- Support for multiple image formats (`.svs`, `.ndpi`, `.tiff`, etc.)
- GPU acceleration support
- Quality control visualization outputs

#### Usage
```bash
python run_trident_segmentation.py \
    --image_dir /path/to/slides \
    --trident_output_dir ./trident_output \
    --trident_script_path /path/to/trident/run_batch_of_slides.py \
    --gpu 0
```

### Quality Control with Google Drive Integration

The pipeline includes tools for uploading segmentation results to Google Drive for quality control review.

#### Setup Google Drive Authentication
1. Create credentials:
   - Go to Google Cloud Console
   - Create a new project or select existing one
   - Enable Google Drive API
   - Create OAuth 2.0 credentials
   - Download credentials as `drive_credentials.json`

2. Generate authentication token:
```bash
python generate_drive_token.py --credentials_file drive_credentials.json
```
This will create a `token.json` file after browser authentication.

3. Upload contour visualizations:
```bash
python upload_contours_to_drive.py \
    --trident_output_dir ./trident_output \
    --credentials_file ./drive_credentials.json \
    --token_file ./token.json \
    --folder_name "PDAC5_QC_Contours"
```

#### Security Notes
- Credential files (`drive_credentials.json`, `token.json`) are automatically excluded from git
- Token refresh is handled automatically
- Only requested scopes are used (file creation and upload)

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

#### Manual Import (Single Project)
```bash
/path/to/QuPath script 00a_import_trident_geojson.groovy --args /path/to/trident_outputs/
```

- Replace `/path/to/QuPath` with your QuPath executable path.
- The argument `/path/to/trident_outputs/` must be the **same** directory used as `--trident_output_dir` in the Python script.
- This will add the TRIDENT segmentations as annotations with the class "Tissue (TRIDENT)" to the corresponding images in QuPath.

#### Automated Import (Multiple Projects)

For batch processing of multiple QuPath projects, use the automated bash script:

```bash
chmod +x run_import_trident_geojson.sh

# Test with your 5-image project first
./run_import_trident_geojson.sh -t ./trident_output/contours_geoJSON -s

# Process a specific project
./run_import_trident_geojson.sh -t ./trident_output/contours_geoJSON -p QuPath_MP_PDAC100/project.qpproj

# Process all projects (600 images across all projects)
./run_import_trident_geojson.sh -t ./trident_output/contours_geoJSON -a
```

**Script Features:**
- **Flexible QuPath path**: Set via environment variable (`export QUPATH_PATH=/path/to/QuPath`) or script configuration
- **Multiple processing modes**: 
  - `-s, --test`: Process only test project (QuPath_MP_PDAC5)
  - `-p, --project`: Process specific project file
  - `-a, --all`: Process all QuPath projects in current directory
- **Comprehensive logging**: Timestamped logs with progress tracking
- **Error handling**: Validates inputs and handles failures gracefully
- **Progress tracking**: Shows progress when processing multiple projects

**Before Running:**
1. **Set the correct QuPath path** for your server:
   ```bash
   export QUPATH_PATH=/path/to/your/QuPath/installation
   ```

2. **Verify your TRIDENT output structure** matches expected format:
   ```
   trident_output/contours_geoJSON/
   ├── 00000664-00767663-23HI014130-1-A01-1/
   │   └── segmentations/
   │       └── 00000664-00767663-23HI014130-1-A01-1.geojson
   └── ...
   ```

**Recommended Testing Approach:**
1. Start with test project: `./run_import_trident_geojson.sh -t ./trident_output/contours_geoJSON -s`
2. Try one larger project: `./run_import_trident_geojson.sh -t ./trident_output/contours_geoJSON -p QuPath_MP_PDAC100/project.qpproj`
3. Process all projects: `./run_import_trident_geojson.sh -t ./trident_output/contours_geoJSON -a`

The script creates detailed logs in the `logs/` directory for tracking progress and debugging.

### Quality Control Workflow for TRIDENT Annotations

After importing TRIDENT annotations into QuPath, you can run a comprehensive QC workflow that exports annotated thumbnails and uploads them to Google Drive for visual validation.

#### Features
- **Automated thumbnail export** with TRIDENT annotation overlays (green contours)
- **Batch processing** across multiple QuPath projects  
- **Google Drive integration** for collaborative review
- **Comprehensive logging** with detailed progress tracking
- **Duplicate prevention** and error handling
- **Visual quality assessment** with annotation summary reports

#### Prerequisites
1. **Google Drive API Setup** (same as TRIDENT QC workflow):
   ```bash
   python generate_drive_token.py --credentials_file drive_credentials.json
   ```

2. **TRIDENT annotations imported** into QuPath projects using `00a_import_trident_geojson.groovy`

#### Usage

##### Test Mode (5-image project)
```bash
./run_qc_thumbnail_export.sh -s -r /path/to/trident_output
```

##### Single Project
```bash
./run_qc_thumbnail_export.sh \
    -p /path/to/project.qpproj \
    -r /path/to/trident_output \
    -o ./qc_thumbnails \
    -f "ProjectName_QC_Thumbnails"
```

##### All Projects
```bash
./run_qc_thumbnail_export.sh \
    -a \
    -r /path/to/trident_output \
    -c ./drive_credentials.json \
    -t ./token.json
```

#### Script Options
- `-s, --test`: Process test project only (QuPath_MP_PDAC5)
- `-a, --all`: Process all QuPath projects in current directory  
- `-p, --project`: Process specific project file
- `-r, --trident`: **Required** - Path to TRIDENT output directory
- `-o, --output`: Output directory for thumbnails (default: qc_thumbnails)
- `-c, --credentials`: Google Drive credentials file (default: drive_credentials.json)
- `-t, --token`: Token file (default: token.json)
- `-f, --folder`: Google Drive folder name (default: auto-generated)

#### Workflow Steps
1. **TRIDENT Import**: Automatically imports GeoJSON annotations into QuPath
2. **Thumbnail Export**: Exports 2048px thumbnails with green TRIDENT overlays
3. **Drive Upload**: Uploads thumbnails to organized Google Drive folders
4. **QC Summary**: Generates detailed reports with annotation statistics

#### Output Structure
```
qc_thumbnails/
├── ProjectName/
│   ├── QC_Summary_YYYYMMDD_HHMMSS.txt
│   ├── image1_qc_thumbnail.jpg
│   ├── image2_qc_thumbnail.jpg
│   └── ...
└── logs/
    ├── qc_workflow_YYYYMMDD_HHMMSS.log
    ├── qupath_trident_YYYYMMDD_HHMMSS.log
    └── qupath_qc_YYYYMMDD_HHMMSS.log
```

#### QC Summary Report
Each project generates a summary showing:
- **Total images processed**
- **Images with TRIDENT annotations** vs. **no annotations found**
- **Individual image status** with warning indicators
- **Processing statistics** and error counts

#### Google Drive Organization
Uploads are organized in folders:
- `ProjectName_QC_Thumbnails_YYYYMMDD/`
  - Individual thumbnail images
  - QC summary report
  - Timestamp-based organization

#### Troubleshooting
- **"No TRIDENT annotations found"**: Ensure TRIDENT import completed successfully
- **"TRIDENT directory not found"**: Verify the `-r` path points to your TRIDENT output directory
- **Google Drive errors**: Check credentials and token files are valid
- **QuPath script errors**: Review the separate log files in `logs/` directory

This QC workflow enables efficient visual validation of TRIDENT tissue segmentations across large datasets before proceeding with the main analysis pipeline.

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