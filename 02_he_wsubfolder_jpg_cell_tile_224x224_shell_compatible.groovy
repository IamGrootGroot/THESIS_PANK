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
import qupath.lib.objects.PathObject
import qupath.lib.objects.PathDetectionObject
import qupath.lib.images.ImageData
import qupath.lib.projects.Project
import qupath.lib.images.servers.ImageServerProvider
import javax.swing.JOptionPane
import qupath.lib.gui.dialogs.Dialogs

// Configuration parameters for patch extraction
// Declare at script level (not inside a class definition or method)
PATCH_SIZE = 224        // Size of the patches in pixels
MAGNIFICATION = 20.0    // Target magnification for the patches
OUTPUT_DIR = "/Users/maxencepelloux/PYTHON_Projects/THESIS_PANK/output/tiles"  // Base output directory
DEFAULT_FORCE_REGENERATION = false  // Change to true to force tile regeneration

/**
 * Parse command line arguments
 * @return Map containing parsed arguments
 */
def parseArguments() {
    def args = args ?: []
    def params = [
        forceRegeneration: DEFAULT_FORCE_REGENERATION,
        outputDir: OUTPUT_DIR
    ]
    
    args.each { arg ->
        if (arg == "force=true") {
            params.forceRegeneration = true
        } else if (arg.startsWith("output=")) {
            params.outputDir = arg.substring(7)
        }
    }
    
    return params
}

/**
 * Validates and creates the output directory structure
 * @param imageName Name of the current image
 * @param baseOutputDir Base output directory
 * @return File object representing the output directory
 */
def setupOutputDirectory(String imageName, String baseOutputDir) {
    def outputDir = new File(baseOutputDir, imageName)
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
 * Gets all detections in the hierarchy
 * @param imageData The image data containing the hierarchy
 * @return List of detection objects
 */
def getAllDetections(imageData) {
    def hierarchy = imageData.getHierarchy()
    // Use the correct method to get all detections from the hierarchy
    return hierarchy.getDetectionObjects()
}

/**
 * Checks if the output directory already contains tiles
 * @param outputDir Directory to check for existing tiles
 * @return boolean indicating if tiles already exist and count
 */
def checkExistingTiles(File outputDir) {
    def allCellsDir = new File(outputDir, "all_cells")
    if (!allCellsDir.exists()) {
        return [exists: false, count: 0]
    }
    
    def tileCount = allCellsDir.listFiles().findAll { it.name.endsWith('.jpg') }.size()
    return [exists: tileCount > 0, count: tileCount]
}

/**
 * Clears all existing tiles from the directory
 * @param outputDir Directory containing tiles to clear
 * @return int number of files removed
 */
def clearExistingTiles(File outputDir) {
    def allCellsDir = new File(outputDir, "all_cells")
    if (!allCellsDir.exists()) {
        return 0
    }
    
    def tileFiles = allCellsDir.listFiles().findAll { it.name.endsWith('.jpg') }
    def count = tileFiles.size()
    
    if (count > 0) {
        tileFiles.each { it.delete() }
        print "Deleted ${count} existing tile files"
    }
    
    return count
}

/**
 * Gets a decision from the user for how to handle existing tiles
 * @param existingTileInfo Map with exists and count properties
 * @param forceRegeneration Whether to force regeneration from command line args
 * @return String indicating the user's choice ('REGENERATE', 'KEEP', 'CANCEL')
 */
def askUserAboutExistingTiles(Map existingTileInfo, boolean forceRegeneration) {
    // In a headless context, we can't show dialog boxes, so return based on force parameter
    if (existingTileInfo.exists) {
        print "Found ${existingTileInfo.count} existing tile images. Using command line argument for decision."
        return forceRegeneration ? 'REGENERATE' : 'KEEP'
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
 * Main execution function for patch extraction
 */
def runPatchExtraction() {
    try {
        // Parse arguments
        def params = parseArguments()
        def forceRegeneration = params.forceRegeneration
        def baseOutputDir = params.outputDir
        
        // Get the current image data (already loaded by QuPath's --image parameter)
        def imageData = getCurrentImageData()
        if (imageData == null) {
            print "Error: No image is currently loaded"
            return
        }
        
        // Get the image server and name
        def server = imageData.getServer()
        def imageName = GeneralTools.stripExtension(server.getMetadata().getName())
        print "Processing image: ${imageName}"
        
        // Setup output directory
        def outputDir = setupOutputDirectory(imageName, baseOutputDir)
        
        // Check for existing tiles
        def existingTileInfo = checkExistingTiles(outputDir)
        if (existingTileInfo.exists) {
            def userDecision = askUserAboutExistingTiles(existingTileInfo, forceRegeneration)
            
            if (userDecision == 'CANCEL') {
                print "Operation cancelled by user"
                return
            } else if (userDecision == 'KEEP') {
                print "Keeping ${existingTileInfo.count} existing tiles"
                print "Tile extraction skipped - using existing tiles"
                return
            } else if (userDecision == 'REGENERATE') {
                clearExistingTiles(outputDir)
            }
        }
        
        // Get image dimensions
        def imageWidth = server.getWidth()
        def imageHeight = server.getHeight()
        
        // Calculate downsample factor
        def downsample = calculateDownsample(server)
        
        // Define patch size from configuration
        def patchSize = (int)(PATCH_SIZE * downsample)
        def halfPatchSize = (int)(PATCH_SIZE / 2 * downsample)
        
        // Get all detections directly (rather than through annotations)
        def detections = getAllDetections(imageData)
        def totalCells = detections.size()
        
        if (totalCells == 0) {
            print "Error: No cell detections found in the image. Please run the cell detection script first."
            return
        }
        
        print "Found ${totalCells} cell detections in the image"
        
        // Process each detection
        def processedCells = 0
        def counter = 0
        def failedExtractions = 0
        def startTime = System.currentTimeMillis()
        
        // Create a default folder for all cells
        def cellsOutputDir = new File(outputDir, "all_cells")
        if (!cellsOutputDir.exists()) {
            cellsOutputDir.mkdirs()
        }
        
        for (detection in detections) {
            processedCells++
            try {
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
                        cellsOutputDir,
                        String.format("cell_%d_%d_%06d.jpg", centroidX, centroidY, counter)
                    )
                    
                    ImageWriterTools.writeImageRegion(server, region, outputFile.getAbsolutePath())
                    counter++
                } else {
                    // Skip cells at image boundaries
                    failedExtractions++
                }
            } catch (Exception e) {
                print "Error extracting tile from cell ${processedCells}: ${e.getMessage()}"
                failedExtractions++
            }
            
            // Report progress
            if (processedCells % Math.max(100, (int)(totalCells/10)) == 0 || processedCells == totalCells) {
                def progress = (processedCells / totalCells * 100).round(1)
                print "Progress: ${progress}% (${processedCells}/${totalCells} cells processed)"
            }
        }
        
        // Calculate processing time
        def endTime = System.currentTimeMillis()
        def processingTime = (endTime - startTime) / 1000.0
        
        // Save any changes to the project
        saveImageData(imageData)
        
        if (counter > 0) {
            print "Patch extraction completed in ${processingTime.round(1)} seconds."
            print "Extracted ${counter} patches from ${totalCells} detected cells."
            if (failedExtractions > 0) {
                print "Note: ${failedExtractions} cells were skipped (likely at image boundaries)."
            }
        } else {
            print "Patch extraction completed but no patches were extracted. Please check that cell detection was successful."
        }
    } catch (Exception e) {
        print "Error during tile extraction: " + e.getMessage()
        e.printStackTrace()
    }
}

// Execute the main function
runPatchExtraction()
