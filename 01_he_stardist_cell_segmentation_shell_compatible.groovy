/*
 * Copyright (c) 2024 Maxence PELLOUX
 * All rights reserved.
 *
 * This script is part of the PANK thesis project and implements the first step
 * of the cell segmentation pipeline using StarDist2D for H&E stained images.
 * Optimized for A6000 GPU acceleration.
 */

import qupath.lib.objects.classes.PathClass
import qupath.ext.stardist.StarDist2D
import qupath.lib.images.ImageData
import qupath.lib.projects.Project
import qupath.lib.images.servers.ImageServerProvider
import qupath.lib.roi.ROIs
import qupath.lib.objects.PathObjects
import qupath.lib.regions.ImagePlane

// Configuration parameters for StarDist2D cell segmentation (RTX 6000 Ada optimized)
PIXEL_SIZE = 0.23  // microns per pixel
DETECTION_THRESHOLD = 0.25
CELL_EXPANSION = 0.0
MAX_IMAGE_DIMENSION = 20480  // Increased for RTX 6000 Ada (49GB VRAM)
NORMALIZATION_PERCENTILES = [0.2, 99.8]
TILE_SIZE = 2560  // Increased for RTX 6000 Ada
OVERLAP = 160  // Increased for RTX 6000 Ada
BATCH_SIZE = 80  // Increased for RTX 6000 Ada
TRIDENT_TISSUE_CLASS_NAME = "Tissue (TRIDENT)"
NUCLEUS_CLASS_NAME = "Nucleus"
MODEL_PATH = "/u/trinhvq/Documents/maxencepelloux/HE/THESIS_PANK/models/he_heavy_augment.pb"

// GPU Configuration - optimized for RTX 6000 Ada Generation
USE_GPU = true
GPU_DEVICE_ID = 0
ENABLE_PARALLEL_PROCESSING = true  // Enabled for RTX 6000 Ada

/**
 * Parse command line arguments
 * @return Map containing parsed arguments
 */
def parseArguments() {
    return [modelPath: MODEL_PATH, useGpu: USE_GPU, deviceId: GPU_DEVICE_ID]
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
 * Check GPU availability and print system information
 * @return boolean indicating if GPU is available
 */
def checkGpuAvailability() {
    try {
        // Try to get system properties related to CUDA
        def javaLibraryPath = System.getProperty("java.library.path")
        print "Java library path: ${javaLibraryPath}"
        
        // Check for CUDA-related environment variables
        def cudaPath = System.getenv("CUDA_PATH")
        def cudaHome = System.getenv("CUDA_HOME")
        
        if (cudaPath != null) {
            print "CUDA_PATH detected: ${cudaPath}"
        }
        if (cudaHome != null) {
            print "CUDA_HOME detected: ${cudaHome}"
        }
        
        // Check available processors for parallel processing
        def availableProcessors = Runtime.getRuntime().availableProcessors()
        print "Available processors: ${availableProcessors}"
        
        // Check memory
        def maxMemory = Runtime.getRuntime().maxMemory() / (1024 * 1024 * 1024)
        print "Maximum JVM memory: ${maxMemory.round(2)} GB"
        
        return true
    } catch (Exception e) {
        print "GPU availability check failed: ${e.getMessage()}"
        return false
    }
}

/**
 * Creates and configures the StarDist2D model with A6000 optimization
 * @param modelPath Path to the model file
 * @param useGpu Whether to use GPU acceleration
 * @param deviceId GPU device ID to use
 * @return configured StarDist2D instance
 */
def createStarDistModel(String modelPath, boolean useGpu, int deviceId) {
    print "Configuring StarDist2D model..."
    print "Model path: ${modelPath}"
    print "GPU acceleration: ${useGpu}"
    print "Device ID: ${deviceId}"
    
    try {
        def builder = StarDist2D.builder(modelPath)
            .threshold(DETECTION_THRESHOLD)
            .pixelSize(PIXEL_SIZE)
            .cellExpansion(CELL_EXPANSION)
            .tileSize(TILE_SIZE)
            .measureShape()
            .measureIntensity()
            .classify(PathClass.fromString(NUCLEUS_CLASS_NAME))
        
        // Use the newer preprocessGlobal method instead of deprecated preprocess
        try {
            builder = builder.preprocessGlobal(
                StarDist2D.imageNormalizationBuilder()
                    .maxDimension(MAX_IMAGE_DIMENSION)
                    .percentiles(NORMALIZATION_PERCENTILES[0], NORMALIZATION_PERCENTILES[1])
                    .build()
            )
            print "Using preprocessGlobal method"
        } catch (Exception e) {
            // Fallback to deprecated method if newer one is not available
            builder = builder.preprocess(
                StarDist2D.imageNormalizationBuilder()
                    .maxDimension(MAX_IMAGE_DIMENSION)
                    .percentiles(NORMALIZATION_PERCENTILES[0], NORMALIZATION_PERCENTILES[1])
                    .build()
            )
            print "Using deprecated preprocess method as fallback"
        }
        
        // Add GPU-specific configurations
        if (useGpu) {
            print "Attempting to enable GPU acceleration..."
            try {
                // Try different approaches for GPU configuration
                if (builder.hasProperty('useGPU')) {
                    builder = builder.useGPU(true)
                    print "GPU acceleration enabled via useGPU()"
                } else if (builder.hasProperty('device')) {
                    builder = builder.device("GPU:${deviceId}")
                    print "GPU device set via device() method"
                }
                
                // Enable parallel processing for A6000
                if (ENABLE_PARALLEL_PROCESSING && builder.hasProperty('parallelProcessing')) {
                    builder = builder.parallelProcessing(true)
                    print "Parallel processing enabled"
                } else {
                    print "Parallel processing disabled"
                }
                
                // Set batch size for A6000
                if (builder.hasProperty('batchSize')) {
                    builder = builder.batchSize(BATCH_SIZE)
                    print "Batch size set to: ${BATCH_SIZE}"
                }
                
                // Set tile overlap
                if (builder.hasProperty('overlap')) {
                    builder = builder.overlap(OVERLAP)
                    print "Tile overlap set to: ${OVERLAP}"
                }
                
            } catch (Exception e) {
                print "Warning: Could not configure GPU acceleration: ${e.getMessage()}"
                print "Falling back to CPU processing"
                useGpu = false
            }
        }
        
        if (!useGpu) {
            print "Using CPU processing"
        }
        
        def model = builder.build()
        print "StarDist2D model configured successfully"
        return model
        
    } catch (Exception e) {
        print "Error creating StarDist model: ${e.getMessage()}"
        e.printStackTrace()
        throw e
    }
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
    print "=== StarDist2D Cell Detection with A6000 Optimization ==="
    
    // Parse command line arguments
    def args = parseArguments()
    if (!args) {
        return
    }

    // Check GPU availability
    def gpuAvailable = checkGpuAvailability()
    print "GPU check completed. Available: ${gpuAvailable}"

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

    // Get image information
    def server = imageData.getServer()
    def imageName = server.getMetadata().getName()
    def imageWidth = server.getWidth()
    def imageHeight = server.getHeight()
    def magnification = server.getMetadata().getMagnification()
    
    print "Processing image: ${imageName}"
    print "Dimensions: ${imageWidth} x ${imageHeight}"
    print "Magnification: ${magnification}x"

    // Setup hierarchy
    def hierarchy = imageData.getHierarchy()
    
    // Get the PathClass for TRIDENT tissue annotations
    def tridentTissueClass = getPathClass(TRIDENT_TISSUE_CLASS_NAME)
    if (tridentTissueClass == null) {
        print "Error: PathClass '${TRIDENT_TISSUE_CLASS_NAME}' not found. Make sure TRIDENT GeoJSONs were imported correctly."
        return
    }
    print "Using PathClass for tissue regions: ${tridentTissueClass.getName()}"

    // Get annotations specifically from TRIDENT
    def tridentAnnotations = hierarchy.getAnnotationObjects().findAll { it.getPathClass() == tridentTissueClass }

    if (tridentAnnotations.isEmpty()) {
        print "Warning: No annotations with class '${TRIDENT_TISSUE_CLASS_NAME}' found in the current image. Skipping StarDist detection for this image."
        return
    }

    print "Found ${tridentAnnotations.size()} '${TRIDENT_TISSUE_CLASS_NAME}' annotations to process."
    
    // Calculate total tissue area for performance estimation
    def totalTissueArea = tridentAnnotations.sum { it.getROI().getArea() }
    print "Total tissue area: ${(totalTissueArea / 1000000).round(2)} mm²"

    try {
        // Create StarDist model with A6000 optimization
        def startTime = System.currentTimeMillis()
        def stardist = createStarDistModel(args.modelPath, args.useGpu, args.deviceId)
        def modelLoadTime = System.currentTimeMillis() - startTime
        print "Model loaded in ${modelLoadTime}ms"

        def totalTargetAnnotations = tridentAnnotations.size()
        def processedAnnotationsCount = 0
        def totalDetections = 0
        def detectionStartTime = System.currentTimeMillis()

        // Run detection on the filtered TRIDENT annotations
        tridentAnnotations.each { annotation ->
            processedAnnotationsCount++
            print "Processing TRIDENT annotation ${processedAnnotationsCount}/${totalTargetAnnotations}: ${annotation.getName() ?: 'Unnamed'}"
            
            def annotationStartTime = System.currentTimeMillis()
            
            // Get the ROI from the annotation
            def roi = annotation.getROI()
            def annotationArea = roi.getArea()
            
            // Use the correct method signature: detectObjects(imageData, roi)
            def detections = stardist.detectObjects(imageData, roi)
            
            // Add all detected cells to the hierarchy
            detections.each { detection ->
                hierarchy.addObject(detection)
                totalDetections++
            }
            
            def annotationTime = System.currentTimeMillis() - annotationStartTime
            def cellDensity = detections.size() / (annotationArea / 1000000) // cells per mm²
            
            print "Added ${detections.size()} cell detections (${cellDensity.round(0)} cells/mm²) in ${annotationTime}ms"
        }

        def totalDetectionTime = System.currentTimeMillis() - detectionStartTime
        def avgTimePerAnnotation = totalDetectionTime / totalTargetAnnotations
        def cellsPerSecond = totalDetections / (totalDetectionTime / 1000.0)

        if (totalDetections > 0) {
            // Save results
            print "=== Detection Results ==="
            print "Total cells detected: ${totalDetections}"
            print "Average cells per annotation: ${(totalDetections / totalTargetAnnotations).round(0)}"
            print "Total detection time: ${totalDetectionTime}ms"
            print "Average time per annotation: ${avgTimePerAnnotation.round(0)}ms"
            print "Detection speed: ${cellsPerSecond.round(1)} cells/second"
            
            fireHierarchyUpdate()
            
            // Explicitly save to project
            saveImageData(imageData)
            
            print "Completed StarDist detection for the current image."
        } else {
            print "No cells detected by StarDist within the provided TRIDENT annotations for the current image."
            saveImageData(imageData)
        }
    } catch (Exception e) {
        print "Error during detection: " + e.getMessage()
        e.printStackTrace()
    }
}

// Execute the main function
runCellDetection()
print "StarDist nucleus detection script finished for the current image!"