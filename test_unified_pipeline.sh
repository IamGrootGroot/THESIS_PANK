#!/bin/bash

# =============================================================================
# PANK Thesis Project - Unified Pipeline Test Script
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script tests the unified pipeline configuration detection without
# actually running the full pipeline.
# =============================================================================

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

QUPATH_06_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6/qupath/build/dist/QuPath/bin/QuPath"
QUPATH_051_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build_0.5.1/qupath/build/dist/QuPath/bin/QuPath"

# Test QuPath 0.6
if [ -f "$QUPATH_06_PATH" ] && [ -x "$QUPATH_06_PATH" ]; then
    echo "✅ QuPath 0.6 available at: $QUPATH_06_PATH"
    QUPATH_06_AVAILABLE=true
else
    echo "❌ QuPath 0.6 not found at: $QUPATH_06_PATH"
    QUPATH_06_AVAILABLE=false
fi

# Test QuPath 0.5.1
if [ -f "$QUPATH_051_PATH" ] && [ -x "$QUPATH_051_PATH" ]; then
    echo "✅ QuPath 0.5.1 available at: $QUPATH_051_PATH"
    QUPATH_051_AVAILABLE=true
else
    echo "❌ QuPath 0.5.1 not found at: $QUPATH_051_PATH"
    QUPATH_051_AVAILABLE=false
fi

echo

# Test model file
echo "Testing model file..."
MODEL_PATH="/u/trinhvq/Documents/maxencepelloux/HE/THESIS_PANK/models/he_heavy_augment.pb"
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
if [ "$CUDA_AVAILABLE" = true ] && [ "$QUPATH_051_AVAILABLE" = true ]; then
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
echo "Model Available:          $MODEL_AVAILABLE"
echo "Unified Scripts:          $UNIFIED_STARDIST_AVAILABLE / $UNIFIED_QC_AVAILABLE"
echo "Groovy Scripts:           CPU=$CPU_SCRIPT_AVAILABLE, GPU=$GPU_SCRIPT_AVAILABLE, Generic=$GENERIC_SCRIPT_AVAILABLE"
echo ""
echo "Recommended Mode:         $RECOMMENDED_MODE"
echo "Recommended QuPath:       $RECOMMENDED_QUPATH"
echo

# Test commands
if [ "$UNIFIED_STARDIST_AVAILABLE" = true ]; then
    echo "Test commands:"
    echo "  # Test with auto-detection:"
    echo "  ./run_pipeline_01_unified_stardist.sh -s -v"
    echo ""
    echo "  # Test with specific mode:"
    if [ "$RECOMMENDED_MODE" = "GPU" ]; then
        echo "  ./run_pipeline_01_unified_stardist.sh -s -m gpu -v"
    elif [ "$RECOMMENDED_MODE" = "CPU" ]; then
        echo "  ./run_pipeline_01_unified_stardist.sh -s -m cpu -v"
    fi
    echo ""
    echo "  # Test QC export:"
    echo "  ./run_pipeline_01_unified_qc_export.sh -s -v"
fi

echo
echo "Test completed!" 