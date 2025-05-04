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
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -p, --project PATH    Path to QuPath project file (.qpproj)"
    echo "  -m, --model PATH      Path to StarDist model file (.pb)"
    echo "  -i, --images PATH     Directory containing .ndpi images"
    echo "  -h, --help           Show this help message"
    echo
    echo "Example:"
    echo "  $0 -p /path/to/project.qpproj -m /path/to/model.pb -i /path/to/images"
    echo
    echo "Note: All paths are required. The script will validate their existence."
    exit 1
}

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
# Function to log normal messages with timestamp and terminal output
log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;32m$1\033[0m" | tee -a "$LOG_FILE"
}

# Function to log error messages with timestamp and terminal output
error_log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;31mERROR: $1\033[0m" | tee -a "$LOG_FILE" "$ERROR_LOG"
}

# Function to display progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\r\033[1;33mProgress: [%${completed}s%${remaining}s] %d%%\033[0m" \
           "$(printf '#%.0s' $(seq 1 $completed))" \
           "$(printf '-%.0s' $(seq 1 $remaining))" \
           "$percentage"
}

# Redirect all output to log files while maintaining terminal output
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" "$ERROR_LOG" >&2)

# =============================================================================
# Command Line Argument Parsing
# =============================================================================
# Initialize variables
PROJECT_PATH=""
MODEL_PATH=""
IMAGES_DIR=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        -m|--model)
            MODEL_PATH="$2"
            shift 2
            ;;
        -i|--images)
            IMAGES_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            error_log "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate required arguments
if [ -z "$PROJECT_PATH" ] || [ -z "$MODEL_PATH" ] || [ -z "$IMAGES_DIR" ]; then
    error_log "Missing required arguments"
    show_help
fi

# =============================================================================
# Pipeline Initialization
# =============================================================================
# Clear screen and show welcome message
clear
echo -e "\033[1;35m===============================================\033[0m"
echo -e "\033[1;35m     PANK Thesis Project - Cell Segmentation   \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

# Log start of pipeline with configuration details
log "Starting pipeline execution"
log "Project path: $PROJECT_PATH"
log "Model path: $MODEL_PATH"
log "Images directory: $IMAGES_DIR"
echo

# =============================================================================
# Input Validation
# =============================================================================
# Check if required files and directories exist
log "Validating input files and directories..."

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

log "Input validation completed successfully"
echo

# =============================================================================
# Main Pipeline Execution
# =============================================================================
# Count total number of .ndpi files
total_images=$(ls -1 "$IMAGES_DIR"/*.ndpi 2>/dev/null | wc -l)
current_image=0

if [ "$total_images" -eq 0 ]; then
    error_log "No .ndpi files found in $IMAGES_DIR"
    exit 1
fi

log "Found $total_images images to process"
echo

# Process each .ndpi file in the images directory
for image in "$IMAGES_DIR"/*.ndpi; do
    if [ -f "$image" ]; then
        current_image=$((current_image + 1))
        image_name=$(basename "$image")
        
        echo -e "\033[1;36mProcessing image $current_image of $total_images: $image_name\033[0m"
        
        # Step 1: Cell Segmentation using StarDist
        log "Starting cell segmentation for $image_name"
        if qupath script --project="$PROJECT_PATH" \
                        --image="$image" \
                        --args="--model=$MODEL_PATH" \
                        01_he_stardist_cell_segmentation_0.23_um_per_pixel_qupath.groovy; then
            log "Cell segmentation completed successfully for $image_name"
        else
            error_log "Cell segmentation failed for $image_name"
            continue
        fi
        
        # Step 2: Cell Tile Extraction
        log "Starting cell tile extraction for $image_name"
        if qupath script --project="$PROJECT_PATH" \
                        --image="$image" \
                        02_he_wsubfolder_jpg_cell_tile_224x224_qupath.groovy; then
            log "Cell tile extraction completed successfully for $image_name"
        else
            error_log "Cell tile extraction failed for $image_name"
            continue
        fi
        
        # Update progress bar
        progress_bar $current_image $total_images
        echo
    fi
done

# =============================================================================
# Pipeline Completion
# =============================================================================
echo
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           Pipeline Execution Complete         \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "Pipeline execution completed"
log "Check $LOG_FILE for detailed logs"
log "Check $ERROR_LOG for error logs" 