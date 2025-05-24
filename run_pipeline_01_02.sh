#!/bin/bash

# =============================================================================
# PANK Thesis Project - Cell Segmentation Pipeline (Server Version)
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script automates the cell segmentation and tile extraction pipeline
# for H&E stained images using QuPath and StarDist on the remote server.
# =============================================================================

# =============================================================================
# QuPath Configuration (Linux Server Version)
# =============================================================================
# Common QuPath installation paths on Linux servers
QUPATH_PATHS=(
    "/opt/QuPath/bin/QuPath"
    "/usr/local/bin/QuPath"
    "/home/pellouxp/QuPath/bin/QuPath"
    "$(which QuPath 2>/dev/null)"
)

# Find QuPath installation
QUPATH_PATH=""
for path in "${QUPATH_PATHS[@]}"; do
    if [ -f "$path" ] && [ -x "$path" ]; then
        QUPATH_PATH="$path"
        break
    fi
done

if [ -z "$QUPATH_PATH" ]; then
    echo "Error: QuPath not found. Please install QuPath or add it to PATH"
    echo "Searched in:"
    for path in "${QUPATH_PATHS[@]}"; do
        [ -n "$path" ] && echo "  - $path"
    done
    exit 1
fi

echo "Found QuPath at: $QUPATH_PATH"

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -p, --project PATH    Path to QuPath project directory"
    echo "  -m, --model PATH      Path to StarDist model file (.pb)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Example:"
    echo "  $0 -p /path/to/HE/QuPath_MP_PDAC5 -m /path/to/models/he_heavy_augment.pb"
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
echo -e "\033[1;35m     Server Version\033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

# Log start of pipeline with configuration details
log "Starting pipeline execution"
log "Project path: $PROJECT_PATH"
log "Model path: $MODEL_PATH"
log "QuPath path: $QUPATH_PATH"
echo

# =============================================================================
# Input Validation
# =============================================================================
# Check if required files and directories exist
log "Validating input files and directories..."

# Check if project directory exists and contains .qpproj file
if [ ! -d "$PROJECT_PATH" ]; then
    error_log "Project directory not found: $PROJECT_PATH"
    exit 1
fi

# Find the .qpproj file in the project directory
QPPROJ_FILE=$(find "$PROJECT_PATH" -name "*.qpproj" -type f | head -n 1)
if [ -z "$QPPROJ_FILE" ]; then
    error_log "No .qpproj file found in: $PROJECT_PATH"
    exit 1
fi

log "Found QuPath project file: $QPPROJ_FILE"

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
# Script Path Configuration
# =============================================================================
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CELL_SEG_SCRIPT="$SCRIPT_DIR/01_he_stardist_cell_segmentation_shell_compatible.groovy"
TILE_EXTRACT_SCRIPT="$SCRIPT_DIR/02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy"

# Validate script files exist
if [ ! -f "$CELL_SEG_SCRIPT" ]; then
    error_log "Cell segmentation script not found: $CELL_SEG_SCRIPT"
    exit 1
fi

if [ ! -f "$TILE_EXTRACT_SCRIPT" ]; then
    error_log "Tile extraction script not found: $TILE_EXTRACT_SCRIPT"
    exit 1
fi

# =============================================================================
# Process All Images in Project
# =============================================================================
log "Processing all images in the QuPath project..."

# Step 1: Run cell segmentation on all images in the project
log "Executing Cell Segmentation (StarDist) on all images"
if ! "$QUPATH_PATH" script --project="$QPPROJ_FILE" \
                --args="model=$MODEL_PATH" \
                "$CELL_SEG_SCRIPT" \
                > "$QUPATH_LOG" 2>&1; then
    error_log "Cell segmentation failed. Check $QUPATH_LOG for details."
    tail -n 50 "$QUPATH_LOG"
    exit 1
fi
log "Cell segmentation completed successfully"

# Allow QuPath to fully save changes
log "Waiting for QuPath to save project changes..."
sleep 5

# Step 2: Run tile extraction on all images in the project
log "Executing Cell Tile Extraction on all images"
if ! "$QUPATH_PATH" script --project="$QPPROJ_FILE" \
                "$TILE_EXTRACT_SCRIPT" \
                > "$QUPATH_LOG" 2>&1; then
    error_log "Cell tile extraction failed. Check $QUPATH_LOG for details."
    tail -n 50 "$QUPATH_LOG"
    exit 1
fi
log "Cell tile extraction completed successfully"

# =============================================================================
# Pipeline Completion
# =============================================================================
echo
log "Pipeline execution completed successfully!"
log "Cell segmentation and tile extraction finished for all images in the project"
log "Output directory: $OUTPUT_DIR"
log "Log files:"
log "  - Main log: $LOG_FILE"
log "  - Error log: $ERROR_LOG"  
log "  - QuPath log: $QUPATH_LOG"
echo
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m          Pipeline Completed Successfully!     \033[0m"
echo -e "\033[1;32m===============================================\033[0m" 