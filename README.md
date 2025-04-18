# THESIS_PANK - Cell Segmentation and Analysis Pipeline

This repository contains scripts for cell segmentation and analysis using QuPath and StarDist.

## Project Structure

- `01_he_stardist_cell_segmentation_0.23_um_per_pixel_qupath_NEW.txt`: StarDist-based cell segmentation script
- `02_he_wsubfolder_jpg_cell_tile_224x224_qupath_NEW2.txt`: Cell-centered tiling script for patch extraction

## Requirements

- QuPath 0.5.1 or later
- StarDist extension for QuPath
- Python 3.x (for future analysis scripts)

## Installation

1. Install QuPath from [qupath.github.io](https://qupath.github.io)
2. Install StarDist extension through QuPath's Extension Manager
3. Place the model file `he_heavy_augment.pb` in the specified directory

## Usage

1. Run the StarDist segmentation script (`01_he_stardist_cell_segmentation_0.23_um_per_pixel_qupath_NEW.txt`)
2. Run the tiling script (`02_he_wsubfolder_jpg_cell_tile_224x224_qupath_NEW2.txt`)

## Configuration

Update the following paths in the scripts:
- Model path in `01_he_stardist_cell_segmentation_0.23_um_per_pixel_qupath_NEW.txt`
- Output directory in `02_he_wsubfolder_jpg_cell_tile_224x224_qupath_NEW2.txt`

## License

[Add your license here]

## Contact

[Add your contact information here] 