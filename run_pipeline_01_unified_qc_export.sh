#!/bin/bash

# =============================================================================
# PANK Thesis Project - Unified Cell Detection QC Export
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script exports QC thumbnails showing both TRIDENT annotations and
# StarDist cell detections, compatible with both CPU and GPU processing modes.
# =============================================================================

# =============================================================================
# Configuration
# =============================================================================
# QuPath paths (same as unified pipeline)
QUPATH_06_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6.0/qupath/build/dist/QuPath/bin/QuPath"
QUPATH_051_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build_0.5.1/qupath/build/dist/QuPath/bin/QuPath"

# Default output directory
QC_OUTPUT_DIR="qc_cell_detection_thumbnails"

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -p, --project PATH    Export QC for specific QuPath project (.qpproj)"
    echo "  -s, --test           Export QC for test project only (QuPath_MP_PDAC5)"
    echo "  -a, --all            Export QC for all QuPath projects"
    echo "  -o, --output DIR     Output directory for QC thumbnails (default: $QC_OUTPUT_DIR)"
    echo "  -n, --num-images N   Process only first N images (default: all images)"
    echo "  -m, --mode MODE      Processing mode: 'cpu', 'gpu', or 'auto' (default: auto)"
    echo "  -q, --qupath PATH    Force specific QuPath executable path"
    echo "  -u, --upload         Upload to Google Drive after export"
    echo "  -t, --token PATH     Path to Google Drive token file (required for upload)"
    echo "  -v, --verbose        Enable verbose logging"
    echo "  -h, --help           Show this help message"
    echo
    echo "Processing Modes:"
    echo "  auto    Automatically detect best QuPath configuration (default)"
    echo "  cpu     Use QuPath 0.6 (CPU-optimized)"
    echo "  gpu     Use QuPath 0.5.1 (GPU-enabled)"
    echo
    echo "Examples:"
    echo "  $0 -s                           # Test project QC with auto-detection"
    echo "  $0 -p QuPath_MP_PDAC100/project.qpproj -n 10 -u -t token.json -m gpu"
    echo "  $0 -a -n 5 -u -t /path/to/token.json -m cpu  # All projects, first 5 images each with CPU mode and upload"
    echo "  $0 -s -o custom_qc_dir -n 10 -v # Custom output dir, first 10 images with verbose logging"
    echo
    echo "Note: For Google Drive upload, you need:"
    echo "      - token.json (generated with generate_drive_token.py)"
    exit 1
}

# =============================================================================
# Logging Configuration
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/unified_qc_export_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/unified_qc_export_${TIMESTAMP}_error.log"
QUPATH_LOG="${LOG_DIR}/qupath_qc_unified_${TIMESTAMP}.log"

# Logging functions
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
        echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;36mVERBOSE: $1\033[0m" | tee -a "$LOG_FILE"
    fi
}

# =============================================================================
# System Detection Functions (reused from unified pipeline)
# =============================================================================
check_cuda_availability() {
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            return 0
        fi
    fi
    return 1
}

determine_optimal_qupath() {
    verbose_log "Determining optimal QuPath configuration for QC export..."
    
    local cuda_available=false
    local qupath_051_available=false
    local qupath_06_available=false
    
    # Check CUDA availability
    if check_cuda_availability; then
        cuda_available=true
        verbose_log "CUDA is available"
    fi
    
    # Check QuPath installations
    if [ -f "$QUPATH_051_PATH" ] && [ -x "$QUPATH_051_PATH" ]; then
        qupath_051_available=true
        verbose_log "QuPath 0.5.1 available"
    fi
    
    if [ -f "$QUPATH_06_PATH" ] && [ -x "$QUPATH_06_PATH" ]; then
        qupath_06_available=true
        verbose_log "QuPath 0.6 available"
    fi
    
    # Decision logic (prefer the same as processing)
    if [ "$cuda_available" = true ] && [ "$qupath_051_available" = true ]; then
        echo "$QUPATH_051_PATH"
        log "Auto-selected QuPath 0.5.1 for QC export (matches GPU processing)" >&2
    elif [ "$qupath_06_available" = true ]; then
        echo "$QUPATH_06_PATH"
        log "Auto-selected QuPath 0.6 for QC export (matches CPU processing)" >&2
    elif [ "$qupath_051_available" = true ]; then
        echo "$QUPATH_051_PATH"
        warn_log "Using QuPath 0.5.1 for QC export (CUDA may not be available)" >&2
    else
        error_log "No suitable QuPath installation found for QC export" >&2
        return 1
    fi
}

setup_qupath_for_mode() {
    local mode="$1"
    
    case "$mode" in
        "gpu")
            if [ -f "$QUPATH_051_PATH" ] && [ -x "$QUPATH_051_PATH" ]; then
                echo "$QUPATH_051_PATH"
                log "Using QuPath 0.5.1 for GPU mode QC export" >&2
            else
                error_log "QuPath 0.5.1 not found for GPU mode: $QUPATH_051_PATH" >&2
                return 1
            fi
            ;;
        "cpu")
            if [ -f "$QUPATH_06_PATH" ] && [ -x "$QUPATH_06_PATH" ]; then
                echo "$QUPATH_06_PATH"
                log "Using QuPath 0.6 for CPU mode QC export" >&2
            else
                error_log "QuPath 0.6 not found for CPU mode: $QUPATH_06_PATH" >&2
                return 1
            fi
            ;;
        "auto")
            determine_optimal_qupath
            ;;
        *)
            error_log "Invalid mode: $mode" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# Command Line Argument Parsing
# =============================================================================
PROJECT_PATH=""
PROCESS_ALL=false
TEST_ONLY=false
FORCE_MODE="auto"
CUSTOM_QUPATH_PATH=""
UPLOAD_TO_DRIVE=false
TOKEN_PATH=""
VERBOSE=false
NUM_IMAGES="all"  # Default to processing all images

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        -s|--test)
            TEST_ONLY=true
            shift
            ;;
        -a|--all)
            PROCESS_ALL=true
            shift
            ;;
        -o|--output)
            QC_OUTPUT_DIR="$2"
            shift 2
            ;;
        -n|--num-images)
            NUM_IMAGES="$2"
            shift 2
            ;;
        -m|--mode)
            FORCE_MODE="$2"
            shift 2
            ;;
        -q|--qupath)
            CUSTOM_QUPATH_PATH="$2"
            shift 2
            ;;
        -u|--upload)
            UPLOAD_TO_DRIVE=true
            shift
            ;;
        -t|--token)
            TOKEN_PATH="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
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

# Validate arguments
mode_count=0
[ "$PROCESS_ALL" = true ] && ((mode_count++))
[ "$TEST_ONLY" = true ] && ((mode_count++))
[ -n "$PROJECT_PATH" ] && ((mode_count++))

if [ "$mode_count" -ne 1 ]; then
    error_log "Please specify exactly one processing mode: -a, -s, or -p"
    show_help
fi

# Validate force mode
if [[ ! "$FORCE_MODE" =~ ^(auto|cpu|gpu)$ ]]; then
    error_log "Invalid mode: $FORCE_MODE. Must be 'auto', 'cpu', or 'gpu'"
    show_help
fi

# Validate num-images parameter
if [[ "$NUM_IMAGES" != "all" ]] && ! [[ "$NUM_IMAGES" =~ ^[0-9]+$ ]]; then
    error_log "Invalid num-images value: $NUM_IMAGES. Must be 'all' or a positive integer"
    show_help
fi

if [[ "$NUM_IMAGES" =~ ^[0-9]+$ ]] && [ "$NUM_IMAGES" -le 0 ]; then
    error_log "Invalid num-images value: $NUM_IMAGES. Must be greater than 0"
    show_help
fi

# Validate token file if upload is requested
if [ "$UPLOAD_TO_DRIVE" = true ]; then
    if [ -z "$TOKEN_PATH" ]; then
        error_log "Token file path is required when upload is enabled. Use -t option."
        show_help
    fi
    if [ ! -f "$TOKEN_PATH" ]; then
        error_log "Token file not found: $TOKEN_PATH"
        error_log "Please run generate_drive_token.py first"
        exit 1
    fi
    log "Token file validated: $TOKEN_PATH"
fi

# =============================================================================
# Pipeline Initialization
# =============================================================================
clear
echo -e "\033[1;35m===============================================\033[0m"
echo -e "\033[1;35m     PANK Thesis - Unified Cell Detection QC  \033[0m"
echo -e "\033[1;35m     Compatible with CPU/GPU Processing Modes \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

log "Starting unified cell detection QC export"
log "Mode: $FORCE_MODE"
log "Output directory: $QC_OUTPUT_DIR"
log "Number of images: $NUM_IMAGES"
log "Upload to Drive: $UPLOAD_TO_DRIVE"
log "Verbose logging: $VERBOSE"

# Determine QuPath executable
if [ -n "$CUSTOM_QUPATH_PATH" ]; then
    if [ ! -f "$CUSTOM_QUPATH_PATH" ] || [ ! -x "$CUSTOM_QUPATH_PATH" ]; then
        error_log "Custom QuPath path not found or not executable: $CUSTOM_QUPATH_PATH"
        exit 1
    fi
    SELECTED_QUPATH_PATH="$CUSTOM_QUPATH_PATH"
    log "Using custom QuPath: $CUSTOM_QUPATH_PATH"
else
    SELECTED_QUPATH_PATH=$(setup_qupath_for_mode "$FORCE_MODE")
    if [ $? -ne 0 ]; then
        exit 1
    fi
fi

# Validate QC script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QC_SCRIPT="$SCRIPT_DIR/00c_export_cell_detection_qc_thumbnails.groovy"

if [ ! -f "$QC_SCRIPT" ]; then
    error_log "QC export script not found: $QC_SCRIPT"
    exit 1
fi

log "Using QC script: $(basename "$QC_SCRIPT")"
log "Selected QuPath: $SELECTED_QUPATH_PATH"

# =============================================================================
# Processing Function
# =============================================================================
export_qc_for_project() {
    local project_file="$1"
    local project_name=$(basename "$(dirname "$project_file")")
    
    log "Exporting QC thumbnails for project: $project_name" >&2
    verbose_log "Project file: $project_file" >&2
    
    if [ ! -f "$project_file" ]; then
        error_log "Project file not found: $project_file" >&2
        return 1
    fi
    
    # Create project-specific output directory
    local project_qc_dir="${QC_OUTPUT_DIR}/${project_name}"
    mkdir -p "$project_qc_dir"
    
    # Run QC export
    verbose_log "Running QC export for $project_name" >&2
    if "$SELECTED_QUPATH_PATH" script \
            --project="$project_file" \
            --args "$project_qc_dir" \
            --args "$NUM_IMAGES" \
            "$QC_SCRIPT" \
            >> "$QUPATH_LOG" 2>&1; then
        log "QC export completed for $project_name" >&2
        echo "$project_qc_dir"  # Return the output directory (only this goes to stdout)
        return 0
    else
        error_log "QC export failed for $project_name" >&2
        return 1
    fi
}

# =============================================================================
# Main Processing Logic
# =============================================================================
successful_exports=0
failed_exports=0
start_time=$(date +%s)
qc_directories=()

# Base directory for QuPath projects (parent of THESIS_PANK)
HE_BASE_DIR="/u/trinhvq/Documents/maxencepelloux/HE"

# Determine projects to process based on processing mode
if [ "$TEST_ONLY" = true ]; then
    # Use mode-specific test projects based on QuPath_MP_PDAC2
    # First determine the actual processing mode if auto
    if [ "$FORCE_MODE" = "auto" ]; then
        # Determine actual mode based on selected QuPath
        if [[ "$SELECTED_QUPATH_PATH" == *"0.5.1"* ]]; then
            ACTUAL_MODE="GPU"
        elif [[ "$SELECTED_QUPATH_PATH" == *"0.6"* ]]; then
            ACTUAL_MODE="CPU"
        else
            ACTUAL_MODE="GPU"  # Default fallback
        fi
    else
        case "$FORCE_MODE" in
            "gpu") ACTUAL_MODE="GPU" ;;
            "cpu") ACTUAL_MODE="CPU" ;;
            *) ACTUAL_MODE="GPU" ;;
        esac
    fi
    
    case "$ACTUAL_MODE" in
        "GPU")
            project_files=("$HE_BASE_DIR/QuPath_MP_PDAC2_0.5.1/project.qpproj")
            log "Processing GPU test project (QuPath_MP_PDAC2_0.5.1)"
            ;;
        "CPU")
            project_files=("$HE_BASE_DIR/QuPath_MP_PDAC2_0.6.0/project.qpproj")
            log "Processing CPU test project (QuPath_MP_PDAC2_0.6.0)"
            ;;
        *)
            error_log "Unknown processing mode: $ACTUAL_MODE"
            exit 1
            ;;
    esac
elif [ -n "$PROJECT_PATH" ]; then
    # Handle both relative and absolute paths
    if [[ "$PROJECT_PATH" = /* ]]; then
        # Absolute path
        project_files=("$PROJECT_PATH")
    else
        # Relative path - assume it's relative to HE directory
        project_files=("$HE_BASE_DIR/$PROJECT_PATH")
    fi
    log "Processing single project: ${project_files[0]}"
elif [ "$PROCESS_ALL" = true ]; then
    # Find all QuPath projects in HE directory
    project_files=("$HE_BASE_DIR"/QuPath_MP_PDAC*/project.qpproj)
    log "Processing all QuPath projects in $HE_BASE_DIR"
fi

# Validate project files
if [ ${#project_files[@]} -eq 0 ] || [ ! -f "${project_files[0]}" ]; then
    error_log "No QuPath project files found"
    exit 1
fi

log "Found ${#project_files[@]} QuPath project(s) to process"

# Process projects
for project_file in "${project_files[@]}"; do
    if qc_dir=$(export_qc_for_project "$project_file"); then
        ((successful_exports++))
        qc_directories+=("$qc_dir")
    else
        ((failed_exports++))
    fi
done

# Wait for files to be fully written to disk
if [ "$UPLOAD_TO_DRIVE" = true ] && [ ${#qc_directories[@]} -gt 0 ]; then
    log "Waiting for QC files to be fully written to disk..."
    sleep 5
fi

# =============================================================================
# Google Drive Upload (if requested)
# =============================================================================
if [ "$UPLOAD_TO_DRIVE" = true ] && [ ${#qc_directories[@]} -gt 0 ]; then
    log "Uploading QC thumbnails to Google Drive..."
    
    # Check if upload script exists
    UPLOAD_SCRIPT="$SCRIPT_DIR/upload_qc_thumbnails_to_drive.py"
    if [ ! -f "$UPLOAD_SCRIPT" ]; then
        error_log "Upload script not found: $UPLOAD_SCRIPT"
    else
        # Define authentication files (same pattern as working scripts)
        # Use token.json for both credentials and token (same as working scripts)
        if [ ! -f "$TOKEN_PATH" ] && [ -f "../$(basename "$TOKEN_PATH")" ]; then
            TOKEN_FILE="../$(basename "$TOKEN_PATH")"
        else
            TOKEN_FILE="$TOKEN_PATH"
        fi
        
        # Use the same file for both credentials and token (like working scripts)
        CREDENTIALS_FILE="$TOKEN_FILE"
        
        log "Using token file for both credentials and token: $TOKEN_FILE"
        
        # Upload each QC directory
        for qc_dir in "${qc_directories[@]}"; do
            if [ -d "$qc_dir" ]; then
                project_name=$(basename "$qc_dir")
                
                # Verify QC files exist before upload
                qc_file_count=$(find "$qc_dir" -name "*.jpg" -o -name "*.png" | wc -l)
                
                if [ "$qc_file_count" -eq 0 ]; then
                    warn_log "No QC thumbnail files found in $qc_dir, skipping upload"
                    continue
                fi
                
                log "Uploading QC thumbnails for $project_name ($qc_file_count files)..."
                
                verbose_log "Running upload command: python3 $UPLOAD_SCRIPT --qc_thumbnails_dir $qc_dir --folder_name Unified_Cell_Detection_QC_${project_name}_${TIMESTAMP} --credentials_file $CREDENTIALS_FILE --token_file $TOKEN_FILE"
                
                # Upload using Python script (same pattern as working scripts)
                if python3 "$UPLOAD_SCRIPT" \
                    --qc_thumbnails_dir "$qc_dir" \
                    --folder_name "Unified_Cell_Detection_QC_${project_name}_${TIMESTAMP}" \
                    --credentials_file "$CREDENTIALS_FILE" \
                    --token_file "$TOKEN_FILE" \
                    >> "$LOG_FILE" 2>&1; then
                    log "Successfully uploaded QC thumbnails for $project_name"
                else
                    error_log "Failed to upload QC thumbnails for $project_name"
                fi
            else
                warn_log "QC directory not found: $qc_dir"
            fi
        done
    fi
fi

# =============================================================================
# Pipeline Completion
# =============================================================================
end_time=$(date +%s)
total_time=$((end_time - start_time))

echo
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           Unified QC Export Complete         \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "Unified cell detection QC export completed"
log "Processing mode: $FORCE_MODE"
log "Successful exports: $successful_exports"
log "Failed exports: $failed_exports"
log "Total time: $((total_time / 60)) minutes"
log "QC directories created: ${#qc_directories[@]}"

for qc_dir in "${qc_directories[@]}"; do
    if [ -d "$qc_dir" ]; then
        log "  - $qc_dir"
    fi
done

echo
echo "QC Export Summary:"
echo "  Processing mode: $FORCE_MODE"
echo "  Successful exports: $successful_exports"
echo "  Failed exports: $failed_exports"
echo "  Upload to Drive: $UPLOAD_TO_DRIVE"
echo "  Processing time: $((total_time / 60)) minutes"
echo

if [ "$failed_exports" -gt 0 ]; then
    exit 1
else
    exit 0
fi 