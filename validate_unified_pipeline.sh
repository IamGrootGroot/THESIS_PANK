#!/bin/bash

# =============================================================================
# PANK Thesis Project - Unified Pipeline Test Script
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script tests the unified pipeline configuration detection without
# actually running the full pipeline. Now includes custom QuPath testing.
# =============================================================================

set -euo pipefail

# Configuration - use environment variables or defaults
QUPATH_06_PATH="${QUPATH_06_PATH:-./qupath_06/bin/QuPath}"
QUPATH_051_PATH="${QUPATH_051_PATH:-./qupath_051/bin/QuPath}"
MODEL_PATH="${MODEL_PATH:-./models/he_heavy_augment.pb}"
HE_BASE_DIR="${HE_BASE_DIR:-./data}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" >&2
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}" >&2
    fi
}

# Help function
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -q, --qupath PATH    Test specific QuPath executable path"
    echo "  -v, --verbose        Enable verbose output"
    echo "  -h, --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $0                           # Test default installations"
    echo "  $0 -q /path/to/QuPath        # Test custom QuPath installation"
    echo "  $0 -q /path/to/QuPath -v     # Test with verbose output"
    echo
    echo "This script tests:"
    echo "  ✓ CUDA availability"
    echo "  ✓ Default QuPath installations (0.5.1 and 0.6)"
    echo "  ✓ Custom QuPath installations (if specified)"
    echo "  ✓ Model file availability"
    echo "  ✓ Pipeline scripts availability"
    echo "  ✓ Provides optimal configuration recommendations"
    exit 1
}

# Parse arguments
CUSTOM_QUPATH_PATH=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
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
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Logging functions
verbose_log() {
    if [ "$VERBOSE" = true ]; then
        echo "  [VERBOSE] $1"
    fi
}

echo "==============================================="
echo "     PANK Thesis - Unified Pipeline Test"
echo "==============================================="
echo

# Test CUDA availability
echo "Testing CUDA availability..."
if command -v nvidia-smi &> /dev/null; then
    if nvidia-smi &> /dev/null; then
        gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
        gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1)
        echo "✅ CUDA available: $gpu_count GPU(s) detected"
        echo "   GPU info: $gpu_info"
        CUDA_AVAILABLE=true
    else
        echo "❌ nvidia-smi found but failed to execute"
        CUDA_AVAILABLE=false
    fi
else
    echo "❌ nvidia-smi not found - CUDA not available"
    CUDA_AVAILABLE=false
fi

echo

# Test QuPath installations
echo "Testing QuPath installations..."

# Function to detect QuPath version
detect_qupath_version() {
    local qupath_path="$1"
    verbose_log "Detecting version for: $qupath_path"
    
    if [[ "$qupath_path" == *"0.5.1"* ]]; then
        echo "0.5.1"
    elif [[ "$qupath_path" == *"0.6"* ]] || [[ "$qupath_path" == *"0.6.0"* ]]; then
        echo "0.6"
    else
        # Try to get version from parent directory
        local parent_dir=$(dirname "$(dirname "$qupath_path")")
        if [[ "$parent_dir" == *"0.5.1"* ]]; then
            echo "0.5.1"
        elif [[ "$parent_dir" == *"0.6"* ]]; then
            echo "0.6"
        else
            echo "unknown"
        fi
    fi
}

# Function to check StarDist extension
check_stardist_extension() {
    local qupath_path="$1"
    local qupath_base_dir=$(dirname "$(dirname "$qupath_path")")
    
    verbose_log "Checking StarDist in: $qupath_base_dir"
    
    local search_dirs=(
        "$qupath_base_dir/lib"
        "$qupath_base_dir/lib/app"
        "$qupath_base_dir/extensions"
    )
    
    for search_dir in "${search_dirs[@]}"; do
        if [ -d "$search_dir" ]; then
            if find "$search_dir" -name "*stardist*.jar" 2>/dev/null | grep -q .; then
                return 0
            fi
        fi
    done
    return 1
}

# Test default QuPath 0.6
if [ -f "$QUPATH_06_PATH" ] && [ -x "$QUPATH_06_PATH" ]; then
    echo "✅ QuPath 0.6 available at: $QUPATH_06_PATH"
    if check_stardist_extension "$QUPATH_06_PATH"; then
        echo "   ✅ StarDist extension found"
    else
        echo "   ❌ StarDist extension not found"
    fi
    QUPATH_06_AVAILABLE=true
else
    echo "❌ QuPath 0.6 not found at: $QUPATH_06_PATH"
    QUPATH_06_AVAILABLE=false
fi

# Test default QuPath 0.5.1
if [ -f "$QUPATH_051_PATH" ] && [ -x "$QUPATH_051_PATH" ]; then
    echo "✅ QuPath 0.5.1 available at: $QUPATH_051_PATH"
    if check_stardist_extension "$QUPATH_051_PATH"; then
        echo "   ✅ StarDist extension found"
    else
        echo "   ❌ StarDist extension not found"
    fi
    QUPATH_051_AVAILABLE=true
else
    echo "❌ QuPath 0.5.1 not found at: $QUPATH_051_PATH"
    QUPATH_051_AVAILABLE=false
fi

# Test custom QuPath if specified
CUSTOM_QUPATH_AVAILABLE=false
CUSTOM_QUPATH_VERSION="unknown"
if [ -n "$CUSTOM_QUPATH_PATH" ]; then
    echo
    echo "Testing custom QuPath installation..."
    if [ -f "$CUSTOM_QUPATH_PATH" ] && [ -x "$CUSTOM_QUPATH_PATH" ]; then
        CUSTOM_QUPATH_VERSION=$(detect_qupath_version "$CUSTOM_QUPATH_PATH")
        echo "✅ Custom QuPath available at: $CUSTOM_QUPATH_PATH"
        echo "   Detected version: $CUSTOM_QUPATH_VERSION"
        
        if check_stardist_extension "$CUSTOM_QUPATH_PATH"; then
            echo "   ✅ StarDist extension found"
        else
            echo "   ❌ StarDist extension not found"
        fi
        CUSTOM_QUPATH_AVAILABLE=true
    else
        echo "❌ Custom QuPath not found or not executable: $CUSTOM_QUPATH_PATH"
        CUSTOM_QUPATH_AVAILABLE=false
    fi
fi

echo

# Test model file
echo "Testing model file..."
if [ -f "$MODEL_PATH" ]; then
    model_size=$(du -h "$MODEL_PATH" | cut -f1)
    echo "✅ Model file found: $MODEL_PATH ($model_size)"
    MODEL_AVAILABLE=true
else
    echo "❌ Model file not found: $MODEL_PATH"
    MODEL_AVAILABLE=false
fi

echo

# Test unified scripts
echo "Testing unified scripts..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/run_pipeline_01_unified_stardist.sh" ] && [ -x "$SCRIPT_DIR/run_pipeline_01_unified_stardist.sh" ]; then
    echo "✅ Unified StarDist script available and executable"
    UNIFIED_STARDIST_AVAILABLE=true
else
    echo "❌ Unified StarDist script not found or not executable"
    UNIFIED_STARDIST_AVAILABLE=false
fi

if [ -f "$SCRIPT_DIR/run_pipeline_01_unified_qc_export.sh" ] && [ -x "$SCRIPT_DIR/run_pipeline_01_unified_qc_export.sh" ]; then
    echo "✅ Unified QC export script available and executable"
    UNIFIED_QC_AVAILABLE=true
else
    echo "❌ Unified QC export script not found or not executable"
    UNIFIED_QC_AVAILABLE=false
fi

echo

# Test Groovy scripts
echo "Testing Groovy scripts..."
if [ -f "$SCRIPT_DIR/01_he_stardist_cell_segmentation_cpu.groovy" ]; then
    echo "✅ CPU-optimized Groovy script available"
    CPU_SCRIPT_AVAILABLE=true
else
    echo "❌ CPU-optimized Groovy script not found"
    CPU_SCRIPT_AVAILABLE=false
fi

if [ -f "$SCRIPT_DIR/01_he_stardist_cell_segmentation_gpu.groovy" ]; then
    echo "✅ GPU-optimized Groovy script available"
    GPU_SCRIPT_AVAILABLE=true
else
    echo "❌ GPU-optimized Groovy script not found"
    GPU_SCRIPT_AVAILABLE=false
fi

if [ -f "$SCRIPT_DIR/01_he_stardist_cell_segmentation_shell_compatible.groovy" ]; then
    echo "✅ Generic Groovy script available (fallback)"
    GENERIC_SCRIPT_AVAILABLE=true
else
    echo "❌ Generic Groovy script not found"
    GENERIC_SCRIPT_AVAILABLE=false
fi

echo

# Determine optimal configuration
echo "Determining optimal configuration..."

# Priority: Custom QuPath > Default installations
if [ "$CUSTOM_QUPATH_AVAILABLE" = true ]; then
    if [ "$CUSTOM_QUPATH_VERSION" = "0.5.1" ] && [ "$CUDA_AVAILABLE" = true ]; then
        RECOMMENDED_MODE="GPU (Custom)"
        RECOMMENDED_QUPATH="$CUSTOM_QUPATH_PATH"
        echo "🚀 Recommended: GPU mode with custom QuPath 0.5.1 + CUDA"
    elif [ "$CUSTOM_QUPATH_VERSION" = "0.6" ]; then
        RECOMMENDED_MODE="CPU (Custom)"
        RECOMMENDED_QUPATH="$CUSTOM_QUPATH_PATH"
        echo "🖥️  Recommended: CPU mode with custom QuPath 0.6"
    else
        RECOMMENDED_MODE="Custom (Auto-detect)"
        RECOMMENDED_QUPATH="$CUSTOM_QUPATH_PATH"
        echo "⚙️  Recommended: Auto-detection with custom QuPath"
    fi
elif [ "$CUDA_AVAILABLE" = true ] && [ "$QUPATH_051_AVAILABLE" = true ]; then
    RECOMMENDED_MODE="GPU"
    RECOMMENDED_QUPATH="$QUPATH_051_PATH"
    echo "🚀 Recommended: GPU mode (QuPath 0.5.1 + CUDA)"
elif [ "$QUPATH_06_AVAILABLE" = true ]; then
    RECOMMENDED_MODE="CPU"
    RECOMMENDED_QUPATH="$QUPATH_06_PATH"
    echo "🖥️  Recommended: CPU mode (QuPath 0.6 + 128-core optimization)"
elif [ "$QUPATH_051_AVAILABLE" = true ]; then
    RECOMMENDED_MODE="GPU (no CUDA)"
    RECOMMENDED_QUPATH="$QUPATH_051_PATH"
    echo "⚠️  Recommended: GPU mode (QuPath 0.5.1) but CUDA not available"
else
    RECOMMENDED_MODE="NONE"
    RECOMMENDED_QUPATH="NONE"
    echo "❌ No suitable configuration found"
fi

echo

# Summary
echo "==============================================="
echo "                   SUMMARY"
echo "==============================================="
echo "CUDA Available:           $CUDA_AVAILABLE"
echo "QuPath 0.6 Available:     $QUPATH_06_AVAILABLE"
echo "QuPath 0.5.1 Available:   $QUPATH_051_AVAILABLE"
if [ -n "$CUSTOM_QUPATH_PATH" ]; then
    echo "Custom QuPath Available:  $CUSTOM_QUPATH_AVAILABLE ($CUSTOM_QUPATH_VERSION)"
fi
echo "Model Available:          $MODEL_AVAILABLE"
echo "Unified Scripts:          $UNIFIED_STARDIST_AVAILABLE / $UNIFIED_QC_AVAILABLE"
echo "Groovy Scripts:           CPU=$CPU_SCRIPT_AVAILABLE, GPU=$GPU_SCRIPT_AVAILABLE, Generic=$GENERIC_SCRIPT_AVAILABLE"
echo ""
echo "Recommended Mode:         $RECOMMENDED_MODE"
echo "Recommended QuPath:       $RECOMMENDED_QUPATH"
echo

# Test commands
if [ "$UNIFIED_STARDIST_AVAILABLE" = true ]; then
    echo "Recommended test commands:"
    
    if [ "$CUSTOM_QUPATH_AVAILABLE" = true ]; then
        echo "  # Test with your custom QuPath:"
        if [ "$CUSTOM_QUPATH_VERSION" = "0.5.1" ] && [ "$CUDA_AVAILABLE" = true ]; then
            echo "  ./run_pipeline_01_unified_stardist.sh -s -q '$CUSTOM_QUPATH_PATH' -m gpu -v"
        elif [ "$CUSTOM_QUPATH_VERSION" = "0.6" ]; then
            echo "  ./run_pipeline_01_unified_stardist.sh -s -q '$CUSTOM_QUPATH_PATH' -m cpu -v"
        else
            echo "  ./run_pipeline_01_unified_stardist.sh -s -q '$CUSTOM_QUPATH_PATH' -v"
        fi
        echo ""
    fi
    
    echo "  # Test with auto-detection:"
    echo "  ./run_pipeline_01_unified_stardist.sh -s -v"
    echo ""
    
    if [ "$RECOMMENDED_MODE" != "NONE" ]; then
        echo "  # Recommended optimal command:"
        if [[ "$RECOMMENDED_MODE" == *"GPU"* ]]; then
            if [ "$CUSTOM_QUPATH_AVAILABLE" = true ]; then
                echo "  ./run_pipeline_01_unified_stardist.sh -s -q '$CUSTOM_QUPATH_PATH' -m gpu -v"
            else
                echo "  ./run_pipeline_01_unified_stardist.sh -s -m gpu -v"
            fi
        elif [[ "$RECOMMENDED_MODE" == *"CPU"* ]]; then
            if [ "$CUSTOM_QUPATH_AVAILABLE" = true ]; then
                echo "  ./run_pipeline_01_unified_stardist.sh -s -q '$CUSTOM_QUPATH_PATH' -m cpu -v"
            else
                echo "  ./run_pipeline_01_unified_stardist.sh -s -m cpu -v"
            fi
        fi
    fi
    
    echo ""
    echo "  # Test QC export:"
    echo "  ./run_pipeline_01_unified_qc_export.sh -s -v"
fi

echo
echo "Test completed!" 