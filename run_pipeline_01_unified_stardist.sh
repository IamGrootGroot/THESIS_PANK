#!/bin/bash

# =============================================================================
# PANK Thesis Project - Unified StarDist Cell Segmentation Pipeline
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script automatically detects QuPath version and CUDA availability
# to choose between CPU (QuPath 0.6) and GPU (QuPath 0.5.1) processing.
# =============================================================================

# =============================================================================
# QuPath Installation Paths Configuration
# =============================================================================
# QuPath 0.6 (CPU-optimized build with StarDist 0.6.0-rc1)
QUPATH_06_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build_0.6/qupath/build/dist/QuPath/bin/QuPath"
QUPATH_06_DIR="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build_0.6/qupath/build/dist/QuPath"
STARDIST_06_JAR="$QUPATH_06_DIR/lib/app/qupath-extension-stardist-0.6.0-rc1.jar"

# QuPath 0.5.1 (GPU-enabled build)
QUPATH_051_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build/qupath/qupath-app/build/install/QuPath-0.5.1/bin/QuPath-0.5.1"
QUPATH_051_DIR="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build/qupath/qupath-app/build/install/QuPath-0.5.1"

# Model path
MODEL_PATH="/u/trinhvq/Documents/maxencepelloux/HE/THESIS_PANK/models/he_heavy_augment.pb"

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -p, --project PATH    Process specific QuPath project (.qpproj)"
    echo "  -s, --test           Process only the test project (QuPath_MP_PDAC2)"
    echo "  -a, --all            Process all QuPath projects (one at a time)"
    echo "  -m, --mode MODE      Force processing mode: 'cpu', 'gpu', or 'auto' (default: auto)"
    echo "  -q, --qupath PATH    Force specific QuPath executable path"
    echo "  -v, --verbose        Enable verbose logging"
    echo "  -h, --help           Show this help message"
    echo
    echo "Processing Modes:"
    echo "  auto    Automatically detect best configuration (default)"
    echo "  cpu     Force CPU processing with QuPath 0.6"
    echo "  gpu     Force GPU processing with QuPath 0.5.1"
    echo
    echo "Examples:"
    echo "  $0 -s                           # Test project with auto-detection"
    echo "  $0 -p QuPath_MP_PDAC100/project.qpproj -m gpu"
    echo "  $0 -a -m cpu                    # All projects, force CPU"
    echo "  $0 -s -q /custom/path/to/QuPath # Custom QuPath path"
    echo
    echo "Auto-detection Logic:"
    echo "  1. Check CUDA availability with nvidia-smi"
    echo "  2. Detect QuPath version from executable"
    echo "  3. Choose optimal configuration:"
    echo "     - GPU mode: QuPath 0.5.1 + CUDA available"
    echo "     - CPU mode: QuPath 0.6 + optimized for 128-core server"
    exit 1
}

# =============================================================================
# Logging Configuration
# =============================================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/unified_stardist_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/unified_stardist_${TIMESTAMP}_error.log"
QUPATH_LOG="${LOG_DIR}/qupath_unified_${TIMESTAMP}.log"

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
# System Detection Functions
# =============================================================================
check_cuda_availability() {
    verbose_log "Checking CUDA availability..."
    
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
            local gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1)
            log "CUDA available: $gpu_count GPU(s) detected"
            log "GPU info: $gpu_info"
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

detect_qupath_version() {
    local qupath_path="$1"
    verbose_log "Detecting QuPath version for: $qupath_path"
    
    if [ ! -f "$qupath_path" ]; then
        verbose_log "QuPath executable not found: $qupath_path"
        return 1
    fi
    
    # Try to extract version from path or executable
    if [[ "$qupath_path" == *"0.5.1"* ]]; then
        echo "0.5.1"
        return 0
    elif [[ "$qupath_path" == *"0.6"* ]]; then
        echo "0.6"
        return 0
    else
        # Try to run QuPath to get version (may not work in headless mode)
        local version_output=$("$qupath_path" --version 2>/dev/null | head -1)
        if [[ "$version_output" == *"0.5.1"* ]]; then
            echo "0.5.1"
            return 0
        elif [[ "$version_output" == *"0.6"* ]]; then
            echo "0.6"
            return 0
        else
            verbose_log "Could not determine QuPath version from: $qupath_path"
            return 1
        fi
    fi
}

determine_optimal_configuration() {
    verbose_log "Determining optimal processing configuration..."
    
    local cuda_available=false
    local qupath_051_available=false
    local qupath_06_available=false
    
    # Check CUDA availability
    if check_cuda_availability; then
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
    
    # Decision logic
    if [ "$cuda_available" = true ] && [ "$qupath_051_available" = true ]; then
        echo "gpu"
        log "Auto-selected: GPU mode (CUDA + QuPath 0.5.1)"
    elif [ "$qupath_06_available" = true ]; then
        echo "cpu"
        log "Auto-selected: CPU mode (QuPath 0.6 optimized for 128-core server)"
    elif [ "$qupath_051_available" = true ]; then
        echo "gpu"
        warn_log "Auto-selected: GPU mode (QuPath 0.5.1) but CUDA may not be available"
    else
        error_log "No suitable QuPath installation found"
        return 1
    fi
}

setup_processing_environment() {
    local mode="$1"
    
    case "$mode" in
        "gpu")
            SELECTED_QUPATH_PATH="$QUPATH_051_PATH"
            SELECTED_QUPATH_DIR="$QUPATH_051_DIR"
            PROCESSING_MODE="GPU"
            STARDIST_SCRIPT="01_he_stardist_cell_segmentation_gpu.groovy"
            log "Configuration: GPU mode with QuPath 0.5.1"
            ;;
        "cpu")
            SELECTED_QUPATH_PATH="$QUPATH_06_PATH"
            SELECTED_QUPATH_DIR="$QUPATH_06_DIR"
            PROCESSING_MODE="CPU"
            STARDIST_SCRIPT="01_he_stardist_cell_segmentation_cpu.groovy"
            log "Configuration: CPU mode with QuPath 0.6 (128-core optimized)"
            ;;
        *)
            error_log "Invalid processing mode: $mode"
            return 1
            ;;
    esac
    
    # Validate selected QuPath
    if [ ! -f "$SELECTED_QUPATH_PATH" ] || [ ! -x "$SELECTED_QUPATH_PATH" ]; then
        error_log "Selected QuPath not found or not executable: $SELECTED_QUPATH_PATH"
        return 1
    fi
    
    # Validate model file
    if [ ! -f "$MODEL_PATH" ]; then
        error_log "Model file not found: $MODEL_PATH"
        return 1
    fi
    
    log "QuPath executable: $SELECTED_QUPATH_PATH"
    log "Processing mode: $PROCESSING_MODE"
    log "Model file: $MODEL_PATH"
    
    return 0
}

# =============================================================================
# Command Line Argument Parsing
# =============================================================================
PROJECT_PATH=""
PROCESS_ALL=false
TEST_ONLY=false
FORCE_MODE="auto"
CUSTOM_QUPATH_PATH=""
VERBOSE=false

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
        -m|--mode)
            FORCE_MODE="$2"
            shift 2
            ;;
        -q|--qupath)
            CUSTOM_QUPATH_PATH="$2"
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

# =============================================================================
# Pipeline Initialization
# =============================================================================
clear
echo -e "\033[1;35m===============================================\033[0m"
echo -e "\033[1;35m     PANK Thesis - Unified StarDist Pipeline   \033[0m"
echo -e "\033[1;35m     Automatic CPU/GPU Detection & Selection   \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

log "Starting unified StarDist cell segmentation pipeline"
log "Force mode: $FORCE_MODE"
log "Verbose logging: $VERBOSE"

# Determine processing configuration
if [ "$FORCE_MODE" = "auto" ]; then
    SELECTED_MODE=$(determine_optimal_configuration)
    if [ $? -ne 0 ]; then
        error_log "Failed to determine optimal configuration"
        exit 1
    fi
else
    SELECTED_MODE="$FORCE_MODE"
    log "Using forced mode: $SELECTED_MODE"
fi

# Handle custom QuPath path
if [ -n "$CUSTOM_QUPATH_PATH" ]; then
    if [ ! -f "$CUSTOM_QUPATH_PATH" ] || [ ! -x "$CUSTOM_QUPATH_PATH" ]; then
        error_log "Custom QuPath path not found or not executable: $CUSTOM_QUPATH_PATH"
        exit 1
    fi
    
    # Override based on detected version
    detected_version=$(detect_qupath_version "$CUSTOM_QUPATH_PATH")
    if [ $? -eq 0 ]; then
        case "$detected_version" in
            "0.5.1")
                QUPATH_051_PATH="$CUSTOM_QUPATH_PATH"
                QUPATH_051_DIR="$(dirname "$(dirname "$CUSTOM_QUPATH_PATH")")"
                ;;
            "0.6")
                QUPATH_06_PATH="$CUSTOM_QUPATH_PATH"
                QUPATH_06_DIR="$(dirname "$(dirname "$CUSTOM_QUPATH_PATH")")"
                ;;
        esac
        log "Using custom QuPath $detected_version: $CUSTOM_QUPATH_PATH"
    else
        warn_log "Could not detect version of custom QuPath, using as-is"
    fi
fi

# Setup processing environment
if ! setup_processing_environment "$SELECTED_MODE"; then
    exit 1
fi

# =============================================================================
# Script Path Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CELL_SEG_SCRIPT_PATH="$SCRIPT_DIR/$STARDIST_SCRIPT"

# Check if we need to create mode-specific scripts
if [ ! -f "$CELL_SEG_SCRIPT_PATH" ]; then
    warn_log "Mode-specific script not found: $STARDIST_SCRIPT"
    warn_log "Using generic script: 01_he_stardist_cell_segmentation_shell_compatible.groovy"
    CELL_SEG_SCRIPT_PATH="$SCRIPT_DIR/01_he_stardist_cell_segmentation_shell_compatible.groovy"
fi

if [ ! -f "$CELL_SEG_SCRIPT_PATH" ]; then
    error_log "StarDist script not found: $CELL_SEG_SCRIPT_PATH"
    exit 1
fi

log "Using StarDist script: $(basename "$CELL_SEG_SCRIPT_PATH")"

# =============================================================================
# Processing Function
# =============================================================================
process_project() {
    local project_file="$1"
    local project_name=$(basename "$(dirname "$project_file")")
    
    log "Processing project: $project_name"
    verbose_log "Project file: $project_file"
    
    if [ ! -f "$project_file" ]; then
        error_log "Project file not found: $project_file"
        return 1
    fi
    
    # Mode-specific setup
    case "$PROCESSING_MODE" in
        "CPU")
            # CPU mode: QuPath 0.6 with StarDist extension setup
            local main_lib_dir="$SELECTED_QUPATH_DIR/lib"
            if [ ! -f "$main_lib_dir/qupath-extension-stardist-0.6.0-rc1.jar" ]; then
                if [ -f "$STARDIST_06_JAR" ]; then
                    cp "$STARDIST_06_JAR" "$main_lib_dir/"
                    verbose_log "Copied StarDist extension to main lib directory"
                fi
            fi
            
            # Run with CPU-optimized settings
            verbose_log "Running StarDist cell segmentation (CPU mode) for $project_name"
            if JAVA_OPTS="-Djava.class.path=$SELECTED_QUPATH_DIR/lib/*:$SELECTED_QUPATH_DIR/lib/app/*" \
               "$SELECTED_QUPATH_PATH" script \
                    --project="$project_file" \
                    "$CELL_SEG_SCRIPT_PATH" \
                    >> "$QUPATH_LOG" 2>&1; then
                log "StarDist segmentation (CPU) completed successfully for $project_name"
                return 0
            else
                error_log "StarDist segmentation (CPU) failed for $project_name"
                return 1
            fi
            ;;
            
        "GPU")
            # GPU mode: QuPath 0.5.1 with GPU acceleration
            verbose_log "Running StarDist cell segmentation (GPU mode) for $project_name"
            if "$SELECTED_QUPATH_PATH" script \
                    --project="$project_file" \
                    "$CELL_SEG_SCRIPT_PATH" \
                    >> "$QUPATH_LOG" 2>&1; then
                log "StarDist segmentation (GPU) completed successfully for $project_name"
                return 0
            else
                error_log "StarDist segmentation (GPU) failed for $project_name"
                return 1
            fi
            ;;
    esac
}

# =============================================================================
# Main Processing Logic
# =============================================================================
successful_projects=0
failed_projects=0
start_time=$(date +%s)

# Determine projects to process
if [ "$TEST_ONLY" = true ]; then
    # Use mode-specific test projects based on QuPath_MP_PDAC2
    case "$PROCESSING_MODE" in
        "GPU")
            project_files=("/u/trinhvq/Documents/maxencepelloux/HE/QuPath_MP_PDAC2_0.5.1/project.qpproj")
            log "Processing GPU test project (QuPath_MP_PDAC2_0.5.1)"
            ;;
        "CPU")
            project_files=("/u/trinhvq/Documents/maxencepelloux/HE/QuPath_MP_PDAC2_0.6.0/project.qpproj")
            log "Processing CPU test project (QuPath_MP_PDAC2_0.6.0)"
            ;;
        *)
            error_log "Unknown processing mode: $PROCESSING_MODE"
            exit 1
            ;;
    esac
elif [ -n "$PROJECT_PATH" ]; then
    project_files=("$PROJECT_PATH")
    log "Processing single project: $PROJECT_PATH"
elif [ "$PROCESS_ALL" = true ]; then
    project_files=(QuPath_MP_PDAC*/project.qpproj)
    log "Processing all QuPath projects"
fi

# Validate project files
if [ ${#project_files[@]} -eq 0 ] || [ ! -f "${project_files[0]}" ]; then
    error_log "No QuPath project files found"
    exit 1
fi

total_projects=${#project_files[@]}
log "Found $total_projects QuPath project(s) to process"

# Process projects
current_project=0
for project_file in "${project_files[@]}"; do
    ((current_project++))
    
    echo "----------------------------------------"
    echo "Processing project $current_project/$total_projects"
    echo "----------------------------------------"
    
    if process_project "$project_file"; then
        ((successful_projects++))
    else
        ((failed_projects++))
    fi
    
    # Allow QuPath to save changes between projects
    sleep 2
done

# =============================================================================
# Pipeline Completion
# =============================================================================
end_time=$(date +%s)
total_time=$((end_time - start_time))

echo
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           Unified Pipeline Complete           \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "Unified StarDist cell segmentation pipeline completed"
log "Processing mode used: $PROCESSING_MODE"
log "Successfully processed: $successful_projects projects"
log "Failed to process: $failed_projects projects"
log "Total time: $((total_time / 60)) minutes"
log "Main log: $LOG_FILE"
log "Error log: $ERROR_LOG"
log "QuPath log: $QUPATH_LOG"

echo
echo "Performance Summary:"
echo "  Processing mode: $PROCESSING_MODE"
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