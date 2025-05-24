#!/usr/bin/env python3
"""
Run TRIDENT Tissue Segmentation Script

This script iterates through whole-slide images in a specified directory,
runs TRIDENT's run_single_slide.py for tissue segmentation on each,
and stores the output.

TRIDENT is expected to create a job directory for each slide, structured as:
<trident_base_output_dir>/<slide_name_without_extension>/
And the GeoJSON segmentation file is expected at:
<trident_base_output_dir>/<slide_name_without_extension>/segmentations/<slide_name_without_extension>.geojson
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

def run_trident_for_slide(trident_script_path, slide_path, slide_job_dir):
    """
    Executes TRIDENT's run_single_slide.py for a given slide.
    """
    command = [
        "python",
        trident_script_path,
        "--slide_path", str(slide_path),
        "--job_dir", str(slide_job_dir)
    ]

    logger.info(f"Executing TRIDENT for {slide_path.name}: {' '.join(command)}")
    try:
        # Using shell=False for security and better control.
        # Ensure python and trident_script_path are findable or use absolute paths.
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate()

        if process.returncode == 0:
            logger.info(f"TRIDENT executed successfully for {slide_path.name}.")
            if stdout:
                logger.debug(f"TRIDENT stdout:\n{stdout}")
        else:
            logger.error(f"TRIDENT execution failed for {slide_path.name} with exit code {process.returncode}.")
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
        logger.error(f"An unexpected error occurred while running TRIDENT for {slide_path.name}: {e}")
        logger.error(f"Command was: {' '.join(command)}")
        return -1

def main():
    parser = argparse.ArgumentParser(description="Run TRIDENT tissue segmentation on a directory of WSI files.")
    parser.add_argument("--image_dir", type=str, required=True,
                        help="Directory containing the whole-slide image files (e.g., .ndpi, .svs).")
    parser.add_argument("--trident_output_dir", type=str, required=True,
                        help="Base directory where TRIDENT will create job-specific subdirectories for its output.")
    parser.add_argument("--trident_script_path", type=str, required=True,
                        help="Path to TRIDENT's run_single_slide.py script.")

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
    logger.info(f"TRIDENT base output directory: {trident_output_dir.resolve()}")

    processed_files = 0
    failed_files = 0

    for item in image_dir.iterdir():
        if item.is_file() and item.suffix.lower() in SUPPORTED_EXTENSIONS:
            slide_name_no_ext = item.stem
            slide_job_dir = trident_output_dir / slide_name_no_ext

            # TRIDENT's run_single_slide.py creates the job_dir if it doesn't exist.
            # We can ensure the parent (trident_output_dir) exists, which we did.

            logger.info(f"Processing slide: {item.name}")
            
            return_code = run_trident_for_slide(
                str(trident_script_path.resolve()), 
                item.resolve(), 
                str(slide_job_dir.resolve())
            )
            
            if return_code == 0:
                processed_files += 1
                # Verify GeoJSON output (optional but good for confirmation)
                expected_geojson = slide_job_dir / "segmentations" / f"{slide_name_no_ext}.geojson"
                if expected_geojson.exists():
                    logger.info(f"Verified GeoJSON output for {item.name} at {expected_geojson}")
                else:
                    logger.warning(f"GeoJSON file NOT found for {item.name} at expected location: {expected_geojson}")
            else:
                failed_files += 1
            logger.info("-" * 50)

    logger.info(f"TRIDENT processing complete. Processed {processed_files} slides. Failed {failed_files} slides.")

if __name__ == "__main__":
    main() 