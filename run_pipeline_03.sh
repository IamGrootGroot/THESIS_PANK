#!/bin/bash

# Exit on error
set -e

# Configuration
export HF_TOKEN="your_token_here"  # Replace with your HuggingFace token
IMAGE_DIR="/path/to/your/images"   # Replace with your image directory
OUTPUT_CSV="output_embeddings.csv"  # Output CSV file name

# Log file setup
LOG_FILE="feature_extraction_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "Starting feature extraction pipeline at $(date)"
echo "----------------------------------------"

# Check if Python environment is activated (if using virtual environment)
if [ -z "$VIRTUAL_ENV" ]; then
    echo "Warning: No virtual environment detected. Make sure you have all required packages installed."
fi

# Check if CUDA is available
if command -v nvidia-smi &> /dev/null; then
    echo "CUDA is available on this system"
    nvidia-smi
else
    echo "Warning: CUDA not detected. The script will run on CPU which may be slow."
fi

# Run the feature extraction script
echo "Running feature extraction..."
python 03_uni2_feature_extraction_NEW2.py \
    --image_dir "$IMAGE_DIR" \
    --output_csv "$OUTPUT_CSV" \
    --batch_size 32 \
    --num_workers 4 \
    --hf_token "$HF_TOKEN"

# Check if the script completed successfully
if [ $? -eq 0 ]; then
    echo "----------------------------------------"
    echo "Feature extraction completed successfully at $(date)"
    echo "Output saved to: $OUTPUT_CSV"
    echo "Log file: $LOG_FILE"
else
    echo "----------------------------------------"
    echo "Error: Feature extraction failed at $(date)"
    echo "Check the log file for details: $LOG_FILE"
    exit 1
fi 