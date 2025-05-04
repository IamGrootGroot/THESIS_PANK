/*
 * Copyright (c) 2024 Maxence PELLOUX
 * All rights reserved.
 *
 * This script is part of the PANK thesis project and implements the first step
 * of the cell segmentation pipeline using StarDist2D for H&E stained images.
 */

import qupath.lib.objects.classes.PathClass
import qupath.ext.stardist.StarDist2D
import qupath.lib.images.ImageData
import qupath.lib.projects.Project
import qupath.lib.images.servers.ImageServerProvider

// Configuration parameters for StarDist2D cell segmentation
// Declare at script level (not inside a class definition or method)
PIXEL_SIZE = 0.23  // microns per pixel
DETECTION_THRESHOLD = 0.25
CELL_EXPANSION = 0.0
MAX_IMAGE_DIMENSION = 4096
NORMALIZATION_PERCENTILES = [0.2, 99.8]

/**
 * Parse command line arguments
 * @return Map containing parsed arguments
 */
def parseArguments() {
    def args = args
    if (!args) {
        println "Error: No arguments provided"
        return null
    }
    
    def modelPath = null
    
    args.each { arg ->
        if (arg.startsWith("model=")) {
            modelPath = arg.substring(6)
        }
    }
    
    if (!modelPath) {
        println "Error: Model path not provided"
        return null
    }
    
    return [modelPath: modelPath]
}

/**
 * Validates the existence of the StarDist model file
 * @param modelPath Path to the model file
 * @return boolean indicating if the model file exists
 */
def validateModelFile(String modelPath) {
    def modelFile = new File(modelPath)
    if (!modelFile.exists()) {
        print "Error: Model file not found at ${modelPath}"
        return false
    }
    return true
}

/**
 * Creates and configures the StarDist2D model with specified parameters
 * @param modelPath Path to the model file
 * @return configured StarDist2D instance
 */
def createStarDistModel(String modelPath) {
    return StarDist2D.builder(modelPath)
        .threshold(DETECTION_THRESHOLD)
        .pixelSize(PIXEL_SIZE)
        .cellExpansion(CELL_EXPANSION)
        .measureShape()
        .measureIntensity()
        .classify(PathClass.fromString("Nucleus"))
        .preprocess(
            StarDist2D.imageNormalizationBuilder()
                .maxDimension(MAX_IMAGE_DIMENSION)
                .percentiles(NORMALIZATION_PERCENTILES[0], NORMALIZATION_PERCENTILES[1])
                .build()
        )
        .build()
}

/**
 * Main execution function for cell detection
 */
def runCellDetection() {
    // Parse command line arguments
    def args = parseArguments()
    if (!args) {
        return
    }

    // Validate model file
    if (!validateModelFile(args.modelPath)) {
        return
    }

    // Get the current image data (already loaded by QuPath's --image parameter)
    def imageData = getCurrentImageData()
    if (imageData == null) {
        print "Error: No image is currently loaded"
        return
    }

    // Setup hierarchy and annotations
    def hierarchy = imageData.getHierarchy()
    def annotations = hierarchy.getAnnotationObjects()

    // Create full image annotation if none exists
    if (annotations.isEmpty()) {
        print "No annotations found. Creating full image annotation..."
        createFullImageAnnotation(true)
        annotations = hierarchy.getAnnotationObjects()
    }

    print "Running StarDist detection on the current image..."

    try {
        def stardist = createStarDistModel(args.modelPath)
        def totalAnnotations = annotations.size()
        def processedAnnotations = 0

        // Run detection on annotations
        stardist.detectObjects(imageData, annotations).each { detection ->
            hierarchy.addObject(detection, true)
            processedAnnotations++
            
            // Report progress
            if (processedAnnotations % Math.max(100, totalAnnotations/10) == 0 || processedAnnotations == totalAnnotations) {
                def progress = (processedAnnotations / totalAnnotations * 100).round(1)
                print "Progress: ${progress}% (${processedAnnotations}/${totalAnnotations} annotations processed)"
            }
        }

        // Save results
        fireHierarchyUpdate()
        print "Completed detection for the current image."
    } catch (Exception e) {
        print "Error during detection: " + e.getMessage()
    }
}

// Execute the main function
runCellDetection()
print "StarDist nucleus detection completed for the current image!"
