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
# Get Images from Project
# =============================================================================
log "Getting list of images from the project..."

# Use QuPath headless to list images in the project and redirect verbose output to log file
IMAGE_LIST=$(
  "$QUPATH_PATH" headless script --args="projectPath=$PROJECT_PATH" -e "
    import qupath.lib.projects.ProjectIO
    import java.awt.image.BufferedImage

    def project = ProjectIO.loadProject(new File(args[0].substring(12)), BufferedImage.class)
    def imageList = project.getImageList()
    println '${imageList.size()}'
    imageList.each { entry -> println entry.getImageName() }
  " 2> "$QUPATH_LOG" | grep -v "INFO" | tail -n +1  # Skip the INFO log lines
)

# Extract number of images and names
TOTAL_IMAGES=$(echo "$IMAGE_LIST" | head -n 1)
# Skip the first line which contains the count
IMAGE_NAMES=($(echo "$IMAGE_LIST" | tail -n +2))

if [ -z "$TOTAL_IMAGES" ] || [ "$TOTAL_IMAGES" -eq 0 ] || [ ${#IMAGE_NAMES[@]} -eq 0 ]; then
    error_log "No images found in the project. Please add images through the QuPath GUI first."
    exit 1
fi

log "Found $TOTAL_IMAGES images in the project: ${IMAGE_NAMES[*]}"
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