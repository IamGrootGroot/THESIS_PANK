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
# QuPath Configuration
# =============================================================================
QUPATH_PATH="/Applications/QuPath-0.5.1-arm64.app/Contents/MacOS/QuPath-0.5.1-arm64"

# Validate QuPath installation
if [ ! -f "$QUPATH_PATH" ]; then
    echo "Error: QuPath not found at $QUPATH_PATH"
    exit 1
fi

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -p, --project PATH    Path to QuPath project file (.qpproj)"
    echo "  -m, --model PATH      Path to StarDist model file (.pb)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Example:"
    echo "  $0 -p /path/to/project.qpproj -m /path/to/model.pb"
    echo
    echo "Note: All paths are required. The script will validate their existence."
    echo "IMPORTANT: Images must be already added to the QuPath project through the GUI."
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
QUPATH_LOG="${LOG_DIR}/qupath_${TIMESTAMP}.log"

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
    
    # Ensure values are within range to avoid printf errors
    if [ "$completed" -lt 0 ]; then completed=0; fi
    if [ "$remaining" -lt 0 ]; then remaining=0; fi
    
    printf "\r\033[1;33mProgress: [%s%s] %d%%\033[0m" \
           "$(printf '%0.s#' $(seq 1 $completed))" \
           "$(printf '%0.s-' $(seq 1 $remaining))" \
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
if [ -z "$PROJECT_PATH" ] || [ -z "$MODEL_PATH" ]; then
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

log "Input validation completed successfully"
echo

# =============================================================================
# Create Output Directory
# =============================================================================
OUTPUT_DIR="output/tiles"
mkdir -p "$OUTPUT_DIR"
log "Created output directory: $OUTPUT_DIR"

# =============================================================================
# Manually Define Images to Process
# =============================================================================
log "Preparing to process images from the project"

# Instead of trying to parse QuPath output, ask for user input
read -p "Enter the number of images to process: " TOTAL_IMAGES
echo

if [[ ! "$TOTAL_IMAGES" =~ ^[0-9]+$ ]] || [ "$TOTAL_IMAGES" -eq 0 ]; then
    error_log "Invalid number of images. Please enter a positive integer."
    exit 1
fi

IMAGE_NAMES=()
for ((i=1; i<=TOTAL_IMAGES; i++)); do
    read -p "Enter the name of image $i: " image_name
    IMAGE_NAMES+=("$image_name")
done

log "Will process $TOTAL_IMAGES images"
echo

# =============================================================================
# Main Pipeline Execution
# =============================================================================
# Process each image in the project
current_image=0

for image_name in "${IMAGE_NAMES[@]}"; do
    current_image=$((current_image + 1))
    
    echo -e "\033[1;36mProcessing image $current_image of $TOTAL_IMAGES: $image_name\033[0m"
    
    # Step 1: Cell Segmentation using StarDist
    log "Starting cell segmentation for $image_name"
    if ! "$QUPATH_PATH" script --project="$PROJECT_PATH" \
                    --image="$image_name" \
                    --args="model=$MODEL_PATH" \
                    01_he_stardist_cell_segmentation_shell_compatible.groovy \
                    > "$QUPATH_LOG" 2>&1; then
        error_log "Cell segmentation failed for $image_name"
        continue
    fi
    
    # Step 2: Cell Tile Extraction
    log "Starting cell tile extraction for $image_name"
    if ! "$QUPATH_PATH" script --project="$PROJECT_PATH" \
                    --image="$image_name" \
                    02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy \
                    > "$QUPATH_LOG" 2>&1; then
        error_log "Cell tile extraction failed for $image_name"
        continue
    fi
    
    # Update progress bar
    progress_bar $current_image $TOTAL_IMAGES
    echo
done

# =============================================================================
# Pipeline Completion
# =============================================================================
echo
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           Pipeline Execution Complete         \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "Pipeline execution completed"
log "Successfully processed $current_image images"
log "Check $LOG_FILE for detailed logs"
log "Check $ERROR_LOG for error logs"
log "QuPath verbose output is in $QUPATH_LOG" 