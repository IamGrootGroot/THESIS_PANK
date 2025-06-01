#!/bin/bash

# =============================================================================
# PANK Thesis Project - TRIDENT GeoJSON Import Pipeline
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script automates the import of TRIDENT-generated GeoJSON tissue 
# segmentations into QuPath projects.
# =============================================================================

# =============================================================================
# Default QuPath Configuration
# =============================================================================
# Default QuPath path (can be overridden with -q option)
# Update this path to match your most common QuPath installation
DEFAULT_QUPATH_PATH="${QUPATH_PATH:-/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6.0/qupath/build/dist/QuPath/bin/QuPath}"

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -t, --trident PATH    Path to TRIDENT output base directory"
    echo "  -p, --project PATH    Path to QuPath project directory or .qpproj file"
    echo "  -q, --qupath PATH     Path to QuPath executable (optional)"
    echo "  -a, --all             Process all QuPath projects in current directory"
    echo "  -s, --test            Process only the test project (QuPath_MP_PDAC5)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -t ./trident_output/contours_geoJSON -s                    # Test project only"
    echo "  $0 -t ./trident_output/contours_geoJSON -p QuPath_MP_PDAC100  # Project directory"
    echo "  $0 -t ./trident_output/contours_geoJSON -p QuPath_MP_PDAC100/project.qpproj  # Project file"
    echo "  $0 -t ./trident_output/contours_geoJSON -a                    # All projects"
    echo "  $0 -t ./trident_output -q /path/to/QuPath -p project_dir      # Custom QuPath"
    echo
    echo "Note: TRIDENT output directory is required."
    echo "      Project path can be either directory (auto-appends /project.qpproj) or .qpproj file."
    echo "      If QuPath path not specified, uses default from script configuration."
    exit 1
}

# =============================================================================
# Logging Configuration
# =============================================================================
# Create timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/trident_import_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/trident_import_${TIMESTAMP}_error.log"
QUPATH_LOG="${LOG_DIR}/qupath_trident_${TIMESTAMP}.log"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# =============================================================================
# Script Path Configuration
# =============================================================================
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROOVY_SCRIPT="$SCRIPT_DIR/00a_import_trident_geojson.groovy"

# Validate Groovy script exists
if [ ! -f "$GROOVY_SCRIPT" ]; then
    echo "ERROR: Groovy script not found at $GROOVY_SCRIPT"
    exit 1
fi

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

# Function to log warning messages with timestamp and terminal output
warn_log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;33mWARNING: $1\033[0m" | tee -a "$LOG_FILE"
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
TRIDENT_DIR=""
PROJECT_PATH=""
CUSTOM_QUPATH_PATH=""
PROCESS_ALL=false
TEST_ONLY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--trident)
            TRIDENT_DIR="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        -q|--qupath)
            CUSTOM_QUPATH_PATH="$2"
            shift 2
            ;;
        -a|--all)
            PROCESS_ALL=true
            shift
            ;;
        -s|--test)
            TEST_ONLY=true
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
if [ -z "$TRIDENT_DIR" ]; then
    error_log "Missing required TRIDENT output directory"
    show_help
fi

# Check that only one processing mode is selected
mode_count=0
[ "$PROCESS_ALL" = true ] && ((mode_count++))
[ "$TEST_ONLY" = true ] && ((mode_count++))
[ -n "$PROJECT_PATH" ] && ((mode_count++))

if [ "$mode_count" -ne 1 ]; then
    error_log "Please specify exactly one processing mode: --all, --test, or --project"
    show_help
fi

# =============================================================================
# Project Path Normalization
# =============================================================================
# If PROJECT_PATH is provided, check if it's a directory or file
if [ -n "$PROJECT_PATH" ]; then
    if [ -d "$PROJECT_PATH" ]; then
        # If it's a directory, append /project.qpproj
        PROJECT_PATH="${PROJECT_PATH%/}/project.qpproj"
        log "Project directory provided, using: $PROJECT_PATH"
    elif [[ "$PROJECT_PATH" == *.qpproj ]]; then
        # If it already ends with .qpproj, use as is
        log "Project file provided: $PROJECT_PATH"
    else
        # If it's neither a directory nor ends with .qpproj, assume it's a directory without trailing slash
        PROJECT_PATH="${PROJECT_PATH}/project.qpproj"
        log "Assuming project directory, using: $PROJECT_PATH"
    fi
fi

# =============================================================================
# Pipeline Initialization
# =============================================================================
# Clear screen and show welcome message
clear
echo -e "\033[1;35m===============================================\033[0m"
echo -e "\033[1;35m     PANK Thesis - TRIDENT GeoJSON Import     \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

# Log start of pipeline with configuration details
log "Starting TRIDENT GeoJSON import pipeline"
log "TRIDENT output directory: $TRIDENT_DIR"
echo

# =============================================================================
# Input Validation
# =============================================================================
log "Validating input directories..."

# Check TRIDENT output directory
if [ ! -d "$TRIDENT_DIR" ]; then
    error_log "TRIDENT output directory not found: $TRIDENT_DIR"
    exit 1
fi

# Convert to absolute path for QuPath
TRIDENT_DIR=$(realpath "$TRIDENT_DIR")
log "Using absolute TRIDENT path: $TRIDENT_DIR"

# =============================================================================
# QuPath Path Configuration
# =============================================================================
# Use custom QuPath path if provided, otherwise use default
if [ -n "$CUSTOM_QUPATH_PATH" ]; then
    QUPATH_PATH="$CUSTOM_QUPATH_PATH"
    log "Using custom QuPath path: $QUPATH_PATH"
else
    # Use default QuPath path from script configuration
    QUPATH_PATH="$DEFAULT_QUPATH_PATH"
    log "Using default QuPath path: $QUPATH_PATH"
fi

# Validate QuPath installation
if [ ! -f "$QUPATH_PATH" ]; then
    error_log "QuPath not found at $QUPATH_PATH"
    if [ -n "$CUSTOM_QUPATH_PATH" ]; then
        error_log "Custom QuPath path is invalid"
    else
        error_log "Please set the correct path in the script or use -q option"
    fi
    exit 1
fi

log "QuPath executable validated: $QUPATH_PATH"

# =============================================================================
# Function to Process a Single Project
# =============================================================================
process_project() {
    local project_file="$1"
    local project_name=$(basename "$(dirname "$project_file")")
    
    log "Processing project: $project_name"
    log "Project file: $project_file"
    
    if [ ! -f "$project_file" ]; then
        error_log "Project file not found: $project_file"
        return 1
    fi
    
    # Run the GeoJSON import script
    if "$QUPATH_PATH" script --project="$project_file" \
                    --args="$TRIDENT_DIR" \
                    "$GROOVY_SCRIPT" \
                    >> "$QUPATH_LOG" 2>&1; then
        log "Successfully imported TRIDENT GeoJSON for project: $project_name"
        return 0
    else
        error_log "Failed to import TRIDENT GeoJSON for project: $project_name"
        return 1
    fi
}

# =============================================================================
# Main Processing Logic
# =============================================================================
successful_projects=0
failed_projects=0

if [ "$TEST_ONLY" = true ]; then
    # Process only the test project
    log "Processing test project only (QuPath_MP_PDAC5)"
    test_project="QuPath_MP_PDAC5/project.qpproj"
    
    if process_project "$test_project"; then
        ((successful_projects++))
    else
        ((failed_projects++))
    fi
    
elif [ -n "$PROJECT_PATH" ]; then
    # Process single specified project
    log "Processing single project: $PROJECT_PATH"
    
    if process_project "$PROJECT_PATH"; then
        ((successful_projects++))
    else
        ((failed_projects++))
    fi
    
elif [ "$PROCESS_ALL" = true ]; then
    # Process all QuPath projects in current directory
    log "Processing all QuPath projects in current directory"
    
    # Find all QuPath project files
    project_files=(QuPath_MP_PDAC*/project.qpproj)
    
    if [ ${#project_files[@]} -eq 0 ] || [ ! -f "${project_files[0]}" ]; then
        error_log "No QuPath project files found in current directory"
        exit 1
    fi
    
    total_projects=${#project_files[@]}
    log "Found $total_projects QuPath projects to process"
    
    current_project=0
    for project_file in "${project_files[@]}"; do
        ((current_project++))
        progress_bar "$current_project" "$total_projects"
        echo # New line after progress bar
        
        if process_project "$project_file"; then
            ((successful_projects++))
        else
            ((failed_projects++))
        fi
        
        # Allow QuPath to fully save changes between projects
        sleep 2
    done
fi

# =============================================================================
# Pipeline Completion
# =============================================================================
echo
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           Pipeline Execution Complete         \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "TRIDENT GeoJSON import pipeline completed"
log "Successfully processed: $successful_projects projects"
log "Failed to process: $failed_projects projects"
log "Check $LOG_FILE for detailed logs"
log "Check $ERROR_LOG for error logs"
log "QuPath verbose output is in $QUPATH_LOG"

if [ "$failed_projects" -gt 0 ]; then
    exit 1
else
    exit 0
fi 