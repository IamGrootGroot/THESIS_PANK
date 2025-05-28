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
QUPATH_06_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6.0/qupath/build/dist/QuPath/bin/QuPath"
QUPATH_06_DIR="/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6.0/qupath/build/dist/QuPath"
STARDIST_06_JAR="$QUPATH_06_DIR/lib/app/qupath-extension-stardist-0.6.0-rc1.jar"

# QuPath 0.5.1 (GPU-enabled build)
QUPATH_051_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build_0.5.1/qupath/build/dist/QuPath/bin/QuPath"
QUPATH_051_DIR="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build_0.5.1/qupath/build/dist/QuPath"

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
    echo "  -q, --qupath PATH    Custom QuPath executable path (with compatibility checks)"
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
    echo "  $0 -s -q /custom/path/to/QuPath # Custom QuPath with compatibility check"
    echo "  $0 -s -q /path/to/QuPath -m gpu # Custom QuPath forced to GPU mode"
    echo
    echo "Compatibility Checks:"
    echo "  - Verifies QuPath executable exists and is executable"
    echo "  - Detects QuPath version (0.5.1 vs 0.6)"
    echo "  - Checks CUDA compatibility for GPU mode"
    echo "  - Validates StarDist extension availability"
    echo "  - Ensures mode compatibility with QuPath version"
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

check_stardist_extension() {
    local qupath_path="$1"
    local qupath_version="$2"
    
    verbose_log "Checking StarDist extension availability for QuPath $qupath_version"
    
    local qupath_base_dir=$(dirname "$(dirname "$qupath_path")")
    local stardist_found=false
    
    # Version-specific StarDist extension checks
    case "$qupath_version" in
        "0.5.1")
            # For QuPath 0.5.1, look for StarDist in lib directories
            local search_dirs=(
                "$qupath_base_dir/lib"
                "$qupath_base_dir/lib/app"
                "$qupath_base_dir/extensions"
            )
            ;;
        "0.6")
            # For QuPath 0.6, look for StarDist 0.6.0-rc1
            local search_dirs=(
                "$qupath_base_dir/lib"
                "$qupath_base_dir/lib/app"
                "$qupath_base_dir/extensions"
            )
            ;;
        *)
            warn_log "Unknown QuPath version for StarDist check: $qupath_version"
            return 1
            ;;
    esac
    
    # Search for StarDist JAR files
    for search_dir in "${search_dirs[@]}"; do
        if [ -d "$search_dir" ]; then
            if find "$search_dir" -name "*stardist*.jar" 2>/dev/null | grep -q .; then
                local stardist_jar=$(find "$search_dir" -name "*stardist*.jar" | head -1)
                verbose_log "Found StarDist extension: $stardist_jar"
                stardist_found=true
                break
            fi
        fi
    done
    
    if [ "$stardist_found" = false ]; then
        error_log "StarDist extension not found for QuPath $qupath_version"
        error_log "Please install StarDist extension or use a QuPath build with StarDist included"
        return 1
    fi
    
    verbose_log "StarDist extension validation passed"
    return 0
}

validate_mode_compatibility() {
    local qupath_version="$1"
    local requested_mode="$2"
    local cuda_available="$3"
    
    verbose_log "Validating mode compatibility: QuPath $qupath_version, mode $requested_mode, CUDA $cuda_available"
    
    case "$requested_mode" in
        "gpu")
            if [ "$qupath_version" != "0.5.1" ]; then
                error_log "GPU mode requires QuPath 0.5.1, but detected version: $qupath_version"
                error_log "Use QuPath 0.5.1 for GPU acceleration or switch to CPU mode"
                return 1
            fi
            
            if [ "$cuda_available" != "true" ]; then
                warn_log "GPU mode requested but CUDA not available"
                warn_log "Processing may fall back to CPU within QuPath"
            fi
            ;;
        "cpu")
            if [ "$qupath_version" != "0.6" ]; then
                warn_log "CPU mode optimized for QuPath 0.6, but detected version: $qupath_version"
                warn_log "Processing will continue but may not be optimally configured"
            fi
            ;;
        "auto")
            # Auto mode is always compatible, but we'll provide recommendations
            if [ "$qupath_version" = "0.5.1" ] && [ "$cuda_available" = "true" ]; then
                verbose_log "Auto mode: QuPath 0.5.1 + CUDA detected, will use GPU mode"
            elif [ "$qupath_version" = "0.6" ]; then
                verbose_log "Auto mode: QuPath 0.6 detected, will use CPU mode"
            else
                verbose_log "Auto mode: Using detected configuration"
            fi
            ;;
        *)
            error_log "Invalid processing mode: $requested_mode"
            return 1
            ;;
    esac
    
    verbose_log "Mode compatibility validation passed"
    return 0
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
    
    # Step 3: StarDist extension check
    if ! check_stardist_extension "$qupath_path" "$detected_version"; then
        return 1
    fi
    
    # Step 4: Mode compatibility validation
    if ! validate_mode_compatibility "$detected_version" "$requested_mode" "$cuda_available"; then
        return 1
    fi
    
    # Step 5: Set global variables for later use
    DETECTED_QUPATH_VERSION="$detected_version"
    VALIDATED_QUPATH_PATH="$qupath_path"
    
    log "✅ QuPath validation completed successfully"
    log "   Path: $qupath_path"
    log "   Version: $detected_version"
    log "   Mode: $requested_mode"
    log "   CUDA: $cuda_available"
    
    return 0
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
echo -e "\033[1;35m     With Comprehensive Compatibility Checks   \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

log "Starting unified StarDist cell segmentation pipeline"
log "Force mode: $FORCE_MODE"
log "Custom QuPath: ${CUSTOM_QUPATH_PATH:-'Not specified'}"
log "Verbose logging: $VERBOSE"

# Check CUDA availability first
CUDA_AVAILABLE=false
if check_cuda_availability; then
    CUDA_AVAILABLE=true
fi

# Handle custom QuPath path with comprehensive validation
if [ -n "$CUSTOM_QUPATH_PATH" ]; then
    log "Validating custom QuPath installation..."
    
    if ! comprehensive_qupath_validation "$CUSTOM_QUPATH_PATH" "$FORCE_MODE" "$CUDA_AVAILABLE"; then
        error_log "Custom QuPath validation failed"
        exit 1
    fi
    
    # Override the detected configuration with validated custom path
    case "$DETECTED_QUPATH_VERSION" in
        "0.5.1")
            QUPATH_051_PATH="$CUSTOM_QUPATH_PATH"
            QUPATH_051_DIR="$(dirname "$(dirname "$CUSTOM_QUPATH_PATH")")"
            log "Using validated custom QuPath 0.5.1: $CUSTOM_QUPATH_PATH"
            ;;
        "0.6")
            QUPATH_06_PATH="$CUSTOM_QUPATH_PATH"
            QUPATH_06_DIR="$(dirname "$(dirname "$CUSTOM_QUPATH_PATH")")"
            log "Using validated custom QuPath 0.6: $CUSTOM_QUPATH_PATH"
            ;;
    esac
    
    # If mode is auto, determine based on validated QuPath version
    if [ "$FORCE_MODE" = "auto" ]; then
        if [ "$DETECTED_QUPATH_VERSION" = "0.5.1" ] && [ "$CUDA_AVAILABLE" = true ]; then
            SELECTED_MODE="gpu"
            log "Auto-selected GPU mode based on custom QuPath 0.5.1 + CUDA"
        elif [ "$DETECTED_QUPATH_VERSION" = "0.6" ]; then
            SELECTED_MODE="cpu"
            log "Auto-selected CPU mode based on custom QuPath 0.6"
        else
            SELECTED_MODE="gpu"
            warn_log "Auto-selected GPU mode with custom QuPath (CUDA may not be optimal)"
        fi
    else
        SELECTED_MODE="$FORCE_MODE"
        log "Using forced mode: $SELECTED_MODE with validated custom QuPath"
    fi
else
    # Original auto-detection logic for default paths
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
            # GPU mode: QuPath 0.5.1 with GPU acceleration and StarDist extension setup
            local main_lib_dir="$SELECTED_QUPATH_DIR/lib"
            local stardist_051_jar="$SELECTED_QUPATH_DIR/lib/app/qupath-extension-stardist-0.5.0.jar"
            
            # Copy StarDist extension to main lib directory for headless loading
            if [ ! -f "$main_lib_dir/qupath-extension-stardist-0.5.0.jar" ]; then
                if [ -f "$stardist_051_jar" ]; then
                    cp "$stardist_051_jar" "$main_lib_dir/"
                    verbose_log "Copied StarDist extension to main lib directory for GPU mode"
                else
                    error_log "StarDist extension not found for GPU mode: $stardist_051_jar"
                    return 1
                fi
            fi
            
            # Run with GPU-accelerated settings and explicit classpath
            verbose_log "Running StarDist cell segmentation (GPU mode) for $project_name"
            if JAVA_OPTS="-Djava.class.path=$SELECTED_QUPATH_DIR/lib/*:$SELECTED_QUPATH_DIR/lib/app/*" \
               "$SELECTED_QUPATH_PATH" script \
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