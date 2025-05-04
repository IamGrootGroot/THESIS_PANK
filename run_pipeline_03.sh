#!/bin/bash

# =============================================================================
# PANK Thesis Project - Feature Extraction Pipeline
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script automates the feature extraction pipeline using the UNI2-h model
# from HuggingFace for processing image tiles.
# =============================================================================

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -i, --images PATH     Directory containing image tiles"
    echo "  -o, --output PATH     Output CSV file path (default: output_embeddings.csv)"
    echo "  -t, --token TOKEN     HuggingFace API token"
    echo "  -b, --batch SIZE      Batch size for processing (default: 32)"
    echo "  -w, --workers NUM     Number of worker processes (default: 4)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Example:"
    echo "  $0 -i /path/to/images -o embeddings.csv -t your_hf_token"
    echo
    echo "Note: Image directory and HuggingFace token are required."
    exit 1
}

# =============================================================================
# Logging Configuration
# =============================================================================
# Create timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/feature_extraction_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/feature_extraction_${TIMESTAMP}_error.log"

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

# Function to log warning messages with timestamp and terminal output
warn_log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;33mWARNING: $1\033[0m" | tee -a "$LOG_FILE"
}

# Redirect all output to log files while maintaining terminal output
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" "$ERROR_LOG" >&2)

# =============================================================================
# Command Line Argument Parsing
# =============================================================================
# Initialize variables with defaults
IMAGE_DIR=""
OUTPUT_CSV="output_embeddings.csv"
HF_TOKEN=""
BATCH_SIZE=32
NUM_WORKERS=4

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--images)
            IMAGE_DIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_CSV="$2"
            shift 2
            ;;
        -t|--token)
            HF_TOKEN="$2"
            shift 2
            ;;
        -b|--batch)
            BATCH_SIZE="$2"
            shift 2
            ;;
        -w|--workers)
            NUM_WORKERS="$2"
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
if [ -z "$IMAGE_DIR" ] || [ -z "$HF_TOKEN" ]; then
    error_log "Missing required arguments"
    show_help
fi

# =============================================================================
# Pipeline Initialization
# =============================================================================
# Clear screen and show welcome message
clear
echo -e "\033[1;35m===============================================\033[0m"
echo -e "\033[1;35m     PANK Thesis Project - Feature Extraction  \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

# Log start of pipeline with configuration details
log "Starting feature extraction pipeline"
log "Image directory: $IMAGE_DIR"
log "Output file: $OUTPUT_CSV"
log "Batch size: $BATCH_SIZE"
log "Number of workers: $NUM_WORKERS"
echo

# =============================================================================
# Environment Validation
# =============================================================================
# Check if Python environment is activated
if [ -z "$VIRTUAL_ENV" ]; then
    warn_log "No virtual environment detected. Make sure you have all required packages installed."
fi

# Check if CUDA is available
if command -v nvidia-smi &> /dev/null; then
    log "CUDA is available on this system"
    nvidia-smi | grep "NVIDIA" | head -n 1
else
    warn_log "CUDA not detected. The script will run on CPU which may be slow."
fi

# =============================================================================
# Input Validation
# =============================================================================
# Check if image directory exists and contains files
if [ ! -d "$IMAGE_DIR" ]; then
    error_log "Image directory not found: $IMAGE_DIR"
    exit 1
fi

image_count=$(find "$IMAGE_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) | wc -l)
if [ "$image_count" -eq 0 ]; then
    error_log "No image files found in $IMAGE_DIR"
    exit 1
fi

log "Found $image_count images to process"
echo

# =============================================================================
# Main Pipeline Execution
# =============================================================================
log "Starting feature extraction..."
if python 03_uni2_feature_extraction_NEW2.py \
    --image_dir "$IMAGE_DIR" \
    --output_csv "$OUTPUT_CSV" \
    --batch_size "$BATCH_SIZE" \
    --num_workers "$NUM_WORKERS" \
    --hf_token "$HF_TOKEN"; then
    
    log "Feature extraction completed successfully"
    log "Output saved to: $OUTPUT_CSV"
else
    error_log "Feature extraction failed"
    exit 1
fi

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