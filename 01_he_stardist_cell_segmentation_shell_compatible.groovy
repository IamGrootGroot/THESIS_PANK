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

import qupath.ext.stardist.StarDist2D
import qupath.lib.objects.classes.PathClass

// =============================================================================
// PERFORMANCE CONFIGURATION - TUNE THESE FOR SPEED
// =============================================================================

// Model path
def pathModel = "/u/trinhvq/Documents/maxencepelloux/HE/THESIS_PANK/models/he_heavy_augment.pb"

// SPEED PARAMETER 1: Detection threshold (higher = faster, fewer cells)
def DETECTION_THRESHOLD = 0.25  // Options: 0.2 (slow, more cells), 0.25 (balanced), 0.3 (fast, fewer cells)

// SPEED PARAMETER 2: Max image dimension (higher = faster processing of large images)
def MAX_DIMENSION = 16384  // Options: 4096 (conservative), 8192 (fast), 16384 (maximum speed, high memory)

// SPEED PARAMETER 3: Pixel size (should match your actual resolution)
def PIXEL_SIZE = 0.23  // Your actual resolution - don't change unless you know your exact pixel size

// SPEED PARAMETER 4: Normalization percentiles (wider = more robust but slower)
def NORM_LOW = 0.5   // Options: 0.2 (robust, slow), 0.5 (balanced), 1.0 (fast, less robust)
def NORM_HIGH = 99.5 // Options: 99.8 (robust, slow), 99.5 (balanced), 99.0 (fast, less robust)

// SPEED PARAMETER 5: Cell expansion (0 = fastest, >0 = slower but better cell boundaries)
def CELL_EXPANSION = 0.0  // Options: 0.0 (fastest), 1.0 (slower but better), 2.0 (slowest)

// SPEED PARAMETER 6: Enable measurements (disable for maximum speed)
def MEASURE_SHAPE = false     // Set to false for speed, true for detailed analysis
def MEASURE_INTENSITY = false // Set to false for speed, true for detailed analysis

// =============================================================================

println "=== Optimized StarDist Cell Detection ==="
println "Model path: ${pathModel}"
println "Performance settings:"
println "  Detection threshold: ${DETECTION_THRESHOLD}"
println "  Max dimension: ${MAX_DIMENSION}"
println "  Pixel size: ${PIXEL_SIZE}"
println "  Normalization: ${NORM_LOW}-${NORM_HIGH}%"
println "  Cell expansion: ${CELL_EXPANSION}"
println "  Shape measurements: ${MEASURE_SHAPE}"
println "  Intensity measurements: ${MEASURE_INTENSITY}"

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

// Create StarDist detector with optimized settings
println "Creating optimized StarDist detector..."
def builder = StarDist2D.builder(pathModel)
    .threshold(DETECTION_THRESHOLD)
    .preprocess(
        StarDist2D.imageNormalizationBuilder()
            .maxDimension(MAX_DIMENSION)
            .percentiles(NORM_LOW, NORM_HIGH)
            .build()
    )
    .pixelSize(PIXEL_SIZE)
    .cellExpansion(CELL_EXPANSION)

// Add measurements only if requested (measurements slow down processing)
if (MEASURE_SHAPE) {
    builder = builder.measureShape()
}
if (MEASURE_INTENSITY) {
    builder = builder.measureIntensity()
}

def stardist = builder.build()

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