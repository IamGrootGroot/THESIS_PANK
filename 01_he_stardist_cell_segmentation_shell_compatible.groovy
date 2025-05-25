/*
 * Simple and Reliable StarDist Cell Segmentation
 * Based on A.Khellaf's working version, modified for TRIDENT annotations
 * 
 * This script processes all "Tissue (TRIDENT)" annotations in the current image
 * using StarDist2D for cell detection.
 */

import qupath.ext.stardist.StarDist2D
import qupath.lib.objects.classes.PathClass

// Configuration - using the working model path from the server
def pathModel = "/u/trinhvq/Documents/maxencepelloux/HE/THESIS_PANK/models/he_heavy_augment.pb"

println "=== Simple StarDist Cell Detection ==="
println "Model path: ${pathModel}"

// Check if model file exists
def modelFile = new File(pathModel)
if (!modelFile.exists()) {
    println "ERROR: Model file not found at ${pathModel}"
    return
}

// Get current image data
def imageData = getCurrentImageData()
if (imageData == null) {
    println "ERROR: No image data available"
    return
}

def server = imageData.getServer()
def imageName = server.getMetadata().getName()
println "Processing image: ${imageName}"

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

println "Found ${tridentAnnotations.size()} TRIDENT annotation(s)"

// Create StarDist detector with simple, reliable settings
println "Creating StarDist detector..."
def stardist = StarDist2D.builder(pathModel)
    .threshold(0.25)              // Prediction threshold
    .preprocess(                  // Apply normalization
        StarDist2D.imageNormalizationBuilder()
            .maxDimension(4096)   // Conservative max dimension
            .percentiles(0.2, 99.8)  // Normalization percentiles
            .build()
    )
    .pixelSize(0.23)              // Resolution: 0.23um per pixel
    .build()

println "StarDist detector created successfully"

// Process each TRIDENT annotation
def totalDetections = 0
def startTime = System.currentTimeMillis()

tridentAnnotations.eachWithIndex { annotation, index ->
    println "Processing TRIDENT annotation ${index + 1}/${tridentAnnotations.size()}"
    
    try {
        // Run detection on this annotation
        def detections = stardist.detectObjects(imageData, annotation)
        totalDetections += detections.size()
        
        println "  Detected ${detections.size()} cells in annotation ${index + 1}"
        
    } catch (Exception e) {
        println "  ERROR processing annotation ${index + 1}: ${e.getMessage()}"
    }
}

def processingTime = System.currentTimeMillis() - startTime

// Update hierarchy and save
println "Updating hierarchy..."
fireHierarchyUpdate()

// Print summary
println "=== Detection Complete ==="
println "Image: ${imageName}"
println "TRIDENT annotations processed: ${tridentAnnotations.size()}"
println "Total cells detected: ${totalDetections}"
println "Processing time: ${processingTime}ms"
println "Average cells per annotation: ${tridentAnnotations.size() > 0 ? (totalDetections / tridentAnnotations.size()).round(1) : 0}"

if (totalDetections > 0) {
    println "Detection speed: ${(totalDetections / (processingTime / 1000.0)).round(1)} cells/second"
}

println "Done!"