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
import qupath.lib.roi.ROIs
import qupath.lib.objects.PathObjects
import qupath.lib.regions.ImagePlane

// Configuration parameters for StarDist2D cell segmentation
PIXEL_SIZE = 0.23  // microns per pixel
DETECTION_THRESHOLD = 0.25
CELL_EXPANSION = 0.0
MAX_IMAGE_DIMENSION = 4096
NORMALIZATION_PERCENTILES = [0.2, 99.8]
TILE_SIZE = 4096

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
        .tileSize(TILE_SIZE)
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
 * Explicitly save the current image data to the project
 * @param imageData The current image data to save
 */
def saveImageData(imageData) {
    def project = getProject()
    if (project == null) {
        print "Error: Cannot save - no project available"
        return
    }
    
    def entry = project.getEntry(imageData)
    if (entry == null) {
        print "Error: Cannot save - no project entry found for current image"
        return
    }
    
    print "Saving changes to project..."
    entry.saveImageData(imageData)
    project.syncChanges()
    print "Project saved successfully"
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
    createFullImageAnnotation(true)
    if (imageData == null) {
        print "Error: No image is currently loaded"
        return
    }

    // Setup hierarchy and annotations
    def hierarchy = imageData.getHierarchy()
    def annotations = hierarchy.getAnnotationObjects()

    print "Running StarDist detection on the current image..."

    try {
        def stardist = createStarDistModel(args.modelPath)
        def totalAnnotations = annotations.size()
        def processedAnnotations = 0
        def totalDetections = 0

        // Run detection on annotations
        annotations.each { annotation ->
            print "Processing annotation ${++processedAnnotations}/${totalAnnotations}: ${annotation.getName() ?: 'Unnamed'}"
            
            // Get the ROI from the annotation - this is the correct argument for StarDist
            def roi = annotation.getROI()
            
            // Use the correct method signature: detectObjects(imageData, roi)
            def detections = stardist.detectObjects(imageData, roi)
            
            // Add all detected cells to the hierarchy
            detections.each { detection ->
                hierarchy.addObject(detection)
                totalDetections++
            }
            
            print "Added ${detections.size()} cell detections to annotation ${annotation.getName() ?: 'Unnamed'}"
        }

        // Save results
        print "Finalizing detection results with $totalDetections total cells detected..."
        fireHierarchyUpdate()
        
        // Explicitly save to project
        saveImageData(imageData)
        
        print "Completed detection for the current image."
    } catch (Exception e) {
        print "Error during detection: " + e.getMessage()
        e.printStackTrace()
    }
}

// Execute the main function
runCellDetection()
print "StarDist nucleus detection completed for the current image!"
