#!/bin/bash

# =============================================================================
# PANK Thesis Project - QC Thumbnail Export
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script exports annotated thumbnails from QuPath projects for QC
# and optionally uploads them to Google Drive for easy review.
# =============================================================================

# =============================================================================
# Configuration
# =============================================================================
# Set QUPATH_PATH environment variable or provide default
QUPATH_PATH=${QUPATH_PATH:-"/opt/QuPath/bin/QuPath"}

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -p, --project PATH     Path to QuPath project file (.qpproj)"
    echo "  -o, --output DIR       Output directory for thumbnails (default: qc_thumbnails)"
    echo "  -u, --upload           Upload to Google Drive after export"
    echo "  -d, --drive-folder ID  Google Drive folder ID (required if --upload used)"
    echo "  -s, --test             Process test project (QuPath_MP_PDAC5/project.qpproj)"
    echo "  -a, --all              Process all QuPath projects in current directory"
    echo "  -h, --help            Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -s                                    # Export QC thumbnails for test project"
    echo "  $0 -p QuPath_MP_PDAC100/project.qpproj  # Export for specific project"
    echo "  $0 -a -u -d 1xXxXxXxXxXxXxXxXxXxXx       # Export all projects and upload to Drive"
    echo
    echo "Prerequisites:"
    echo "  - QuPath must be installed and QUPATH_PATH set correctly"
    echo "  - For Google Drive upload: 'rclone' must be configured"
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
QUPATH_LOG="${LOG_DIR}/qupath_qc_${TIMESTAMP}.log"

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

# =============================================================================
# Command Line Argument Parsing
# =============================================================================
PROJECT_PATH=""
OUTPUT_DIR="qc_thumbnails"
UPLOAD_TO_DRIVE=false
DRIVE_FOLDER_ID=""
PROCESS_TEST=false
PROCESS_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -u|--upload)
            UPLOAD_TO_DRIVE=true
            shift
            ;;
        -d|--drive-folder)
            DRIVE_FOLDER_ID="$2"
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
# Check QuPath installation
if [ ! -f "$QUPATH_PATH" ]; then
    error_log "QuPath not found at $QUPATH_PATH"
    error_log "Please set QUPATH_PATH environment variable or install QuPath"
    exit 1
fi

# Validate upload requirements
if [ "$UPLOAD_TO_DRIVE" = true ]; then
    if [ -z "$DRIVE_FOLDER_ID" ]; then
        error_log "Google Drive folder ID required when using --upload"
        show_help
    fi
    
    if ! command -v rclone &> /dev/null; then
        error_log "rclone not found. Please install and configure rclone for Google Drive upload"
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
# Main Pipeline
# =============================================================================
clear
echo -e "\033[1;35m===============================================\033[0m"
echo -e "\033[1;35m     PANK Thesis - QC Thumbnail Export       \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

log "Starting QC thumbnail export pipeline"
log "Output directory: $OUTPUT_DIR"
log "Projects to process: ${#PROJECTS_TO_PROCESS[@]}"

if [ "$UPLOAD_TO_DRIVE" = true ]; then
    log "Will upload to Google Drive folder: $DRIVE_FOLDER_ID"
fi

echo

# Create main output directory
mkdir -p "$OUTPUT_DIR"

# Process each project
SUCCESSFUL_EXPORTS=0
FAILED_EXPORTS=0

for project in "${PROJECTS_TO_PROCESS[@]}"; do
    project_name=$(basename "$(dirname "$project")")
    project_output_dir="${OUTPUT_DIR}/${project_name}"
    
    log "Processing project: $project_name"
    log "Project file: $project"
    
    # Run QuPath export script
    if "$QUPATH_PATH" script --project="$project" \
                      --args="$project_output_dir" \
                      00b_export_annotated_thumbnails_qc.groovy \
                      >> "$QUPATH_LOG" 2>&1; then
        log "Successfully exported QC thumbnails for project: $project_name"
        ((SUCCESSFUL_EXPORTS++))
        
        # Upload to Google Drive if requested
        if [ "$UPLOAD_TO_DRIVE" = true ] && [ -d "$project_output_dir" ]; then
            log "Uploading QC thumbnails to Google Drive..."
            if rclone copy "$project_output_dir" "gdrive:$DRIVE_FOLDER_ID/$project_name" --progress; then
                log "Successfully uploaded QC thumbnails for project: $project_name"
            else
                warn_log "Failed to upload QC thumbnails for project: $project_name"
            fi
        fi
    else
        error_log "Failed to export QC thumbnails for project: $project_name"
        ((FAILED_EXPORTS++))
    fi
    
    echo
done

# =============================================================================
# Summary
# =============================================================================
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           Pipeline Execution Complete         \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "QC thumbnail export pipeline completed"
log "Successfully processed: $SUCCESSFUL_EXPORTS projects"
log "Failed to process: $FAILED_EXPORTS projects"
log "Check $LOG_FILE for detailed logs"
log "Check $ERROR_LOG for error logs"
log "QuPath verbose output is in $QUPATH_LOG"

if [ -d "$OUTPUT_DIR" ]; then
    log "QC thumbnails available in: $(pwd)/$OUTPUT_DIR"
fi 