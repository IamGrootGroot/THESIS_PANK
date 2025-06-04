/*
 * StarDist Cell Segmentation for TRIDENT annotations
 * Processes all "Tissue (TRIDENT)" annotations using StarDist2D
 */

import qupath.lib.gui.dialogs.Dialogs
import qupath.ext.stardist.StarDist2D

println "=== StarDist Extension Test ==="
println "StarDist2D class loaded successfully: ${StarDist2D.class.name}"

// Model path - configurable via environment or default
def modelPath = System.getProperty("MODEL_PATH") ?: 
               System.getenv("MODEL_PATH") ?: 
               "./models/he_heavy_augment.pb"
println "Model path: ${modelPath}"

def modelFile = new File(modelPath)
if (!modelFile.exists()) {
    println "ERROR: Model file not found at ${modelPath}"
    return
}

println "Model file found successfully"

def imageData = getCurrentImageData()
if (imageData == null) {
    println "ERROR: No image data available"
    return
}

def server = imageData.getServer()
def imageName = server.getMetadata().getName()
println "Processing image: ${imageName}"

// Create StarDist detector
println "Creating StarDist detector..."
def stardist = StarDist2D.builder(modelPath)
      .threshold(0.25)
      .preprocess(
        StarDist2D.imageNormalizationBuilder()
            .maxDimension(4096)
            .percentiles(0.2, 99.8)
            .build()
    )
      .pixelSize(0.23)
      .build()

println "StarDist detector created successfully"

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

def tridentAnnotations = hierarchy.getAnnotationObjects().findAll { 
    it.getPathClass() == tridentClass 
}

if (tridentAnnotations.isEmpty()) {
    println "WARNING: No TRIDENT annotations found in ${imageName}"
    return
}

println "Found ${tridentAnnotations.size()} TRIDENT annotation(s)"

def totalDetections = 0
tridentAnnotations.eachWithIndex { annotation, index ->
    println "Processing TRIDENT annotation ${index + 1}/${tridentAnnotations.size()}"
    
    try {
        stardist.detectObjects(imageData, [annotation])
        
        def detections = annotation.getChildObjects().findAll { it.isDetection() }
        totalDetections += detections.size()
        
        println "  Detected ${detections.size()} cells in annotation ${index + 1}"
        
    } catch (Exception e) {
        println "  ERROR processing annotation ${index + 1}: ${e.getMessage()}"
        e.printStackTrace()
    }
}

println "Updating hierarchy..."
fireHierarchyUpdate()

println "=== Detection Complete ==="
println "Image: ${imageName}"
println "TRIDENT annotations processed: ${tridentAnnotations.size()}"
println "Total cells detected: ${totalDetections}"

println "Done!"