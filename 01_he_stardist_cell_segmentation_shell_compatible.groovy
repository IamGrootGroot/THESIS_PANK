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
import javax.swing.JOptionPane
import qupath.lib.gui.dialogs.Dialogs

// Configuration parameters for StarDist2D cell segmentation
// Declare at script level (not inside a class definition or method)
PIXEL_SIZE = 0.23  // microns per pixel
DETECTION_THRESHOLD = 0.25
CELL_EXPANSION = 0.0
MAX_IMAGE_DIMENSION = 4096
NORMALIZATION_PERCENTILES = [0.2, 99.8]
DEFAULT_FORCE_REDETECTION = false  // Change to true to force redetection

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
    def forceRedetection = DEFAULT_FORCE_REDETECTION
    
    args.each { arg ->
        if (arg.startsWith("model=")) {
            modelPath = arg.substring(6)
        } else if (arg == "force=true") {
            forceRedetection = true
        }
    }
    
    if (!modelPath) {
        println "Error: Model path not provided"
        return null
    }
    
    return [modelPath: modelPath, forceRedetection: forceRedetection]
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
 * Creates a full image annotation
 * @param imageData The current image data
 * @return The created annotation object
 */
def createFullImageAnnotation(imageData) {
    def server = imageData.getServer()
    def width = server.getWidth()
    def height = server.getHeight()
    def roi = ROIs.createRectangleROI(0, 0, width, height, ImagePlane.getDefaultPlane())
    def annotation = PathObjects.createAnnotationObject(roi, PathClass.fromString("Tissue"))
    annotation.setName("Whole Image")
    imageData.getHierarchy().addObject(annotation)
    return annotation
}

/**
 * Checks if the image already has cell detections
 * @param imageData The current image data
 * @return boolean indicating if cells have already been detected
 */
def hasExistingCellDetections(imageData) {
    def hierarchy = imageData.getHierarchy()
    def detections = hierarchy.getDetectionObjects()
    return !detections.isEmpty()
}

/**
 * Counts the number of detection objects in the hierarchy
 * @param imageData The current image data
 * @return int count of detection objects
 */
def countDetections(imageData) {
    def hierarchy = imageData.getHierarchy()
    return hierarchy.getDetectionObjects().size()
}

/**
 * Removes all detection objects from the hierarchy
 * @param imageData The current image data
 * @return int count of removed detection objects
 */
def clearExistingDetections(imageData) {
    def hierarchy = imageData.getHierarchy()
    def detections = hierarchy.getDetectionObjects()
    def count = detections.size()
    
    if (count > 0) {
        hierarchy.removeObjects(detections, true)
        print "Removed ${count} existing detection objects"
    }
    
    return count
}

/**
 * Gets a decision from the user for how to handle existing detections
 * @param existingCount The number of existing detections
 * @return String indicating the user's choice ('REPLACE', 'KEEP', 'CANCEL')
 */
def askUserAboutExistingDetections(int existingCount) {
    // In a headless context, we can't show dialog boxes, so return based on force parameter
    if (existingCount > 0) {
        print "Found ${existingCount} existing cell detections. Using command line argument for decision."
        return DEFAULT_FORCE_REDETECTION ? 'REPLACE' : 'KEEP'
    }
    return 'PROCEED'
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
    try {
        // Parse command line arguments
        def args = parseArguments()
        if (!args) {
            return
        }
        
        def modelPath = args.modelPath
        def forceRedetection = args.forceRedetection
    
        // Validate model file
        if (!validateModelFile(modelPath)) {
            return
        }
    
        // Get the current image data (already loaded by QuPath's --image parameter)
        def imageData = getCurrentImageData()
        if (imageData == null) {
            print "Error: No image is currently loaded"
            return
        }
        
        // Get the image name for better logging
        def imageName = imageData.getServer().getMetadata().getName()
        print "Processing image: ${imageName}"
    
        // Setup hierarchy and annotations
        def hierarchy = imageData.getHierarchy()
        def annotations = hierarchy.getAnnotationObjects()
    
        // Create full image annotation if none exists
        if (annotations.isEmpty()) {
            print "No annotations found. Creating full image annotation..."
            def wholeImageAnnotation = createFullImageAnnotation(imageData)
            annotations = [wholeImageAnnotation]
        } else {
            print "Found ${annotations.size()} existing annotations"
        }
        
        // Check for existing cell detections
        def existingCount = countDetections(imageData)
        def userDecision = askUserAboutExistingDetections(existingCount)
        
        if (userDecision == 'CANCEL') {
            print "Operation cancelled by user"
            return
        } else if (userDecision == 'KEEP') {
            print "Keeping ${existingCount} existing cell detections"
            print "Cell detection skipped - using existing detections"
            return
        } else if (userDecision == 'REPLACE' || forceRedetection) {
            clearExistingDetections(imageData)
        }
    
        print "Running StarDist detection on the current image..."
    
        def stardist = createStarDistModel(modelPath)
        def totalAnnotations = annotations.size()
        def processedAnnotations = 0
        def totalDetections = 0
        def startTime = System.currentTimeMillis()
    
        // Run detection on annotations
        annotations.each { annotation ->
            print "Processing annotation ${++processedAnnotations}/${totalAnnotations}: ${annotation.getName() ?: 'Unnamed'}"
            
            // Get the ROI from the annotation - this is the correct argument for StarDist
            def roi = annotation.getROI()
            
            try {
                // Use the correct method signature: detectObjects(imageData, roi)
                def detections = stardist.detectObjects(imageData, roi)
                
                // Add all detected cells to the hierarchy
                detections.each { detection ->
                    hierarchy.addObject(detection)
                    totalDetections++
                }
                
                print "Added ${detections.size()} cell detections to annotation ${annotation.getName() ?: 'Unnamed'}"
            } catch (Exception e) {
                print "Error detecting cells in annotation ${annotation.getName() ?: 'Unnamed'}: ${e.getMessage()}"
            }
        }
    
        // Calculate processing time
        def endTime = System.currentTimeMillis()
        def processingTime = (endTime - startTime) / 1000.0
        
        // Save results
        print "Finalizing detection results with $totalDetections total cells detected (took ${processingTime.round(1)} seconds)..."
        fireHierarchyUpdate()
        
        // Explicitly save to project
        saveImageData(imageData)
        
        print "Completed detection for ${imageName}."
    } catch (Exception e) {
        print "Error during cell detection: " + e.getMessage()
        e.printStackTrace()
    }
}

// Execute the main function
runCellDetection()
print "StarDist nucleus detection completed for the current image!"
