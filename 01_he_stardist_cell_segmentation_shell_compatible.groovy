/*
 * Simple and Reliable StarDist Cell Segmentation
 * Based on A.Khellaf's working version, modified for TRIDENT annotations
 * 
 * This script processes all "Tissue (TRIDENT)" annotations in the current image
 * using StarDist2D for cell detection.
 * 
 * PERFORMANCE TUNING PARAMETERS:
 * - maxDimension: Higher = faster but more memory (4096 conservative, 8192 fast, 16384 max)
 * - threshold: Lower = more cells but slower (0.25 balanced, 0.3 faster, 0.2 slower)
 * - pixelSize: Match your actual resolution for optimal speed
 * - percentiles: Wider range = more robust but slower normalization
 */

// Cell segmentation using StarDist2D - based on A.Khellaf's working version
// Modified to process TRIDENT annotations instead of selected objects

// Import in the same order as Khellaf's working version
import qupath.lib.gui.dialogs.Dialogs
import qupath.ext.stardist.StarDist2D

println "=== StarDist Extension Test ==="
println "StarDist2D class loaded successfully: ${StarDist2D.class.name}"

// Model path (updated for server location)
def pathModel = "/u/trinhvq/Documents/maxencepelloux/HE/THESIS_PANK/models/he_heavy_augment.pb"
println "Model path: ${pathModel}"

// Check if model exists
def modelFile = new File(pathModel)
if (!modelFile.exists()) {
    println "ERROR: Model file not found at ${pathModel}"
    return
}

println "Model file found successfully"

// Get current image data
def imageData = getCurrentImageData()
if (imageData == null) {
    println "ERROR: No image data available"
    return
}

def server = imageData.getServer()
def imageName = server.getMetadata().getName()
println "Processing image: ${imageName}"

// Create StarDist detector (exact same parameters as Khellaf)
println "Creating StarDist detector..."
def stardist = StarDist2D.builder(pathModel)
      .threshold(0.25)              // Prediction threshold
      .preprocess(                 // Apply normalization
        StarDist2D.imageNormalizationBuilder()
            .maxDimension(4096)    // Conservative setting
            .percentiles(0.2, 99.8)  // Khellaf's exact values
            .build()
    )
      .pixelSize(0.23)              // Resolution
      .build()

println "StarDist detector created successfully"

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

// Process each TRIDENT annotation (same as Khellaf's approach)
def totalDetections = 0
tridentAnnotations.eachWithIndex { annotation, index ->
    println "Processing TRIDENT annotation ${index + 1}/${tridentAnnotations.size()}"
    
    try {
        // Run detection (exact same call as Khellaf but with list)
        stardist.detectObjects(imageData, [annotation])
        
        // Count detections in this annotation
        def detections = annotation.getChildObjects().findAll { it.isDetection() }
        totalDetections += detections.size()
        
        println "  Detected ${detections.size()} cells in annotation ${index + 1}"
        
    } catch (Exception e) {
        println "  ERROR processing annotation ${index + 1}: ${e.getMessage()}"
        e.printStackTrace()
    }
}

// Update hierarchy
println "Updating hierarchy..."
fireHierarchyUpdate()

// Print summary
println "=== Detection Complete ==="
println "Image: ${imageName}"
println "TRIDENT annotations processed: ${tridentAnnotations.size()}"
println "Total cells detected: ${totalDetections}"

println "Done!"