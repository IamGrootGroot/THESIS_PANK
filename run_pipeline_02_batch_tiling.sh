#!/bin/bash

# =============================================================================
# PANK Thesis Project - Batch Tile Extraction Pipeline (Step 02)
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script automates tile extraction across multiple QuPath projects
# after StarDist cell segmentation has been completed.
# =============================================================================

# QuPath Configuration
STARDIST_JAR="/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6.0/qupath/build/dist/QuPath/lib/app/qupath-extension-stardist-0.6.0-rc1.jar"
QUPATH_CLASSPATH="$STARDIST_JAR:/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6.0/qupath/build/dist/QuPath/lib/app/*"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p PROJECT    Process specific QuPath project (.qpproj)"
    echo "  -a            Process all QuPath projects in current directory"
    echo "  -s            Process only the test project (QuPath_MP_PDAC5)"
    echo "  -r NUM        Resume processing from project number NUM"
    echo "  -h            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s                           # Test project only"
    echo "  $0 -p QuPath_MP_PDAC100/project.qpproj"
    echo "  $0 -a                           # All projects"
    echo "  $0 -a -r 3                      # Resume from 3rd project"
    echo ""
    echo "Note: This script only performs tile extraction (Step 02)."
    echo "      Run run_pipeline_01_batch_stardist.sh first for cell segmentation."
    exit 1
}

# Logging setup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/pipeline_02_tiling_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/pipeline_02_tiling_${TIMESTAMP}_error.log"
QUPATH_LOG="${LOG_DIR}/qupath_02_tiling_${TIMESTAMP}.log"

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
RESUME_FROM=0

while getopts "p:asr:h" opt; do
    case $opt in
        p) PROJECT_PATH="$OPTARG" ;;
        a) PROCESS_ALL=true ;;
        s) TEST_ONLY=true ;;
        r) RESUME_FROM="$OPTARG" ;;
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
echo "     PANK Thesis - Pipeline Step 02"
echo "     Tile Extraction (224x224 patches)"
echo "==============================================="
echo

log "Starting tile extraction pipeline (Step 02)"

# Validate setup
if [ ! -f "02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy" ]; then
    error_log "Tile extraction script not found: 02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy"
    exit 1
fi

log "Setup validation completed successfully"

# Function to process a single project
process_project() {
    local project_file="$1"
    local project_name=$(basename "$(dirname "$project_file")")
    
    log "Processing project: $project_name"
    
    if [ ! -f "$project_file" ]; then
        error_log "Project file not found: $project_file"
        return 1
    fi
    
    # Tile extraction
    log "Running tile extraction for $project_name"
    if java -cp "$QUPATH_CLASSPATH" qupath.QuPath script \
                --project="$project_file" \
                02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy \
                >> "$QUPATH_LOG" 2>&1; then
        log "Tile extraction completed for $project_name"
    else
        error_log "Tile extraction failed for $project_name"
        return 1
    fi
    
    # Wait for QuPath to save
    log "Waiting for project save..."
    sleep 5
    
    log "Successfully completed tile extraction for project: $project_name"
    return 0
}

# Main processing
successful_projects=0
failed_projects=0
start_time=$(date +%s)

if [ "$TEST_ONLY" = true ]; then
    # Process test project only
    log "Processing test project only (QuPath_MP_PDAC5)"
    if process_project "QuPath_MP_PDAC5/project.qpproj"; then
        ((successful_projects++))
    else
        ((failed_projects++))
    fi
    
elif [ -n "$PROJECT_PATH" ]; then
    # Process single project
    log "Processing single project: $PROJECT_PATH"
    if process_project "$PROJECT_PATH"; then
        ((successful_projects++))
    else
        ((failed_projects++))
    fi
    
elif [ "$PROCESS_ALL" = true ]; then
    # Process all projects
    log "Processing all QuPath projects"
    
    project_files=(QuPath_MP_PDAC*/project.qpproj)
    
    if [ ${#project_files[@]} -eq 0 ] || [ ! -f "${project_files[0]}" ]; then
        error_log "No QuPath project files found"
        exit 1
    fi
    
    total_projects=${#project_files[@]}
    log "Found $total_projects QuPath projects to process"
    
    if [ "$RESUME_FROM" -gt 0 ]; then
        log "Resuming from project number: $RESUME_FROM"
    fi
    
    current_project=0
    for project_file in "${project_files[@]}"; do
        ((current_project++))
        
        # Skip if resuming
        if [ "$current_project" -lt "$RESUME_FROM" ]; then
            continue
        fi
        
        echo "Progress: $current_project/$total_projects"
        
        if process_project "$project_file"; then
            ((successful_projects++))
        else
            ((failed_projects++))
        fi
        
        # Time estimate
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        if [ "$((successful_projects + failed_projects))" -gt 0 ]; then
            avg_time=$((elapsed / (successful_projects + failed_projects)))
            remaining=$((total_projects - current_project))
            estimated=$((avg_time * remaining))
            log "Estimated time remaining: $((estimated / 3600))h $((estimated % 3600 / 60))m"
        fi
        
        sleep 5
    done
fi

# Summary
end_time=$(date +%s)
total_time=$((end_time - start_time))

echo
echo "==============================================="
echo "           Pipeline Step 02 Complete"
echo "==============================================="
log "Tile extraction pipeline completed"
log "Total time: $((total_time / 3600))h $((total_time % 3600 / 60))m $((total_time % 60))s"
log "Successfully processed: $successful_projects projects"
log "Failed to process: $failed_projects projects"
log "Logs: $LOG_FILE, $ERROR_LOG, $QUPATH_LOG"
echo
echo "Next step: Run run_pipeline_03.sh for feature extraction"

if [ "$failed_projects" -gt 0 ]; then
    exit 1
else
    exit 0
fi 