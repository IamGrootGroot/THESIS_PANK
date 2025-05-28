#!/bin/bash

# =============================================================================
# PANK Thesis Project - Simple StarDist Cell Segmentation Pipeline
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# Simple, reliable script that processes one project at a time.
# Based on Khellaf's working approach.
# =============================================================================

# QuPath Configuration
QUPATH_PATH="${QUPATH_PATH:-/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build/qupath/build/dist/QuPath/bin/QuPath}"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p PROJECT    Process specific QuPath project (.qpproj)"
    echo "  -s            Process only the test project (QuPath_MP_PDAC5)"
    echo "  -a            Process all QuPath projects (one at a time)"
    echo "  -h            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s                           # Test project only"
    echo "  $0 -p QuPath_MP_PDAC100/project.qpproj"
    echo "  $0 -a                           # All projects (sequential)"
    echo ""
    echo "Note: This script processes projects one at a time for reliability."
    exit 1
}

# Logging setup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/simple_stardist_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/simple_stardist_${TIMESTAMP}_error.log"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" "$ERROR_LOG"
}

# Parse arguments
PROJECT_PATH=""
PROCESS_ALL=false
TEST_ONLY=false

while getopts "p:ash" opt; do
    case $opt in
        p) PROJECT_PATH="$OPTARG" ;;
        a) PROCESS_ALL=true ;;
        s) TEST_ONLY=true ;;
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
clear
echo "==============================================="
echo "     PANK Thesis - Simple StarDist Pipeline"
echo "==============================================="
echo

log "Starting simple StarDist cell segmentation pipeline"

# Validate QuPath
if [ ! -f "$QUPATH_PATH" ]; then
    error_log "QuPath not found: $QUPATH_PATH"
    error_log "Please set QUPATH_PATH environment variable"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CELL_SEG_SCRIPT="$SCRIPT_DIR/01_he_stardist_cell_segmentation_shell_compatible.groovy"

if [ ! -f "$CELL_SEG_SCRIPT" ]; then
    error_log "StarDist script not found: $CELL_SEG_SCRIPT"
    exit 1
fi

# Check model file
MODEL_PATH="/u/trinhvq/Documents/maxencepelloux/HE/THESIS_PANK/models/he_heavy_augment.pb"
if [ ! -f "$MODEL_PATH" ]; then
    error_log "Model file not found: $MODEL_PATH"
    exit 1
fi

log "Setup validation completed successfully"
log "Model file: $MODEL_PATH"

# Function to process a single project
process_project() {
    local project_file="$1"
    local project_name=$(basename "$(dirname "$project_file")")
    
    log "Processing project: $project_name"
    log "Project file: $project_file"
    
    if [ ! -f "$project_file" ]; then
        error_log "Project file not found: $project_file"
        return 1
    fi
    
    # Ensure StarDist extension is available in main lib directory for headless mode
    QUPATH_DIR="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build_0.6/qupath/build/dist/QuPath"
    STARDIST_JAR="$QUPATH_DIR/lib/app/qupath-extension-stardist-0.6.0-rc1.jar"
    MAIN_LIB_DIR="$QUPATH_DIR/lib"
    
    # Copy StarDist to main lib directory if not already there
    if [ ! -f "$MAIN_LIB_DIR/qupath-extension-stardist-0.6.0-rc1.jar" ]; then
        cp "$STARDIST_JAR" "$MAIN_LIB_DIR/"
        log "Copied StarDist extension to main lib directory for headless loading"
    fi
    
    # Run StarDist cell segmentation with forced extension loading
    log "Running StarDist cell segmentation for $project_name"
    if JAVA_OPTS="-Djava.class.path=$QUPATH_DIR/lib/*:$QUPATH_DIR/lib/app/*" \
       "$QUPATH_PATH" script \
            --project="$project_file" \
            "$CELL_SEG_SCRIPT" \
            >> "$LOG_FILE" 2>&1; then
        log "StarDist segmentation completed successfully for $project_name"
        
        # Allow QuPath to save changes
        sleep 2
        return 0
    else
        error_log "StarDist segmentation failed for $project_name"
        return 1
    fi
}

# Main processing
successful_projects=0
failed_projects=0
start_time=$(date +%s)

if [ "$TEST_ONLY" = true ]; then
    # Process test project only
    log "Processing test project only (QuPath_MP_PDAC5)"
    project_files=("QuPath_MP_PDAC5/project.qpproj")
    
elif [ -n "$PROJECT_PATH" ]; then
    # Process single project
    log "Processing single project: $PROJECT_PATH"
    project_files=("$PROJECT_PATH")
    
elif [ "$PROCESS_ALL" = true ]; then
    # Process all projects
    log "Processing all QuPath projects"
    project_files=(QuPath_MP_PDAC*/project.qpproj)
fi

# Validate project files
if [ ${#project_files[@]} -eq 0 ] || [ ! -f "${project_files[0]}" ]; then
    error_log "No QuPath project files found"
    exit 1
fi

total_projects=${#project_files[@]}
log "Found $total_projects QuPath project(s) to process"

# Process projects one by one
current_project=0
for project_file in "${project_files[@]}"; do
    ((current_project++))
    
    echo "----------------------------------------"
    echo "Processing project $current_project/$total_projects"
    echo "----------------------------------------"
    
    # Process project
    if process_project "$project_file"; then
        ((successful_projects++))
    else
        ((failed_projects++))
    fi
done

# Summary
end_time=$(date +%s)
total_time=$((end_time - start_time))

echo
echo "==============================================="
echo "           Simple Pipeline Complete"
echo "==============================================="
log "Simple StarDist cell segmentation pipeline completed"
log "Successfully processed: $successful_projects projects"
log "Failed to process: $failed_projects projects"
log "Total time: $((total_time / 60)) minutes"
log "Main log: $LOG_FILE"
log "Error log: $ERROR_LOG"
echo
echo "Performance Summary:"
echo "  Successfully processed: $successful_projects/$total_projects projects"
echo "  Failed: $failed_projects projects"
echo "  Total processing time: $((total_time / 60)) minutes"
if [ "$total_projects" -gt 0 ]; then
    echo "  Average time per project: $((total_time / total_projects)) seconds"
fi

if [ "$failed_projects" -gt 0 ]; then
    exit 1
else
    exit 0
fi 