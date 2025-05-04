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
    echo "  -f, --force           Force reprocessing even if cells/tiles already exist"
    echo "  -o, --output PATH     Custom output directory for tiles (default: output/tiles)"
    echo "  -s, --skip-detection  Skip cell detection, only extract tiles"
    echo "  -t, --skip-tiles      Skip tile extraction, only detect cells"
    echo "  -h, --help            Show this help message"
    echo
    echo "Example:"
    echo "  $0 -p /path/to/project.qpproj -m /path/to/model.pb -f"
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
FORCE_REPROCESSING=false
OUTPUT_DIR="output/tiles"
SKIP_DETECTION=false
SKIP_TILES=false

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
        -f|--force)
            FORCE_REPROCESSING=true
            shift
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--skip-detection)
            SKIP_DETECTION=true
            shift
            ;;
        -t|--skip-tiles)
            SKIP_TILES=true
            shift
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

# Check for conflicting options
if [ "$SKIP_DETECTION" = true ] && [ "$SKIP_TILES" = true ]; then
    error_log "Cannot skip both detection and tile extraction. At least one step must be executed."
    exit 1
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
log "Output directory: $OUTPUT_DIR"
if [ "$FORCE_REPROCESSING" = true ]; then
    log "Force reprocessing: Enabled"
fi
if [ "$SKIP_DETECTION" = true ]; then
    log "Cell detection: Skipped"
fi
if [ "$SKIP_TILES" = true ]; then
    log "Tile extraction: Skipped"
fi
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
mkdir -p "$OUTPUT_DIR"
log "Created output directory: $OUTPUT_DIR"

# =============================================================================
# Process All Images in Project
# =============================================================================
log "Processing all images in the QuPath project..."

# Create Groovy script that creates full-image annotations for all images
SETUP_SCRIPT=$(mktemp)
cat > "$SETUP_SCRIPT" << 'EOL'
import qupath.lib.roi.ROIs
import qupath.lib.objects.PathObjects
import qupath.lib.regions.ImagePlane
import qupath.lib.objects.classes.PathClass

// Process all images in project
def project = getProject()
if (project == null) {
    print "Error: No project found"
    return
}

// Ensure all images have annotations
for (entry in project.getImageList()) {
    def imageData = entry.readImageData()
    def hierarchy = imageData.getHierarchy()
    def annotations = hierarchy.getAnnotationObjects()
    
    if (annotations.isEmpty()) {
        print "Creating full image annotation for " + entry.getImageName()
        def server = imageData.getServer()
        def width = server.getWidth()
        def height = server.getHeight()
        def roi = ROIs.createRectangleROI(0, 0, width, height, ImagePlane.getDefaultPlane())
        def annotation = PathObjects.createAnnotationObject(roi, PathClass.fromString("Tissue"))
        annotation.setName("Whole Image")
        hierarchy.addObject(annotation)
        entry.saveImageData(imageData)
    } else {
        print "Annotations already exist for " + entry.getImageName()
    }
}

// Sync changes to the project
project.syncChanges()
print "Setup completed successfully"
EOL

# Run the setup script to ensure all images have annotations
log "Setting up annotations for all images in the project..."
if ! "$QUPATH_PATH" script --project="$PROJECT_PATH" -f "$SETUP_SCRIPT" > "$QUPATH_LOG" 2>&1; then
    error_log "Failed to setup annotations"
    rm -f "$SETUP_SCRIPT"
    exit 1
fi
rm -f "$SETUP_SCRIPT"
log "Annotation setup completed successfully"

# Step 1: Run cell segmentation on all images in the project
if [ "$SKIP_DETECTION" = false ]; then
    log "Executing Cell Segmentation (StarDist) on all images"
    
    # Configure force parameter if needed
    FORCE_ARG=""
    if [ "$FORCE_REPROCESSING" = true ]; then
        FORCE_ARG="force=true"
    fi
    
    if ! "$QUPATH_PATH" script --project="$PROJECT_PATH" \
                    --args="model=$MODEL_PATH $FORCE_ARG" \
                    01_he_stardist_cell_segmentation_shell_compatible.groovy \
                    > "$QUPATH_LOG" 2>&1; then
        error_log "Cell segmentation failed"
        exit 1
    fi
    log "Cell segmentation completed successfully"
    
    # Allow QuPath to fully save changes
    log "Waiting for QuPath to save project changes..."
    sleep 5
else
    log "Skipping cell detection as requested"
fi

# Step 2: Run tile extraction on all images in the project
if [ "$SKIP_TILES" = false ]; then
    log "Executing Cell Tile Extraction on all images"
    
    # Configure force and output parameters
    ARGS=""
    if [ "$FORCE_REPROCESSING" = true ]; then
        ARGS="force=true"
    fi
    if [ -n "$OUTPUT_DIR" ]; then
        ARGS="$ARGS output=$OUTPUT_DIR"
    fi
    
    if ! "$QUPATH_PATH" script --project="$PROJECT_PATH" \
                    --args="$ARGS" \
                    02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy \
                    > "$QUPATH_LOG" 2>&1; then
        error_log "Cell tile extraction failed"
        exit 1
    fi
    log "Cell tile extraction completed successfully"
else
    log "Skipping tile extraction as requested"
fi

# =============================================================================
# Pipeline Completion
# =============================================================================
echo
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           Pipeline Execution Complete         \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "Pipeline execution completed"
log "Successfully processed all images in the project"
log "Check $LOG_FILE for detailed logs"
log "Check $ERROR_LOG for error logs"
log "Check $QUPATH_LOG for QuPath verbose output" 