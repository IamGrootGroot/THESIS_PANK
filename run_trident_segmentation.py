#!/usr/bin/env python3
"""
Run TRIDENT Tissue Segmentation Script

This script runs TRIDENT's run_batch_of_slides.py for tissue segmentation
on a directory of whole-slide images or on images from a QuPath project.

TRIDENT is expected to create a job directory with segmentation results.
The GeoJSON segmentation files are expected at:
<trident_output_dir>/segmentations/<slide_name_without_extension>.geojson
"""

import os
import argparse
import subprocess
import logging
import json
import tempfile
import shutil
from pathlib import Path
from urllib.parse import urlparse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Supported WSI extensions by TRIDENT (this list can be expanded)
SUPPORTED_EXTENSIONS = ['.svs', '.ndpi', '.tiff', '.tif', '.vsi', '.mrxs', '.scn']

def extract_images_from_qupath_project(project_path):
    """
    Extract image file paths from a QuPath project.
    
    Args:
        project_path (Path): Path to the QuPath project directory
        
    Returns:
        list: List of image file paths found in the project
    """
    project_path = Path(project_path)
    data_dir = project_path / "data"
    
    if not data_dir.exists():
        logger.error(f"QuPath project data directory not found: {data_dir}")
        return []
    
    image_files = []
    
    # Iterate through numbered subdirectories in data/
    for subdir in data_dir.iterdir():
        if subdir.is_dir() and subdir.name.isdigit():
            server_json_path = subdir / "server.json"
            
            if server_json_path.exists():
                try:
                    with open(server_json_path, 'r') as f:
                        server_data = json.load(f)
                    
                    # Extract URI from server.json
                    uri = server_data.get("builder", {}).get("uri", "")
                    
                    if uri.startswith("file:"):
                        # Parse the file URI to get the actual file path
                        parsed_uri = urlparse(uri)
                        file_path = Path(parsed_uri.path)
                        
                        if file_path.exists() and file_path.suffix.lower() in SUPPORTED_EXTENSIONS:
                            image_files.append(file_path)
                            logger.info(f"Found image: {file_path.name}")
                        else:
                            logger.warning(f"Image file not found or unsupported: {file_path}")
                    else:
                        logger.warning(f"Non-file URI found in {server_json_path}: {uri}")
                        
                except (json.JSONDecodeError, KeyError, Exception) as e:
                    logger.error(f"Error parsing {server_json_path}: {e}")
            else:
                logger.warning(f"server.json not found in {subdir}")
    
    return image_files

def create_temp_directory_with_symlinks(image_files, temp_base_dir=None):
    """
    Create a temporary directory with symbolic links to the image files.
    
    Args:
        image_files (list): List of Path objects pointing to image files
        temp_base_dir (str, optional): Base directory for temporary files
        
    Returns:
        Path: Path to the temporary directory containing symlinks
    """
    if temp_base_dir:
        temp_dir = Path(tempfile.mkdtemp(dir=temp_base_dir))
    else:
        temp_dir = Path(tempfile.mkdtemp())
    
    logger.info(f"Creating temporary directory with symlinks: {temp_dir}")
    
    for img_file in image_files:
        symlink_path = temp_dir / img_file.name
        try:
            symlink_path.symlink_to(img_file.resolve())
            logger.debug(f"Created symlink: {symlink_path} -> {img_file}")
        except Exception as e:
            logger.error(f"Failed to create symlink for {img_file}: {e}")
    
    return temp_dir

def run_trident_batch_segmentation(trident_script_path, image_dir, output_dir, gpu=0):
    """
    Executes TRIDENT's run_batch_of_slides.py for tissue segmentation on all slides in a directory.
    """
    # Use conda run to execute in the trident environment
    command = [
        "conda", "run", "-n", "trident",
        "python",
        trident_script_path,
        "--task", "seg",
        "--wsi_dir", str(image_dir),
        "--job_dir", str(output_dir),
        "--gpu", str(gpu),
        "--remove_holes"
    ]

    logger.info(f"Executing TRIDENT batch segmentation with conda environment: {' '.join(command)}")
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
        logger.error(f"Error: conda or Python interpreter not found. Ensure conda is in PATH.")
        logger.error(f"Attempted command: {' '.join(command)}")
        return -1
    except Exception as e:
        logger.error(f"An unexpected error occurred while running TRIDENT batch segmentation: {e}")
        logger.error(f"Command was: {' '.join(command)}")
        return -1

def main():
    parser = argparse.ArgumentParser(description="Run TRIDENT tissue segmentation on WSI files.")
    
    # Create mutually exclusive group for input source
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument("--image_dir", type=str,
                           help="Directory containing the whole-slide image files (e.g., .ndpi, .svs).")
    input_group.add_argument("--qupath_project", type=str,
                           help="Path to QuPath project directory to extract images from.")
    
    parser.add_argument("--trident_output_dir", type=str, required=True,
                        help="Base directory where TRIDENT will create its output.")
    parser.add_argument("--trident_script_path", type=str, required=True,
                        help="Path to TRIDENT's run_batch_of_slides.py script.")
    parser.add_argument("--gpu", type=int, default=0,
                        help="GPU index to use for processing. Default is 0.")
    parser.add_argument("--temp_dir", type=str,
                        help="Base directory for temporary files (optional).")
    parser.add_argument("--keep_temp", action="store_true",
                        help="Keep temporary directory after processing (useful for debugging).")

    args = parser.parse_args()

    trident_output_dir = Path(args.trident_output_dir)
    trident_script_path = Path(args.trident_script_path)

    if not trident_script_path.is_file():
        logger.error(f"TRIDENT script not found or is not a file: {trident_script_path}")
        return

    # Create the base TRIDENT output directory if it doesn't exist
    trident_output_dir.mkdir(parents=True, exist_ok=True)
    logger.info(f"TRIDENT output directory: {trident_output_dir.resolve()}")

    image_files = []
    temp_dir = None
    cleanup_temp = False

    try:
        if args.image_dir:
            # Traditional directory-based approach
            image_dir = Path(args.image_dir)
            if not image_dir.is_dir():
                logger.error(f"Image directory not found or is not a directory: {image_dir}")
                return
            
            image_files = [f for f in image_dir.iterdir() 
                          if f.is_file() and f.suffix.lower() in SUPPORTED_EXTENSIONS]
            processing_dir = image_dir
            
        elif args.qupath_project:
            # QuPath project-based approach
            qupath_project = Path(args.qupath_project)
            if not qupath_project.is_dir():
                logger.error(f"QuPath project directory not found: {qupath_project}")
                return
            
            logger.info(f"Extracting images from QuPath project: {qupath_project}")
            image_files = extract_images_from_qupath_project(qupath_project)
            
            if not image_files:
                logger.error("No valid image files found in QuPath project")
                return
            
            # Create temporary directory with symlinks
            temp_dir = create_temp_directory_with_symlinks(image_files, args.temp_dir)
            processing_dir = temp_dir
            cleanup_temp = not args.keep_temp

        if not image_files:
            logger.error("No supported image files found")
            return
        
        logger.info(f"Found {len(image_files)} image files to process:")
        for img_file in image_files:
            logger.info(f"  - {img_file.name}")

        # Run TRIDENT batch segmentation
        return_code = run_trident_batch_segmentation(
            str(trident_script_path.resolve()), 
            processing_dir.resolve(), 
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

    finally:
        # Cleanup temporary directory if needed
        if temp_dir and cleanup_temp:
            try:
                shutil.rmtree(temp_dir)
                logger.info(f"Cleaned up temporary directory: {temp_dir}")
            except Exception as e:
                logger.warning(f"Failed to cleanup temporary directory {temp_dir}: {e}")
        elif temp_dir and not cleanup_temp:
            logger.info(f"Temporary directory preserved at: {temp_dir}")

if __name__ == "__main__":
    main() 