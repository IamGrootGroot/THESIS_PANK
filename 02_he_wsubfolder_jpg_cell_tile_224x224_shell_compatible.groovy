/*
 * Copyright (c) 2024 Maxence PELLOUX
 * All rights reserved.
 *
 * This script is part of the PANK thesis project and implements the second step
 * of the cell segmentation pipeline, extracting 224x224 pixel patches centered
 * around detected cell centroids from H&E stained images.
 */

import qupath.lib.images.servers.ImageServer
import qupath.lib.images.writers.ImageWriterTools
import qupath.lib.regions.RegionRequest
import qupath.lib.common.GeneralTools
import qupath.lib.objects.PathAnnotationObject
import qupath.lib.images.ImageData
import qupath.lib.projects.Project
import qupath.lib.images.servers.ImageServerProvider

// Configuration parameters for patch extraction
// Declare at script level (not inside a class definition or method)
PATCH_SIZE = 224        // Size of the patches in pixels
MAGNIFICATION = 20.0    // Target magnification for the patches
OUTPUT_DIR = "/Users/maxencepelloux/PYTHON_Projects/THESIS_PANK/output/tiles"  // Base output directory

/**
 * Parse command line arguments
 * @return Map containing parsed arguments
 */
def parseArguments() {
    // No arguments needed for this version since we're using the current image
    return [:]
}

/**
 * Validates and creates the output directory structure
 * @param imageName Name of the current image
 * @return File object representing the output directory
 */
def setupOutputDirectory(String imageName) {
    def outputDir = new File(OUTPUT_DIR, imageName)
    if (!outputDir.exists()) {
        outputDir.mkdirs()
    }
    return outputDir
}

/**
 * Calculates the downsample factor based on base and desired magnification
 * @param server Current image server
 * @return double representing the downsample factor
 */
def calculateDownsample(ImageServer server) {
    def baseMagnification = server.getMetadata().getMagnification()
    if (baseMagnification == null || Double.isNaN(baseMagnification) || baseMagnification <= 0) {
        print "Base magnification unavailable or invalid. Using default = ${MAGNIFICATION}"
        baseMagnification = MAGNIFICATION
    }

    def downsample = baseMagnification / MAGNIFICATION
    if (Double.isNaN(downsample) || downsample <= 0) {
        print "Invalid downsample (${downsample}). Using 1.0 instead."
        downsample = 1.0
    }
    return downsample
}

/**
 * Main execution function for patch extraction
 */
def runPatchExtraction() {
    // No need to parse arguments - we're using the current image
    
    // Get the current image data (already loaded by QuPath's --image parameter)
    def imageData = getCurrentImageData()
    if (imageData == null) {
        print "Error: No image is currently loaded"
        return
    }
    
    // Get the image server and name
    def server = imageData.getServer()
    def imageName = GeneralTools.stripExtension(server.getMetadata().getName())
    
    // Setup output directory
    def outputDir = setupOutputDirectory(imageName)
    
    // Get image dimensions
    def imageWidth = server.getWidth()
    def imageHeight = server.getHeight()
    
    // Calculate downsample factor
    def downsample = calculateDownsample(server)
    
    // Define patch size from configuration
    def patchSize = (int)(PATCH_SIZE * downsample)
    def halfPatchSize = (int)(PATCH_SIZE / 2 * downsample)
    
    // Process annotations
    def annotations = imageData.getHierarchy().getAnnotationObjects()
    def totalROIs = annotations.size()
    def processedROIs = 0
    
    for (annotation in annotations) {
        processedROIs++
        def annotationName = annotation.getName() ?: "ROI_${annotations.indexOf(annotation) + 1}"
        
        // Create subfolder for this annotation
        def annotationOutputDir = new File(outputDir, annotationName)
        if (!annotationOutputDir.exists()) {
            annotationOutputDir.mkdirs()
        }
        
        // Process detections
        def detections = annotation.getChildObjects().findAll { it.isDetection() }
        def totalCells = detections.size()
        def processedCells = 0
        def counter = 0
        
        print "Processing ROI ${processedROIs}/${totalROIs} (${annotationName}) - ${totalCells} cells to process"
        
        for (detection in detections) {
            processedCells++
            def centroidX = (int)detection.getROI().getCentroidX()
            def centroidY = (int)detection.getROI().getCentroidY()
            
            // Calculate patch coordinates
            def x = centroidX - halfPatchSize
            def y = centroidY - halfPatchSize
            
            // Check boundaries and save patch
            if (x >= 0 && y >= 0 && x + patchSize <= imageWidth && y + patchSize <= imageHeight) {
                def region = RegionRequest.createInstance(
                    server.getPath(),
                    downsample,
                    x,
                    y,
                    patchSize,
                    patchSize
                )
                
                def outputFile = new File(
                    annotationOutputDir,
                    String.format("%s_%d_%d_%06d.jpg", annotationName, centroidX, centroidY, counter)
                )
                
                ImageWriterTools.writeImageRegion(server, region, outputFile.getAbsolutePath())
                counter++
            }
            
            // Report progress
            if (processedCells % Math.max(100, (int)(totalCells/10)) == 0 || processedCells == totalCells) {
                def progress = (processedCells / totalCells * 100).round(1)
                print "ROI ${processedROIs}/${totalROIs} - Progress: ${progress}% (${processedCells}/${totalCells} cells processed)"
            }
        }
        
        print "Total patches saved for ${annotationName}: ${counter}"
    }
    
    print "Patch extraction completed. Processed ${processedROIs} ROIs in total."
}

// Execute the main function
runPatchExtraction()
