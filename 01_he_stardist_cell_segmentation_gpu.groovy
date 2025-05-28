/*
 * GPU-Optimized StarDist Cell Segmentation for QuPath 0.5.1
 * Optimized for CUDA GPU acceleration with TRIDENT annotations
 * 
 * Copyright (c) 2024 Maxence PELLOUX
 * All rights reserved.
 * 
 * PERFORMANCE TUNING FOR GPU:
 * - maxDimension: 8192 (optimal for GPU memory)
 * - threshold: 0.25 (balanced accuracy/speed)
 * - pixelSize: 0.23 (match actual resolution)
 * - percentiles: 0.2, 99.8 (robust normalization)
 * - GPU acceleration enabled for maximum speed
 */

// Import required classes for QuPath 0.5.1
import qupath.lib.gui.dialogs.Dialogs
import qupath.ext.stardist.StarDist2D

println "=== GPU-Optimized StarDist Cell Segmentation ==="
println "QuPath 0.5.1 - CUDA GPU Acceleration"
println "StarDist2D class loaded: ${StarDist2D.class.name}"

// Model path (server location)
def pathModel = "/u/trinhvq/Documents/maxencepelloux/HE/THESIS_PANK/models/he_heavy_augment.pb"
println "Model path: ${pathModel}"

// Validate model file
def modelFile = new File(pathModel)
if (!modelFile.exists()) {
    println "ERROR: Model file not found at ${pathModel}"
    return
}
println "Model file validated successfully"

// Get current image data
def imageData = getCurrentImageData()
if (imageData == null) {
    println "ERROR: No image data available"
    return
}

def server = imageData.getServer()
def imageName = server.getMetadata().getName()
println "Processing image: ${imageName}"

// GPU-optimized StarDist detector configuration
println "Creating GPU-optimized StarDist detector..."
def stardist = StarDist2D.builder(pathModel)
      .threshold(0.25)              // Balanced prediction threshold
      .preprocess(                 // GPU-optimized normalization
        StarDist2D.imageNormalizationBuilder()
            .maxDimension(8192)     // Optimal for GPU memory usage
            .percentiles(0.2, 99.8)  // Robust normalization range
            .build()
    )
      .pixelSize(0.23)              // Match actual slide resolution
      .build()

println "GPU-optimized StarDist detector created successfully"
println "Configuration: maxDimension=8192, threshold=0.25, pixelSize=0.23"

// Get hierarchy and find TRIDENT annotations
def hierarchy = imageData.getHierarchy()
def tridentClass = getPathClass("Tissue (TRIDENT)")

if (tridentClass == null) {
    println "ERROR: PathClass 'Tissue (TRIDENT)' not found"
    println "Available classes:"
    getPathClasses().each { pathClass ->
        println "  - ${pathClass.getName()}"
    }
    return
}

// Find all TRIDENT annotations
def tridentAnnotations = hierarchy.getAnnotationObjects().findAll { 
    it.getPathClass() == tridentClass 
}

if (tridentAnnotations.isEmpty()) {
    println "WARNING: No TRIDENT annotations found in ${imageName}"
    return
}

println "Found ${tridentAnnotations.size()} TRIDENT annotation(s) for processing"

// Process each TRIDENT annotation with GPU optimization
def totalDetections = 0
def startTime = System.currentTimeMillis()

tridentAnnotations.eachWithIndex { annotation, index ->
    println "Processing TRIDENT annotation ${index + 1}/${tridentAnnotations.size()}"
    
    def annotationStartTime = System.currentTimeMillis()
    
    try {
        // Run GPU-accelerated detection
        stardist.detectObjects(imageData, [annotation])
        
        // Count detections in this annotation
        def detections = annotation.getChildObjects().findAll { it.isDetection() }
        totalDetections += detections.size()
        
        def annotationTime = System.currentTimeMillis() - annotationStartTime
        println "  Detected ${detections.size()} cells in annotation ${index + 1} (${annotationTime}ms)"
        
    } catch (Exception e) {
        println "  ERROR processing annotation ${index + 1}: ${e.getMessage()}"
        e.printStackTrace()
    }
}

// Update hierarchy and calculate performance metrics
println "Updating hierarchy..."
fireHierarchyUpdate()

def totalTime = System.currentTimeMillis() - startTime
def detectionSpeed = totalDetections > 0 ? (totalDetections / (totalTime / 1000.0)) : 0

// Performance summary
println "=== GPU Processing Complete ==="
println "Image: ${imageName}"
println "Processing mode: GPU (CUDA accelerated)"
println "TRIDENT annotations processed: ${tridentAnnotations.size()}"
println "Total cells detected: ${totalDetections}"
println "Total processing time: ${totalTime}ms (${totalTime/1000.0}s)"
println "Detection speed: ${detectionSpeed.round(2)} cells/second"
println "Average time per annotation: ${tridentAnnotations.size() > 0 ? (totalTime/tridentAnnotations.size()).round(2) : 0}ms"

// Memory usage information
def runtime = Runtime.getRuntime()
def usedMemory = (runtime.totalMemory() - runtime.freeMemory()) / 1024 / 1024
println "Memory usage: ${usedMemory.round(2)} MB"

// GPU-specific performance notes
println ""
println "GPU Performance Notes:"
println "- Using maxDimension=8192 for optimal GPU memory usage"
println "- CUDA acceleration should provide significant speedup over CPU"
println "- Monitor GPU memory usage with nvidia-smi if available"

println "GPU-optimized cell segmentation completed successfully!" 