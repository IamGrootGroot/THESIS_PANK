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
    "/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build_0.5.1/qupath/build/dist/QuPath/bin/QuPath"
    "/opt/QuPath/bin/QuPath"
    "/usr/local/bin/QuPath"
    "/home/pellouxp/QuPath/bin/QuPath"
    "$(which QuPath 2>/dev/null)"
)

# Find QuPath installation
QUPATH_FOUND=""
if [ -n "$QUPATH_PATH" ]; then
    # Use custom QuPath path if provided
    if [ -f "$QUPATH_PATH" ] && [ -x "$QUPATH_PATH" ]; then
        QUPATH_FOUND="$QUPATH_PATH"
        echo "Using custom QuPath path: $QUPATH_FOUND"
    else
        echo "Error: Custom QuPath path not found or not executable: $QUPATH_PATH"
        exit 1
    fi
else
    # Search in predefined locations
    for path in "${QUPATH_PATHS[@]}"; do
        if [ -f "$path" ] && [ -x "$path" ]; then
            QUPATH_FOUND="$path"
            break
        fi
    done
fi

if [ -z "$QUPATH_FOUND" ]; then
    echo "Error: QuPath not found. Please install QuPath or add it to PATH"
    echo "Searched in:"
    for path in "${QUPATH_PATHS[@]}"; do
        [ -n "$path" ] && echo "  - $path"
    done
    echo
    echo "You can also specify a custom QuPath path with -q/--qupath option"
    exit 1
fi

QUPATH_PATH="$QUPATH_FOUND"
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
    echo "  -q, --qupath PATH     Path to QuPath executable (optional)"
    echo "  -g, --gpu BOOL        Enable GPU acceleration (true/false, default: true)"
    echo "  -d, --device ID       GPU device ID (default: 0)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Example:"
    echo "  $0 -p /path/to/HE/QuPath_MP_PDAC5 -m /path/to/models/he_heavy_augment.pb"
    echo "  $0 -p /path/to/project -m /path/to/model.pb -g true -d 0"
    echo "  $0 -p /path/to/project -m /path/to/model.pb -q /custom/path/to/QuPath"
    echo
    echo "Note: GPU acceleration requires CUDA-compatible QuPath build and drivers."
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
QUPATH_PATH=""  # Allow custom QuPath path
USE_GPU="true"
GPU_DEVICE="0"

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
        -q|--qupath)
            QUPATH_PATH="$2"
            shift 2
            ;;
        -g|--gpu)
            USE_GPU="$2"
            shift 2
            ;;
        -d|--device)
            GPU_DEVICE="$2"
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
echo -e "\033[1;35m     Server Version with GPU Acceleration      \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

# Log start of pipeline with configuration details
log "Starting pipeline execution"
log "Project path: $PROJECT_PATH"
log "Model path: $MODEL_PATH"
log "QuPath path: $QUPATH_PATH"
log "GPU acceleration: $USE_GPU"
log "GPU device: $GPU_DEVICE"
echo

# =============================================================================
# GPU Environment Check
# =============================================================================
log "Checking GPU environment..."

# Check NVIDIA GPU
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits | while IFS=, read name memory_total memory_free; do
        log "GPU detected: $name"
        log "GPU memory: ${memory_free}MB free / ${memory_total}MB total"
    done
else
    log "Warning: nvidia-smi not found. GPU detection unavailable."
fi

# Check CUDA environment
if [ -n "$CUDA_HOME" ]; then
    log "CUDA_HOME: $CUDA_HOME"
elif [ -n "$CUDA_PATH" ]; then
    log "CUDA_PATH: $CUDA_PATH"
else
    log "Warning: CUDA environment variables not set"
fi

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
log "Executing Cell Segmentation (StarDist) with GPU acceleration on all images"
STARDIST_ARGS="model=$MODEL_PATH,gpu=$USE_GPU,device=$GPU_DEVICE"
if ! "$QUPATH_PATH" script --project="$QPPROJ_FILE" \
                --args="$STARDIST_ARGS" \
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
# Performance Summary
# =============================================================================
log "Extracting performance statistics from QuPath logs..."
if [ -f "$QUPATH_LOG" ]; then
    # Extract timing information from logs
    DETECTION_SPEED=$(grep "Detection speed:" "$QUPATH_LOG" | tail -1 | awk '{print $3}')
    TOTAL_CELLS=$(grep "Total cells detected:" "$QUPATH_LOG" | tail -1 | awk '{print $4}')
    
    if [ -n "$DETECTION_SPEED" ] && [ -n "$TOTAL_CELLS" ]; then
        log "Performance Summary:"
        log "  Total cells detected: $TOTAL_CELLS"
        log "  Detection speed: $DETECTION_SPEED cells/second"
    fi
fi

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