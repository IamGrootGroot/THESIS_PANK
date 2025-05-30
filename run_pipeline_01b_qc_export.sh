#!/bin/bash

# =============================================================================
# PANK Thesis Project - Cell Detection QC Export and Upload
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script exports QC thumbnails showing both TRIDENT annotations and
# StarDist cell detections, then uploads them to Google Drive for review.
# =============================================================================

# =============================================================================
# Default QuPath Configuration
# =============================================================================
# Default QuPath path (can be overridden with -q option)
DEFAULT_QUPATH_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6.0/qupath/build/dist/QuPath/bin/QuPath"

# Configuration
QC_OUTPUT_DIR="qc_cell_detection_thumbnails"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p PROJECT    Export QC for specific QuPath project (.qpproj)"
    echo "  -q PATH       Path to QuPath executable (optional)"
    echo "  -a            Export QC for all QuPath projects"
    echo "  -s            Export QC for test project only (QuPath_MP_PDAC5)"
    echo "  -o DIR        Output directory for QC thumbnails (default: $QC_OUTPUT_DIR)"
    echo "  -u            Upload to Google Drive after export"
    echo "  -h            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s                           # Test project QC only"
    echo "  $0 -p QuPath_MP_PDAC100/project.qpproj -u"
    echo "  $0 -a -u                        # All projects with upload"
    echo "  $0 -s -o custom_qc_dir -u       # Custom output dir with upload"
    echo "  $0 -p project.qpproj -q /path/to/QuPath  # Custom QuPath path"
    echo ""
    echo "Note: For Google Drive upload, ensure you have:"
    echo "      - drive_credentials.json"
    echo "      - token.json (generated with generate_drive_token.py)"
    echo "      If QuPath path not specified, uses default configuration."
    exit 1
}

# Logging setup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/qc_export_${TIMESTAMP}.log"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
}

warn_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "$LOG_FILE"
}

# Parse arguments
PROJECT_PATH=""
PROCESS_ALL=false
TEST_ONLY=false
UPLOAD_TO_DRIVE=false

while getopts "p:q:aso:uh" opt; do
    case $opt in
        p) PROJECT_PATH="$OPTARG" ;;
        q) DEFAULT_QUPATH_PATH="$OPTARG" ;;
        a) PROCESS_ALL=true ;;
        s) TEST_ONLY=true ;;
        o) QC_OUTPUT_DIR="$OPTARG" ;;
        u) UPLOAD_TO_DRIVE=true ;;
        h) show_help ;;
        *) show_help ;;
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

# Initialize
echo "==============================================="
echo "     PANK Thesis - Cell Detection QC Export"
echo "==============================================="
echo "Output directory: $QC_OUTPUT_DIR"
echo "Upload to Drive: $UPLOAD_TO_DRIVE"
echo

log "Starting Cell Detection QC export"

# =============================================================================
# QuPath Path Configuration and Validation
# =============================================================================
log "Using QuPath path: $DEFAULT_QUPATH_PATH"

# Validate QuPath installation
if [ ! -f "$DEFAULT_QUPATH_PATH" ]; then
    error_log "QuPath not found at $DEFAULT_QUPATH_PATH"
    error_log "Please specify correct QuPath path with -q option"
    exit 1
fi

log "QuPath executable validated: $DEFAULT_QUPATH_PATH"

# Validate setup
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QC_SCRIPT="$SCRIPT_DIR/00c_export_cell_detection_qc_thumbnails.groovy"

if [ ! -f "$QC_SCRIPT" ]; then
    error_log "QC export script not found: $QC_SCRIPT"
    exit 1
fi

log "Setup validation completed successfully"

# Function to export QC for a single project
export_qc_for_project() {
    local project_file="$1"
    local project_name=$(basename "$(dirname "$project_file")")
    
    log "Exporting QC thumbnails for project: $project_name"
    
    if [ ! -f "$project_file" ]; then
        error_log "Project file not found: $project_file"
        return 1
    fi
    
    # Create project-specific output directory
    local project_qc_dir="${QC_OUTPUT_DIR}/${project_name}"
    mkdir -p "$project_qc_dir"
    log "Created QC output directory: $project_qc_dir"
    
    # Run QC export with explicit output directory argument
    log "Running QuPath QC export script for $project_name..."
    if "$DEFAULT_QUPATH_PATH" script \
            --project="$project_file" \
            --args="$project_qc_dir" \
            "$QC_SCRIPT" \
            >> "$LOG_FILE" 2>&1; then
        log "QC export completed for $project_name"
        
        # Verify that files were actually created
        local file_count=$(find "$project_qc_dir" -name "*.jpg" -o -name "*.png" | wc -l)
        if [ "$file_count" -gt 0 ]; then
            log "Created $file_count QC thumbnail files in: $project_qc_dir"
            echo "$project_qc_dir"  # Return the output directory
            return 0
        else
            warn_log "No QC thumbnail files were created for $project_name"
            warn_log "This might indicate no annotations or detections were found"
            return 1
        fi
    else
        error_log "QC export failed for $project_name"
        error_log "Check QuPath logs for detailed error information"
        return 1
    fi
}

# Main processing
successful_exports=0
failed_exports=0
start_time=$(date +%s)
qc_directories=()

if [ "$TEST_ONLY" = true ]; then
    # Process test project only
    log "Processing test project only (QuPath_MP_PDAC5)"
    if qc_dir=$(export_qc_for_project "QuPath_MP_PDAC5/project.qpproj"); then
        ((successful_exports++))
        qc_directories+=("$qc_dir")
    else
        ((failed_exports++))
    fi
    
elif [ -n "$PROJECT_PATH" ]; then
    # Process single project
    log "Processing single project: $PROJECT_PATH"
    if qc_dir=$(export_qc_for_project "$PROJECT_PATH"); then
        ((successful_exports++))
        qc_directories+=("$qc_dir")
    else
        ((failed_exports++))
    fi
    
elif [ "$PROCESS_ALL" = true ]; then
    # Process all projects
    log "Processing all QuPath projects"
    
    project_files=(QuPath_MP_PDAC*/project.qpproj)
    
    if [ ${#project_files[@]} -eq 0 ] || [ ! -f "${project_files[0]}" ]; then
        error_log "No QuPath project files found"
        exit 1
    fi
    
    log "Found ${#project_files[@]} QuPath projects to process"
    
    for project_file in "${project_files[@]}"; do
        if qc_dir=$(export_qc_for_project "$project_file"); then
            ((successful_exports++))
            qc_directories+=("$qc_dir")
        else
            ((failed_exports++))
        fi
    done
fi

# Upload to Google Drive if requested
if [ "$UPLOAD_TO_DRIVE" = true ] && [ ${#qc_directories[@]} -gt 0 ]; then
    log "Uploading QC thumbnails to Google Drive..."
    
    # Check if upload script exists
    UPLOAD_SCRIPT="$SCRIPT_DIR/upload_qc_thumbnails_to_drive.py"
    if [ ! -f "$UPLOAD_SCRIPT" ]; then
        error_log "Upload script not found: $UPLOAD_SCRIPT"
    else
        # Check for required authentication files
        CREDENTIALS_FILE="drive_credentials.json"
        TOKEN_FILE="token.json"
        
        if [ ! -f "$TOKEN_FILE" ]; then
            error_log "Token file not found: $TOKEN_FILE"
            error_log "Please run generate_drive_token.py first to create the token file"
        else
            log "Found token file: $TOKEN_FILE"
            
            # Credentials file is optional if token is valid
            if [ ! -f "$CREDENTIALS_FILE" ]; then
                warn_log "Credentials file not found: $CREDENTIALS_FILE (will try to use token file only)"
            else
                log "Found credentials file: $CREDENTIALS_FILE"
            fi
            
            # Wait for files to be fully written to disk before upload
            log "Waiting for QC files to be fully written to disk..."
            sleep 3
            
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
                    
                    # Upload using Python script (same pattern as working scripts)
                    if python3 "$UPLOAD_SCRIPT" \
                        --qc_thumbnails_dir "$qc_dir" \
                        --credentials_file "$CREDENTIALS_FILE" \
                        --token_file "$TOKEN_FILE" \
                        --folder_name "Cell_Detection_QC_${project_name}_${TIMESTAMP}" \
                        >> "$LOG_FILE" 2>&1; then
                        log "Successfully uploaded QC thumbnails for $project_name"
                    else
                        error_log "Failed to upload QC thumbnails for $project_name"
                        error_log "Check $LOG_FILE for detailed error information"
                    fi
                else
                    warn_log "QC directory not found: $qc_dir"
                fi
            done
        fi
    fi
fi

# Summary
end_time=$(date +%s)
total_time=$((end_time - start_time))

echo
echo "==============================================="
echo "           Cell Detection QC Export Complete"
echo "==============================================="
log "Cell Detection QC export completed"
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