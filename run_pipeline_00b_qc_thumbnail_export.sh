#!/bin/bash

# =============================================================================
# PANK Thesis Project - QC Thumbnail Export (Annotations Already Imported)
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script exports QC thumbnails from QuPath projects that already have
# TRIDENT annotations imported. It does NOT re-import annotations.
# =============================================================================

# =============================================================================
# Configuration
# =============================================================================
# Default QuPath path (can be overridden with -q option)
DEFAULT_QUPATH_PATH="${QUPATH_PATH:-/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6.0/qupath/build/dist/QuPath/bin/QuPath}"

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -p, --project PATH     Path to QuPath project file (.qpproj)"
    echo "  -q, --qupath PATH      Path to QuPath executable (optional)"
    echo "  -o, --output DIR       Output directory for thumbnails (default: qc_thumbnails)"
    echo "  -c, --credentials FILE Path to Google Drive credentials file (default: drive_credentials.json)"
    echo "  -t, --token FILE       Path to token file (default: token.json)"
    echo "  -f, --folder NAME      Custom Google Drive folder name"
    echo "  -s, --test             Process test project (QuPath_MP_PDAC5/project.qpproj)"
    echo "  -a, --all              Process all QuPath projects in current directory"
    echo "  -h, --help            Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -s                                    # Export QC for test project"
    echo "  $0 -p QuPath_MP_PDAC100/project.qpproj  # Export for specific project"
    echo "  $0 -a                                    # Export all projects and upload to Drive"
    echo "  $0 -p project.qpproj -q /path/to/QuPath  # Custom QuPath path"
    echo
    echo "Prerequisites:"
    echo "  - QuPath projects must already have TRIDENT annotations imported"
    echo "  - Google Drive credentials and token files must be available"
    echo "  - Python with required packages (google-api-python-client, etc.)"
    echo "  - If QuPath path not specified, uses default configuration"
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
QUPATH_TRIDENT_LOG="${LOG_DIR}/qupath_trident_${TIMESTAMP}.log"
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

# =============================================================================
# Command Line Argument Parsing
# =============================================================================
PROJECT_PATH=""
OUTPUT_DIR="qc_thumbnails"
CREDENTIALS_FILE="drive_credentials.json"
TOKEN_FILE="token.json"
CUSTOM_FOLDER_NAME=""
PROCESS_TEST=false
PROCESS_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        -q|--qupath)
            DEFAULT_QUPATH_PATH="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
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
if [ ! -f "$DEFAULT_QUPATH_PATH" ]; then
    error_log "QuPath not found at $DEFAULT_QUPATH_PATH"
    error_log "Please specify correct QuPath path with -q option"
    exit 1
fi

log "Using QuPath executable: $DEFAULT_QUPATH_PATH"

# Check Google Drive authentication files
if [ ! -f "$CREDENTIALS_FILE" ]; then
    error_log "Google Drive credentials file not found: $CREDENTIALS_FILE"
    exit 1
fi

if [ ! -f "$TOKEN_FILE" ]; then
    error_log "Google Drive token file not found: $TOKEN_FILE"
    error_log "Please run generate_drive_token.py first"
    exit 1
fi

# Check Python
if ! command -v python3 &> /dev/null; then
    error_log "python3 not found. Please install Python 3"
    exit 1
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
echo -e "\033[1;35m     PANK Thesis - QC Thumbnail Export Only  \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

log "Starting QC thumbnail export pipeline (annotations already imported)"
log "Output directory: $OUTPUT_DIR"
log "Projects to process: ${#PROJECTS_TO_PROCESS[@]}"
log "Google Drive credentials: $CREDENTIALS_FILE"
log "Google Drive token: $TOKEN_FILE"

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
    
    # Step 1: Export QC thumbnails with TRIDENT annotations
    log "Exporting QC thumbnails with existing annotations..."
    if "$DEFAULT_QUPATH_PATH" script --project="$project" \
                      --args="$project_output_dir" \
                      00b_export_annotated_thumbnails_qc.groovy \
                      >> "$QUPATH_QC_LOG" 2>&1; then
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
        
        # Step 3: Upload to Google Drive
        if [ -d "$project_output_dir" ] && [ "$(ls -A "$project_output_dir" 2>/dev/null)" ]; then
            log "Uploading QC thumbnails to Google Drive..."
            
            # Determine folder name
            if [ -n "$CUSTOM_FOLDER_NAME" ]; then
                drive_folder_name="${CUSTOM_FOLDER_NAME}_${project_name}"
            else
                drive_folder_name="QC_Thumbnails_${project_name}"
            fi
            
            # Upload using Python script
            if python3 upload_qc_thumbnails_to_drive.py \
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
    else
        error_log "Failed to export QC thumbnails for project: $project_name"
        ((FAILED_EXPORTS++))
        ((FAILED_UPLOADS++))
    fi
    
    echo
done

# =============================================================================
# Summary
# =============================================================================
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           QC Export Complete                  \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "QC thumbnail export and upload pipeline completed"
log "Export Results:"
log "  Successfully exported: $SUCCESSFUL_EXPORTS projects"
log "  Failed to export: $FAILED_EXPORTS projects"
log "Upload Results:"
log "  Successfully uploaded: $SUCCESSFUL_UPLOADS projects"
log "  Failed to upload: $FAILED_UPLOADS projects"
log "Check $LOG_FILE for detailed logs"
log "Check $ERROR_LOG for error logs"
log "QuPath QC export output is in $QUPATH_QC_LOG"

if [ -d "$OUTPUT_DIR" ]; then
    log "Local QC thumbnails available in: $(pwd)/$OUTPUT_DIR"
fi 