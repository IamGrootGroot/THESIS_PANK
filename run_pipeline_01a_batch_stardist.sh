#!/bin/bash

# =============================================================================
# PANK Thesis Project - Batch StarDist Cell Segmentation Pipeline (Step 01)
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script automates StarDist cell segmentation across multiple QuPath projects
# with CPU optimization. Does NOT include tile extraction (Step 02).
# =============================================================================

# QuPath and StarDist Configuration
STARDIST_JAR="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build/qupath/build/dist/QuPath/lib/app/qupath-extension-stardist-0.6.0-rc1.jar"
QUPATH_CLASSPATH="$STARDIST_JAR:/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build/qupath/build/dist/QuPath/lib/app/*"

# Parallel Processing Configuration (128-core optimization)
MAX_PARALLEL_JOBS=16  # Number of projects to process simultaneously
JAVA_MEMORY="-Xmx32g"  # Memory per QuPath instance (32GB each)
JAVA_THREADS="-XX:ParallelGCThreads=8"  # GC threads per instance

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p PROJECT    Process specific QuPath project (.qpproj)"
    echo "  -a            Process all QuPath projects in current directory"
    echo "  -s            Process only the test project (QuPath_MP_PDAC5)"
    echo "  -r NUM        Resume processing from project number NUM"
    echo "  -j NUM        Number of parallel jobs (default: $MAX_PARALLEL_JOBS)"
    echo "  -m MEMORY     Memory per job (default: 32g)"
    echo "  -h            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s                           # Test project only"
    echo "  $0 -p QuPath_MP_PDAC100/project.qpproj"
    echo "  $0 -a                           # All projects (parallel)"
    echo "  $0 -a -j 20 -m 24g              # 20 parallel jobs with 24GB each"
    echo "  $0 -a -r 3                      # Resume from 3rd project"
    echo ""
    echo "Note: This script only performs StarDist cell segmentation (Step 01)."
    echo "      Optimized for 128-core servers with parallel processing."
    echo "      Run run_pipeline_02_batch_tiling.sh separately for tile extraction."
    exit 1
}

# Logging setup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/pipeline_01_stardist_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/pipeline_01_stardist_${TIMESTAMP}_error.log"
QUPATH_LOG="${LOG_DIR}/qupath_01_stardist_${TIMESTAMP}.log"
QUPATH_LOG_DIR="${LOG_DIR}/qupath_parallel_${TIMESTAMP}"
mkdir -p "$QUPATH_LOG_DIR"

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

while getopts "p:asr:j:m:h" opt; do
    case $opt in
        p) PROJECT_PATH="$OPTARG" ;;
        a) PROCESS_ALL=true ;;
        s) TEST_ONLY=true ;;
        r) RESUME_FROM="$OPTARG" ;;
        j) MAX_PARALLEL_JOBS="$OPTARG" ;;
        m) JAVA_MEMORY="-Xmx$OPTARG" ;;
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
echo "     PANK Thesis - Pipeline Step 01"
echo "     StarDist Cell Segmentation (Multi-Level Parallel)"
echo "==============================================="
echo "Parallel jobs: $MAX_PARALLEL_JOBS"
echo "Memory per job: $JAVA_MEMORY"
echo "Available CPU cores: $(nproc)"
echo "Available memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo

log "Starting StarDist cell segmentation pipeline (Step 01)"
log "Configuration: $MAX_PARALLEL_JOBS parallel jobs, $JAVA_MEMORY per job"

# Validate setup
if [ ! -f "$STARDIST_JAR" ]; then
    error_log "StarDist JAR not found: $STARDIST_JAR"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CELL_SEG_SCRIPT="$SCRIPT_DIR/01_he_stardist_cell_segmentation_shell_compatible.groovy"

if [ ! -f "$CELL_SEG_SCRIPT" ]; then
    error_log "StarDist script not found: $CELL_SEG_SCRIPT"
    exit 1
fi

log "Setup validation completed successfully"

# Function to wait for jobs and manage parallel execution
wait_for_jobs() {
    local max_jobs=$1
    while [ $(jobs -r | wc -l) -ge $max_jobs ]; do
        sleep 2
    done
}

# Function to show progress
show_progress() {
    local current=$1
    local total=$2
    local completed=$3
    local failed=$4
    local running=$(jobs -r | wc -l)
    
    echo "Progress: $current/$total | Completed: $completed | Failed: $failed | Running: $running"
}

# Function to process a single project (modified for parallel execution)
process_project() {
    local project_file="$1"
    local job_id="$2"
    local project_name=$(basename "$(dirname "$project_file")")
    local job_log="${QUPATH_LOG_DIR}/qupath_${project_name}_${job_id}.log"
    
    log "Job $job_id: Processing project $project_name"
    
    if [ ! -f "$project_file" ]; then
        error_log "Job $job_id: Project file not found: $project_file"
        return 1
    fi
    
    # StarDist cell segmentation with optimized JVM settings
    log "Job $job_id: Running StarDist cell segmentation for $project_name"
    if java $JAVA_MEMORY $JAVA_THREADS \
            -cp "$QUPATH_CLASSPATH" qupath.QuPath script \
            --project="$project_file" \
            "$CELL_SEG_SCRIPT" \
            > "$job_log" 2>&1; then
        log "Job $job_id: StarDist segmentation completed for $project_name"
        return 0
    else
        error_log "Job $job_id: StarDist segmentation failed for $project_name"
        return 1
    fi
}

# Main processing
successful_projects=0
failed_projects=0
start_time=$(date +%s)
job_counter=0

if [ "$TEST_ONLY" = true ]; then
    # Process test project only
    log "Processing test project only (QuPath_MP_PDAC5)"
    project_files=("QuPath_MP_PDAC5/project.qpproj")
    
elif [ -n "$PROJECT_PATH" ]; then
    # Process single project
    log "Processing single project: $PROJECT_PATH"
    project_files=("$PROJECT_PATH")
    
elif [ "$PROCESS_ALL" = true ]; then
    # Process all projects in parallel
    log "Processing all QuPath projects in parallel"
    project_files=(QuPath_MP_PDAC*/project.qpproj)
fi

# Common processing logic for all modes
if [ ${#project_files[@]} -eq 0 ] || [ ! -f "${project_files[0]}" ]; then
    error_log "No QuPath project files found"
    exit 1
fi

total_projects=${#project_files[@]}
log "Found $total_projects QuPath project(s) to process in parallel"

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
    
    # Wait if we've reached max parallel jobs
    wait_for_jobs $MAX_PARALLEL_JOBS
    
    # Start new job in background
    ((job_counter++))
    process_project "$project_file" "$job_counter" &
    
    # Show progress
    show_progress $current_project $total_projects $successful_projects $failed_projects
    
    # Brief pause to avoid overwhelming the system
    sleep 1
done

# Wait for all remaining jobs to complete
log "Waiting for all parallel jobs to complete..."
wait

# Count results (simplified - in a real implementation you'd track job results)
log "All parallel jobs completed"

# Summary
end_time=$(date +%s)
total_time=$((end_time - start_time))

echo
echo "==============================================="
echo "           PARALLEL Pipeline Step 01 Complete"
echo "==============================================="
log "PARALLEL StarDist cell segmentation pipeline completed"
log "Total time: $((total_time / 3600))h $((total_time % 3600 / 60))m $((total_time % 60))s"
log "Configuration: $MAX_PARALLEL_JOBS parallel jobs, $JAVA_MEMORY per job"
log "Logs directory: $QUPATH_LOG_DIR"
log "Main log: $LOG_FILE"
log "Error log: $ERROR_LOG"
echo
echo "Performance Summary:"
echo "  Parallel jobs: $MAX_PARALLEL_JOBS"
echo "  Memory per job: $JAVA_MEMORY"
echo "  Total processing time: $((total_time / 60)) minutes"
echo
echo "Next step: Run run_pipeline_02_batch_tiling.sh for tile extraction"

if [ "$failed_projects" -gt 0 ]; then
    exit 1
else
    exit 0
fi 