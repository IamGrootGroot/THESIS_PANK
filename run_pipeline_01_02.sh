#!/bin/bash

# =============================================================================
# PANK Thesis Project - Cell Segmentation Pipeline
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script automates the cell segmentation and tile extraction pipeline
# for H&E stained images using QuPath and StarDist.
# =============================================================================

# =============================================================================
# Logging Configuration
# =============================================================================
# Create timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/pipeline_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/pipeline_${TIMESTAMP}_error.log"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# =============================================================================
# Logging Functions
# =============================================================================
# Function to log normal messages with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to log error messages with timestamp
error_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" "$ERROR_LOG"
}

# Redirect all output to log files
# This ensures all output (stdout and stderr) is captured in the log files
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" "$ERROR_LOG" >&2)

# =============================================================================
# Pipeline Configuration
# =============================================================================
# Define paths for the pipeline components
PROJECT_PATH="/path/to/your/project.qpproj"  # QuPath project file
MODEL_PATH="/path/to/he_heavy_augment.pb"   # StarDist model file
IMAGES_DIR="/path/to/your/images"           # Directory containing .ndpi images

# =============================================================================
# Pipeline Initialization
# =============================================================================
# Log start of pipeline with configuration details
log "Starting pipeline execution"
log "Project path: $PROJECT_PATH"
log "Model path: $MODEL_PATH"
log "Images directory: $IMAGES_DIR"

# =============================================================================
# Input Validation
# =============================================================================
# Check if required files and directories exist
if [ ! -f "$PROJECT_PATH" ]; then
    error_log "Project file not found: $PROJECT_PATH"
    exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
    error_log "Model file not found: $MODEL_PATH"
    exit 1
fi

if [ ! -d "$IMAGES_DIR" ]; then
    error_log "Images directory not found: $IMAGES_DIR"
    exit 1
fi

# =============================================================================
# Main Pipeline Execution
# =============================================================================
# Process each .ndpi file in the images directory
for image in "$IMAGES_DIR"/*.ndpi; do
    if [ -f "$image" ]; then
        log "Processing image: $image"
        
        # Step 1: Cell Segmentation using StarDist
        log "Starting cell segmentation for $image"
        if qupath script --project="$PROJECT_PATH" \
                        --image="$image" \
                        --args="--model=$MODEL_PATH" \
                        01_he_stardist_cell_segmentation_0.23_um_per_pixel_qupath.groovy; then
            log "Cell segmentation completed successfully for $image"
        else
            error_log "Cell segmentation failed for $image"
            continue
        fi
        
        # Step 2: Cell Tile Extraction
        log "Starting cell tile extraction for $image"
        if qupath script --project="$PROJECT_PATH" \
                        --image="$image" \
                        02_he_wsubfolder_jpg_cell_tile_224x224_qupath.groovy; then
            log "Cell tile extraction completed successfully for $image"
        else
            error_log "Cell tile extraction failed for $image"
            continue
        fi
    else
        error_log "No .ndpi files found in $IMAGES_DIR"
        exit 1
    fi
done

# =============================================================================
# Pipeline Completion
# =============================================================================
# Log completion and provide information about log files
log "Pipeline execution completed"
log "Check $LOG_FILE for detailed logs"
log "Check $ERROR_LOG for error logs" 