#!/bin/bash

# =============================================================================
# PANK Thesis Project - QC Thumbnail Export (Annotations Already Imported)
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script exports QC thumbnails from QuPath projects that already have
# TRIDENT annotations imported. It does NOT re-import annotations.
# =============================================================================

set -euo pipefail

# =============================================================================
# QuPath Installation Paths Configuration
# =============================================================================
# QuPath 0.6 (CPU-optimized build with StarDist 0.6.0-rc1)
QUPATH_06_PATH="${QUPATH_06_PATH:-./qupath_cpu_build_0.6.0/QuPath/bin/QuPath}"
QUPATH_06_DIR="${QUPATH_06_PATH%/bin/QuPath}"

# QuPath 0.5.1 (GPU-enabled build)
QUPATH_051_PATH="${QUPATH_051_PATH:-./qupath_gpu_build_0.5.1/QuPath/bin/QuPath}"
QUPATH_051_DIR="${QUPATH_051_PATH%/bin/QuPath}"

# Default fallback (can be overridden with -q option or auto-detection)
DEFAULT_QUPATH_PATH="${QUPATH_PATH:-${QUPATH_06_PATH}}"

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -p, --project PATH     Path to QuPath project file (.qpproj)"
    echo "  -q, --qupath PATH      Path to QuPath executable (optional, auto-detects if not specified)"
    echo "  -m, --mode MODE        Force processing mode: 'cpu', 'gpu', or 'auto' (default: auto)"
    echo "  -o, --output DIR       Output directory for thumbnails (default: qc_thumbnails)"
    echo "  -n, --num-images NUM   Number of images to process (default: all images)"
    echo "  -c, --credentials FILE Path to Google Drive credentials file (default: drive_credentials.json)"
    echo "  -t, --token FILE       Path to token file (default: token.json)"
    echo "  -f, --folder NAME      Custom Google Drive folder name"
    echo "  -s, --test             Process test project (QuPath_MP_PDAC5/project.qpproj)"
    echo "  -a, --all              Process all QuPath projects in current directory"
    echo "  -u, --upload           Upload QC thumbnails to Google Drive after export"
    echo "  -v, --verbose          Enable verbose logging"
    echo "  --force                Force re-export even if already completed"
    echo "  -h, --help            Show this help message"
    echo
    echo "Processing Modes:"
    echo "  auto    Automatically detect best QuPath configuration (default)"
    echo "  cpu     Force CPU processing with QuPath 0.6"
    echo "  gpu     Force GPU processing with QuPath 0.5.1"
    echo
    echo "Examples:"
    echo "  $0 -s                                    # Export QC for test project with auto-detection"
    echo "  $0 -p QuPath_MP_PDAC100/project.qpproj  # Export for specific project"
    echo "  $0 -a -u                                 # Export all projects and upload to Drive"
    echo "  $0 -p project.qpproj -q /path/to/QuPath  # Custom QuPath path"
    echo "  $0 -s -m cpu                             # Force CPU mode"
    echo "  $0 -a -m gpu -v                          # Force GPU mode with verbose logging"
    echo "  $0 -p project.qpproj -n 10               # Process only first 10 images"
    echo "  $0 -s -n 5 -v                            # Process 5 images with verbose output"
    echo
    echo "Auto-detection Logic:"
    echo "  1. Check CUDA availability with nvidia-smi"
    echo "  2. Detect available QuPath installations (0.5.1 and 0.6)"
    echo "  3. Choose optimal configuration:"
    echo "     - GPU mode: QuPath 0.5.1 + CUDA available"
    echo "     - CPU mode: QuPath 0.6 + optimized for multi-core server"
    echo
    echo "Prerequisites:"
    echo "  - QuPath projects must already have TRIDENT annotations imported"
    echo "  - Google Drive credentials and token files must be available (for upload)"
    echo "  - Python with required packages (google-api-python-client, etc.) (for upload)"
    echo "  - If QuPath path not specified, uses auto-detection"
    echo
    exit 1
}

# =============================================================================
# Logging Configuration
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/qc_export_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/qc_export_${TIMESTAMP}_error.log"
QUPATH_QC_LOG="${LOG_DIR}/qupath_qc_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

# =============================================================================
# Logging Functions
# =============================================================================
log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;32m$1\033[0m" | tee -a "$LOG_FILE"
}

error_log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;31mERROR: $1\033[0m" | tee -a "$LOG_FILE" "$ERROR_LOG"
}

warn_log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;33mWARNING: $1\033[0m" | tee -a "$LOG_FILE"
}

verbose_log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;37m[VERBOSE] $1\033[0m" | tee -a "$LOG_FILE" >&2
    fi
}

# =============================================================================
# QuPath Version Detection and Configuration Functions
# =============================================================================
check_cuda_availability() {
    verbose_log "Checking CUDA availability..."
    
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
            local gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1)
            log "CUDA available: $gpu_count GPU(s) detected"
            verbose_log "GPU info: $gpu_info"
            return 0
        else
            warn_log "nvidia-smi found but failed to execute"
            return 1
        fi
    else
        verbose_log "nvidia-smi not found - CUDA not available"
        return 1
    fi
}

validate_qupath_executable() {
    local qupath_path="$1"
    
    verbose_log "Validating QuPath executable: $qupath_path"
    
    # Check if file exists
    if [ ! -f "$qupath_path" ]; then
        error_log "QuPath executable not found: $qupath_path"
        return 1
    fi
    
    # Check if file is executable
    if [ ! -x "$qupath_path" ]; then
        error_log "QuPath file is not executable: $qupath_path"
        error_log "Try: chmod +x $qupath_path"
        return 1
    fi
    
    # Security check: ensure it's not a suspicious file
    local file_type=$(file "$qupath_path" 2>/dev/null)
    if [[ ! "$file_type" =~ (executable|script|text) ]]; then
        warn_log "QuPath file type may be suspicious: $file_type"
    fi
    
    verbose_log "QuPath executable validation passed"
    return 0
}

detect_qupath_version() {
    local qupath_path="$1"
    verbose_log "Detecting QuPath version for: $qupath_path"
    
    if [ ! -f "$qupath_path" ]; then
        verbose_log "QuPath executable not found: $qupath_path"
        return 1
    fi
    
    # Method 1: Check path for version indicators
    if [[ "$qupath_path" == *"0.5.1"* ]]; then
        echo "0.5.1"
        return 0
    elif [[ "$qupath_path" == *"0.6"* ]] || [[ "$qupath_path" == *"0.6.0"* ]]; then
        echo "0.6"
        return 0
    fi
    
    # Method 2: Check parent directory structure
    local qupath_dir=$(dirname "$qupath_path")
    local parent_dir=$(dirname "$qupath_dir")
    
    if [[ "$parent_dir" == *"0.5.1"* ]]; then
        echo "0.5.1"
        return 0
    elif [[ "$parent_dir" == *"0.6"* ]]; then
        echo "0.6"
        return 0
    fi
    
    # Method 3: Try to run QuPath to get version (may not work in headless mode)
    verbose_log "Attempting to get version from QuPath executable..."
    local version_output
    if version_output=$("$qupath_path" --version 2>/dev/null | head -1); then
        if [[ "$version_output" == *"0.5.1"* ]]; then
            echo "0.5.1"
            return 0
        elif [[ "$version_output" == *"0.6"* ]]; then
            echo "0.6"
            return 0
        fi
    fi
    
    # Method 4: Check for version-specific files in QuPath directory
    local qupath_base_dir=$(dirname "$(dirname "$qupath_path")")
    
    # Look for version-specific JAR files or directories
    if find "$qupath_base_dir" -name "*0.5.1*" -type f 2>/dev/null | grep -q .; then
        echo "0.5.1"
        return 0
    elif find "$qupath_base_dir" -name "*0.6*" -type f 2>/dev/null | grep -q .; then
        echo "0.6"
        return 0
    fi
    
    verbose_log "Could not determine QuPath version from: $qupath_path"
    return 1
}

determine_optimal_qupath() {
    verbose_log "Determining optimal QuPath configuration for QC export..."
    
    local cuda_available=false
    local qupath_051_available=false
    local qupath_06_available=false
    
    # Check CUDA availability (redirect all output to avoid capture)
    if check_cuda_availability >&2; then
        cuda_available=true
    fi
    
    # Check QuPath installations
    if [ -f "$QUPATH_051_PATH" ] && [ -x "$QUPATH_051_PATH" ]; then
        qupath_051_available=true
        verbose_log "QuPath 0.5.1 available at: $QUPATH_051_PATH"
    fi
    
    if [ -f "$QUPATH_06_PATH" ] && [ -x "$QUPATH_06_PATH" ]; then
        qupath_06_available=true
        verbose_log "QuPath 0.6 available at: $QUPATH_06_PATH"
    fi
    
    # Decision logic (prefer the same as processing) - only echo the path
    if [ "$cuda_available" = true ] && [ "$qupath_051_available" = true ]; then
        echo "$QUPATH_051_PATH"
    elif [ "$qupath_06_available" = true ]; then
        echo "$QUPATH_06_PATH"
    elif [ "$qupath_051_available" = true ]; then
        echo "$QUPATH_051_PATH"
    else
        return 1
    fi
}

setup_qupath_for_mode() {
    local mode="$1"
    
    case "$mode" in
        "gpu")
            if [ -f "$QUPATH_051_PATH" ] && [ -x "$QUPATH_051_PATH" ]; then
                echo "$QUPATH_051_PATH"
            else
                return 1
            fi
            ;;
        "cpu")
            if [ -f "$QUPATH_06_PATH" ] && [ -x "$QUPATH_06_PATH" ]; then
                echo "$QUPATH_06_PATH"
            else
                return 1
            fi
            ;;
        "auto")
            determine_optimal_qupath
            ;;
        *)
            return 1
            ;;
    esac
}

comprehensive_qupath_validation() {
    local qupath_path="$1"
    local requested_mode="$2"
    local cuda_available="$3"
    
    log "Performing comprehensive QuPath validation..."
    
    # Step 1: Basic executable validation
    if ! validate_qupath_executable "$qupath_path"; then
        return 1
    fi
    
    # Step 2: Version detection
    local detected_version
    if ! detected_version=$(detect_qupath_version "$qupath_path"); then
        error_log "Could not detect QuPath version for: $qupath_path"
        error_log "Please ensure you're using a supported QuPath version (0.5.1 or 0.6)"
        return 1
    fi
    
    log "Detected QuPath version: $detected_version"
    
    # Step 3: Mode compatibility validation
    case "$requested_mode" in
        "gpu")
            if [ "$detected_version" != "0.5.1" ]; then
                error_log "GPU mode requires QuPath 0.5.1, but detected version: $detected_version"
                error_log "Use QuPath 0.5.1 for GPU acceleration or switch to CPU mode"
                return 1
            fi
            
            if [ "$cuda_available" != "true" ]; then
                warn_log "GPU mode requested but CUDA not available"
                warn_log "Processing may fall back to CPU within QuPath"
            fi
            ;;
        "cpu")
            if [ "$detected_version" != "0.6" ]; then
                warn_log "CPU mode optimized for QuPath 0.6, but detected version: $detected_version"
                warn_log "Processing will continue but may not be optimally configured"
            fi
            ;;
        "auto")
            # Auto mode is always compatible
            verbose_log "Auto mode: Using detected QuPath version $detected_version"
            ;;
        *)
            error_log "Invalid processing mode: $requested_mode"
            return 1
            ;;
    esac
    
    # Step 4: Set global variables for later use
    DETECTED_QUPATH_VERSION="$detected_version"
    VALIDATED_QUPATH_PATH="$qupath_path"
    
    log "✅ QuPath validation completed successfully"
    log "   Path: $qupath_path"
    log "   Version: $detected_version"
    log "   Mode: $requested_mode"
    log "   CUDA: $cuda_available"
    
    return 0
}

# =============================================================================
# Command Line Argument Parsing
# =============================================================================
PROJECT_PATH=""
OUTPUT_DIR="qc_thumbnails"
NUM_IMAGES=""
CREDENTIALS_FILE="drive_credentials.json"
TOKEN_FILE="token.json"
CUSTOM_FOLDER_NAME=""
PROCESS_TEST=false
PROCESS_ALL=false
CUSTOM_QUPATH_PATH=""
FORCE_MODE="auto"
UPLOAD_TO_DRIVE=false
VERBOSE=false
FORCE_RE_EXPORT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        -q|--qupath)
            CUSTOM_QUPATH_PATH="$2"
            shift 2
            ;;
        -m|--mode)
            FORCE_MODE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -n|--num-images)
            NUM_IMAGES="$2"
            shift 2
            ;;
        -c|--credentials)
            CREDENTIALS_FILE="$2"
            shift 2
            ;;
        -t|--token)
            TOKEN_FILE="$2"
            shift 2
            ;;
        -f|--folder)
            CUSTOM_FOLDER_NAME="$2"
            shift 2
            ;;
        -s|--test)
            PROCESS_TEST=true
            shift
            ;;
        -a|--all)
            PROCESS_ALL=true
            shift
            ;;
        -u|--upload)
            UPLOAD_TO_DRIVE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --force)
            FORCE_RE_EXPORT=true
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

# =============================================================================
# Validation
# =============================================================================
# Validate processing mode
case "$FORCE_MODE" in
    "auto"|"cpu"|"gpu")
        # Valid modes
        ;;
    *)
        error_log "Invalid processing mode: $FORCE_MODE"
        error_log "Valid modes are: auto, cpu, gpu"
        exit 1
        ;;
esac

# Check upload prerequisites only if upload is requested
if [ "$UPLOAD_TO_DRIVE" = true ]; then
    # Check Google Drive authentication files
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        error_log "Google Drive credentials file not found: $CREDENTIALS_FILE"
        error_log "Upload disabled. Run without -u flag to skip upload."
        exit 1
    fi

    if [ ! -f "$TOKEN_FILE" ]; then
        error_log "Google Drive token file not found: $TOKEN_FILE"
        error_log "Please run generate_drive_token.py first or run without -u flag to skip upload."
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error_log "python3 not found. Please install Python 3 or run without -u flag to skip upload."
        exit 1
    fi
fi

# Determine projects to process
PROJECTS_TO_PROCESS=()

if [ "$PROCESS_TEST" = true ]; then
    PROJECTS_TO_PROCESS+=("QuPath_MP_PDAC5/project.qpproj")
elif [ "$PROCESS_ALL" = true ]; then
    # Find all QuPath project files
    while IFS= read -r -d '' project_file; do
        PROJECTS_TO_PROCESS+=("$project_file")
    done < <(find . -name "project.qpproj" -type f -print0)
elif [ -n "$PROJECT_PATH" ]; then
    PROJECTS_TO_PROCESS+=("$PROJECT_PATH")
else
    error_log "No processing mode specified. Use -s, -a, or -p"
    show_help
fi

# Validate projects exist
for project in "${PROJECTS_TO_PROCESS[@]}"; do
    if [ ! -f "$project" ]; then
        error_log "Project file not found: $project"
        exit 1
    fi
done

# =============================================================================
# QuPath Configuration
# =============================================================================
# Check CUDA availability
CUDA_AVAILABLE=false
if check_cuda_availability; then
    CUDA_AVAILABLE=true
fi

# Determine QuPath executable
if [ -n "$CUSTOM_QUPATH_PATH" ]; then
    log "Validating custom QuPath installation..."
    
    if ! comprehensive_qupath_validation "$CUSTOM_QUPATH_PATH" "$FORCE_MODE" "$CUDA_AVAILABLE"; then
        error_log "Custom QuPath validation failed"
        exit 1
    fi
    
    SELECTED_QUPATH_PATH="$CUSTOM_QUPATH_PATH"
    log "Using validated custom QuPath: $CUSTOM_QUPATH_PATH (version: $DETECTED_QUPATH_VERSION)"
else
    # Use auto-detection
    SELECTED_QUPATH_PATH=$(setup_qupath_for_mode "$FORCE_MODE")
    if [ $? -ne 0 ] || [ -z "$SELECTED_QUPATH_PATH" ]; then
        error_log "Failed to determine QuPath path"
        exit 1
    fi
    
    # Log the selection result
    case "$FORCE_MODE" in
        "auto")
            if [[ "$SELECTED_QUPATH_PATH" == *"0.5.1"* ]]; then
                if [ "$CUDA_AVAILABLE" = true ]; then
                    log "Auto-selected QuPath 0.5.1 for QC export (matches GPU processing)"
                else
                    warn_log "Auto-selected QuPath 0.5.1 for QC export (CUDA not available)"
                fi
            else
                log "Auto-selected QuPath 0.6 for QC export (matches CPU processing)"
            fi
            ;;
        "gpu")
            log "Using QuPath 0.5.1 for forced GPU mode QC export"
            ;;
        "cpu")
            log "Using QuPath 0.6 for forced CPU mode QC export"
            ;;
    esac
    
    # Validate the auto-selected QuPath
    if ! comprehensive_qupath_validation "$SELECTED_QUPATH_PATH" "$FORCE_MODE" "$CUDA_AVAILABLE"; then
        error_log "Auto-selected QuPath validation failed"
        exit 1
    fi
fi

# =============================================================================
# Main Pipeline
# =============================================================================
# Determine script directory for Groovy files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QC_GROOVY_SCRIPT="$SCRIPT_DIR/00b_export_annotated_thumbnails_qc.groovy"
UPLOAD_SCRIPT="$SCRIPT_DIR/upload_qc_thumbnails_to_drive.py"

# Validate QC script exists
if [ ! -f "$QC_GROOVY_SCRIPT" ]; then
    error_log "QC Groovy script not found: $QC_GROOVY_SCRIPT"
    exit 1
fi

# Validate upload script exists (if upload is requested)
if [ "$UPLOAD_TO_DRIVE" = true ] && [ ! -f "$UPLOAD_SCRIPT" ]; then
    error_log "Upload script not found: $UPLOAD_SCRIPT"
    error_log "Please ensure upload_qc_thumbnails_to_drive.py is in the same directory as this script"
    exit 1
fi

clear
echo -e "\033[1;35m===============================================\033[0m"
echo -e "\033[1;35m     PANK Thesis - QC Thumbnail Export Only  \033[0m"
echo -e "\033[1;35m     With Automatic QuPath Version Detection \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

log "Starting QC thumbnail export pipeline (annotations already imported)"
log "Processing mode: $FORCE_MODE"
log "Selected QuPath: $SELECTED_QUPATH_PATH (version: $DETECTED_QUPATH_VERSION)"
log "CUDA available: $CUDA_AVAILABLE"
log "Output directory: $OUTPUT_DIR"
log "Projects to process: ${#PROJECTS_TO_PROCESS[@]}"
if [ -n "$NUM_IMAGES" ]; then
    log "Number of images per project: $NUM_IMAGES"
else
    log "Number of images per project: all images"
fi
log "Upload to Google Drive: $UPLOAD_TO_DRIVE"
log "Verbose logging: $VERBOSE"
log "QC Groovy script: $QC_GROOVY_SCRIPT"

echo

# Create main output directory
mkdir -p "$OUTPUT_DIR"

# Process each project
SUCCESSFUL_EXPORTS=0
FAILED_EXPORTS=0
SUCCESSFUL_UPLOADS=0
FAILED_UPLOADS=0

for project in "${PROJECTS_TO_PROCESS[@]}"; do
    project_name=$(basename "$(dirname "$project")")
    project_output_dir="${OUTPUT_DIR}/${project_name}"
    
    log "Processing project: $project_name"
    log "Project file: $project"
    
    # Prepare QuPath arguments
    if [ -n "$NUM_IMAGES" ]; then
        log "Processing first $NUM_IMAGES images from project"
        # Use proper QuPath argument format with space separation
        QUPATH_CMD=("$SELECTED_QUPATH_PATH" script --project="$project" --args="$project_output_dir" --args="$NUM_IMAGES" "$QC_GROOVY_SCRIPT")
    else
        log "Processing all images from project"
        QUPATH_CMD=("$SELECTED_QUPATH_PATH" script --project="$project" --args="$project_output_dir" "$QC_GROOVY_SCRIPT")
    fi
    
    # Clean up any existing lock files from previous interrupted runs
    if [ -f "$project_output_dir/.qc_export_running" ]; then
        rm -f "$project_output_dir/.qc_export_running"
        verbose_log "Cleaned up existing lock file"
    fi
    
    # Clean up completion marker if force re-export is requested
    if [ "$FORCE_RE_EXPORT" = true ] && [ -f "$project_output_dir/.qc_export_completed" ]; then
        rm -f "$project_output_dir/.qc_export_completed"
        log "Removed completion marker to force re-export"
    fi
    
    # Step 1: Export QC thumbnails with TRIDENT annotations
    log "Exporting QC thumbnails with existing annotations..."
    if "${QUPATH_CMD[@]}" >> "$QUPATH_QC_LOG" 2>&1; then
        log "Successfully exported QC thumbnails for project: $project_name"
        ((SUCCESSFUL_EXPORTS++))
        
        # Check if thumbnails were actually created
        if [ -d "$project_output_dir" ] && [ "$(ls -A "$project_output_dir" 2>/dev/null)" ]; then
            thumbnail_count=$(find "$project_output_dir" -name "*.jpg" -o -name "*.png" | wc -l)
            log "Created $thumbnail_count QC thumbnails in: $project_output_dir"
        else
            warn_log "No thumbnail files found in output directory for project: $project_name"
            warn_log "This might indicate that no annotations were found in the project"
        fi
        
        # Step 2: Upload to Google Drive (if requested)
        if [ "$UPLOAD_TO_DRIVE" = true ]; then
            if [ -d "$project_output_dir" ] && [ "$(ls -A "$project_output_dir" 2>/dev/null)" ]; then
                log "Uploading QC thumbnails to Google Drive..."
                
                # Determine folder name
                if [ -n "$CUSTOM_FOLDER_NAME" ]; then
                    drive_folder_name="${CUSTOM_FOLDER_NAME}_${project_name}"
                else
                    drive_folder_name="QC_Thumbnails_${project_name}"
                fi
                
                # Upload using Python script
                if python3 "$UPLOAD_SCRIPT" \
                    --qc_thumbnails_dir "$project_output_dir" \
                    --credentials_file "$CREDENTIALS_FILE" \
                    --token_file "$TOKEN_FILE" \
                    --folder_name "$drive_folder_name" \
                    >> "$LOG_FILE" 2>&1; then
                    log "Successfully uploaded QC thumbnails for project: $project_name"
                    ((SUCCESSFUL_UPLOADS++))
                else
                    error_log "Failed to upload QC thumbnails for project: $project_name"
                    ((FAILED_UPLOADS++))
                fi
            else
                warn_log "No thumbnail files found to upload for project: $project_name"
                ((FAILED_UPLOADS++))
            fi
        fi
    else
        error_log "Failed to export QC thumbnails for project: $project_name"
        ((FAILED_EXPORTS++))
        if [ "$UPLOAD_TO_DRIVE" = true ]; then
            ((FAILED_UPLOADS++))
        fi
    fi
    
    echo
done

# =============================================================================
# Summary
# =============================================================================
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           QC Export Complete                  \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "QC thumbnail export pipeline completed"
log "QuPath Configuration:"
log "  Selected QuPath: $SELECTED_QUPATH_PATH"
log "  Detected version: $DETECTED_QUPATH_VERSION"
log "  Processing mode: $FORCE_MODE"
log "  CUDA available: $CUDA_AVAILABLE"
log "Export Results:"
log "  Successfully exported: $SUCCESSFUL_EXPORTS projects"
log "  Failed to export: $FAILED_EXPORTS projects"
if [ "$UPLOAD_TO_DRIVE" = true ]; then
    log "Upload Results:"
    log "  Successfully uploaded: $SUCCESSFUL_UPLOADS projects"
    log "  Failed to upload: $FAILED_UPLOADS projects"
fi
log "Logs:"
log "  Main log: $LOG_FILE"
log "  Error log: $ERROR_LOG"
log "  QuPath output: $QUPATH_QC_LOG"

if [ -d "$OUTPUT_DIR" ]; then
    log "Local QC thumbnails available in: $(pwd)/$OUTPUT_DIR"
fi 