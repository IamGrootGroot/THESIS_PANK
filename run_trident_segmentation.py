#!/usr/bin/env python3
"""
Run TRIDENT Tissue Segmentation Script

This script runs TRIDENT's run_batch_of_slides.py for tissue segmentation
on a directory of whole-slide images.

TRIDENT is expected to create a job directory with segmentation results.
The GeoJSON segmentation files are expected at:
<trident_output_dir>/segmentations/<slide_name_without_extension>.geojson
"""

import os
import argparse
import subprocess
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Supported WSI extensions by TRIDENT (this list can be expanded)
SUPPORTED_EXTENSIONS = ['.svs', '.ndpi', '.tiff', '.tif', '.vsi', '.mrxs', '.scn']

def run_trident_batch_segmentation(trident_script_path, image_dir, output_dir, gpu=0):
    """
    Executes TRIDENT's run_batch_of_slides.py for tissue segmentation on all slides in a directory.
    """
    command = [
        "python",
        trident_script_path,
        "--task", "seg",
        "--wsi_dir", str(image_dir),
        "--job_dir", str(output_dir),
        "--gpu", str(gpu),
        "--remove_holes"
    ]

    logger.info(f"Executing TRIDENT batch segmentation: {' '.join(command)}")
    try:
        # Using shell=False for security and better control.
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate()

        if process.returncode == 0:
            logger.info(f"TRIDENT batch segmentation executed successfully.")
            if stdout:
                logger.debug(f"TRIDENT stdout:\n{stdout}")
        else:
            logger.error(f"TRIDENT batch segmentation failed with exit code {process.returncode}.")
            if stdout:
                logger.error(f"TRIDENT stdout:\n{stdout}")
            if stderr:
                logger.error(f"TRIDENT stderr:\n{stderr}")
        return process.returncode
    except FileNotFoundError:
        logger.error(f"Error: The Python interpreter or TRIDENT script was not found. Ensure Python is in PATH and script path is correct.")
        logger.error(f"Attempted command: {' '.join(command)}")
        return -1
    except Exception as e:
        logger.error(f"An unexpected error occurred while running TRIDENT batch segmentation: {e}")
        logger.error(f"Command was: {' '.join(command)}")
        return -1

def main():
    parser = argparse.ArgumentParser(description="Run TRIDENT tissue segmentation on a directory of WSI files.")
    parser.add_argument("--image_dir", type=str, required=True,
                        help="Directory containing the whole-slide image files (e.g., .ndpi, .svs).")
    parser.add_argument("--trident_output_dir", type=str, required=True,
                        help="Base directory where TRIDENT will create its output.")
    parser.add_argument("--trident_script_path", type=str, required=True,
                        help="Path to TRIDENT's run_batch_of_slides.py script.")
    parser.add_argument("--gpu", type=int, default=0,
                        help="GPU index to use for processing. Default is 0.")

    args = parser.parse_args()

    image_dir = Path(args.image_dir)
    trident_output_dir = Path(args.trident_output_dir)
    trident_script_path = Path(args.trident_script_path)

    if not image_dir.is_dir():
        logger.error(f"Image directory not found or is not a directory: {image_dir}")
        return

    if not trident_script_path.is_file():
        logger.error(f"TRIDENT script not found or is not a file: {trident_script_path}")
        return

    # Create the base TRIDENT output directory if it doesn't exist
    trident_output_dir.mkdir(parents=True, exist_ok=True)
    logger.info(f"TRIDENT output directory: {trident_output_dir.resolve()}")

    # Check if there are supported image files in the directory
    image_files = [f for f in image_dir.iterdir() 
                   if f.is_file() and f.suffix.lower() in SUPPORTED_EXTENSIONS]
    
    if not image_files:
        logger.error(f"No supported image files found in {image_dir}")
        return
    
    logger.info(f"Found {len(image_files)} image files to process")
    for img_file in image_files:
        logger.info(f"  - {img_file.name}")

    # Run TRIDENT batch segmentation
    return_code = run_trident_batch_segmentation(
        str(trident_script_path.resolve()), 
        image_dir.resolve(), 
        str(trident_output_dir.resolve()),
        args.gpu
    )
    
    if return_code == 0:
        logger.info("TRIDENT batch segmentation completed successfully")
        # Check for segmentation outputs
        segmentation_dir = trident_output_dir / "contours_geojson"
        if segmentation_dir.exists():
            geojson_files = list(segmentation_dir.glob("*.geojson"))
            logger.info(f"Found {len(geojson_files)} GeoJSON segmentation files:")
            for geojson_file in geojson_files:
                logger.info(f"  - {geojson_file.name}")
        else:
            logger.warning(f"Segmentation directory not found at {segmentation_dir}")
    else:
        logger.error("TRIDENT batch segmentation failed")

if __name__ == "__main__":
    main() 