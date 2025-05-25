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

// Configuration parameters for StarDist2D cell segmentation (128-core CPU optimized)
PIXEL_SIZE = 0.23  // microns per pixel
DETECTION_THRESHOLD = 0.25
CELL_EXPANSION = 0.0
MAX_IMAGE_DIMENSION = 16384  // Larger for powerful CPU
NORMALIZATION_PERCENTILES = [0.2, 99.8]
TILE_SIZE = 1024  // Optimal CPU tile size
OVERLAP = 64  // Balanced overlap
BATCH_SIZE = 4  // Small batches for CPU but still faster
TRIDENT_TISSUE_CLASS_NAME = "Tissue (TRIDENT)"
NUCLEUS_CLASS_NAME = "Nucleus"
MODEL_PATH = "/u/trinhvq/Documents/maxencepelloux/HE/THESIS_PANK/models/he_heavy_augment.pb"

// CPU Configuration - optimized for 128-core server
USE_GPU = false
GPU_DEVICE_ID = 0
ENABLE_PARALLEL_PROCESSING = true  // Enable for 128-core beast!

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
 * Process a single image with StarDist detection (thread-safe version)
 */
def processImage(imageData, modelPath, useGpu, deviceId) {
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
        print "Error: PathClass '${TRIDENT_TISSUE_CLASS_NAME}' not found for ${imageName}. Skipping."
        return [totalDetections: 0, processingTime: 0]
    }

    // Get annotations specifically from TRIDENT
    def tridentAnnotations = hierarchy.getAnnotationObjects().findAll { it.getPathClass() == tridentTissueClass }

    if (tridentAnnotations.isEmpty()) {
        print "Warning: No TRIDENT annotations found in ${imageName}. Skipping."
        return [totalDetections: 0, processingTime: 0]
    }

    print "Found ${tridentAnnotations.size()} TRIDENT annotations in ${imageName}"
    
    def totalDetections = 0
    def detectionStartTime = System.currentTimeMillis()

    // Create thread-local StarDist model for this image
    def stardist = createStarDistModel(modelPath, useGpu, deviceId)
    print "Created StarDist model for ${imageName}"

    // Run detection on the filtered TRIDENT annotations
    tridentAnnotations.each { annotation ->
        def roi = annotation.getROI()
        def detections = stardist.detectObjects(imageData, roi)
        
        // Add all detected cells to the hierarchy
        detections.each { detection ->
            hierarchy.addObject(detection)
            totalDetections++
        }
    }

    def processingTime = System.currentTimeMillis() - detectionStartTime
    
    // Save results for this image
    fireHierarchyUpdate()
    def project = getProject()
    if (project != null) {
        def entry = project.getEntry(imageData)
        if (entry != null) {
            entry.saveImageData(imageData)
        }
    }
    
    print "Completed ${imageName}: ${totalDetections} cells detected in ${processingTime}ms"
    return [totalDetections: totalDetections, processingTime: processingTime]
}

/**
 * Main execution function for cell detection - processes ALL images in project
 */
def runCellDetection() {
    print "=== StarDist2D Cell Detection with TRUE PARALLEL Processing ==="
    
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

    // Get the project and all images
    def project = getProject()
    if (project == null) {
        print "Error: No project is currently open"
        return
    }
    
    def imageList = project.getImageList()
    if (imageList.isEmpty()) {
        print "Error: No images found in the project"
        return
    }
    
    print "Found ${imageList.size()} images in the project to process"

    try {
        def totalDetections = 0
        def totalProcessingTime = 0
        def processedImages = 0
        def pipelineStartTime = System.currentTimeMillis()

        // Process images in TRUE parallel using thread-safe approach
        print "Starting TRUE PARALLEL processing of ${imageList.size()} images..."
        print "Each image gets its own StarDist model instance for thread safety"
        
        // Use parallel processing with thread-safe model creation
        def results = imageList.parallelStream().map { entry ->
            try {
                print "=== Starting parallel processing: ${entry.getImageName()} ==="
                def imageData = entry.readImageData()
                if (imageData != null) {
                    def result = processImage(imageData, args.modelPath, args.useGpu, args.deviceId)
                    
                    // Thread-safe project saving
                    synchronized(this) {
                        def project = getProject()
                        if (project != null) {
                            def projectEntry = project.getEntry(imageData)
                            if (projectEntry != null) {
                                projectEntry.saveImageData(imageData)
                            }
                            project.syncChanges()
                            print "Project saved after processing ${entry.getImageName()}"
                        }
                    }
                    
                    print "=== Completed parallel processing: ${entry.getImageName()} - ${result.totalDetections} cells ==="
                    return result
                } else {
                    print "Warning: Could not load image data for ${entry.getImageName()}"
                    return [totalDetections: 0, processingTime: 0]
                }
            } catch (Exception e) {
                print "Error processing image ${entry.getImageName()}: ${e.getMessage()}"
                e.printStackTrace()
                return [totalDetections: 0, processingTime: 0]
            }
        }.collect()

        // Aggregate results
        results.each { result ->
            totalDetections += result.totalDetections
            totalProcessingTime += result.processingTime
            if (result.totalDetections > 0) {
                processedImages++
            }
        }

        def pipelineTotalTime = System.currentTimeMillis() - pipelineStartTime
        
        // Final project save
        project.syncChanges()
        
        // Print final results
        print "=== TRUE PARALLEL Processing Results ==="
        print "Total images processed: ${imageList.size()}"
        print "Images with detections: ${processedImages}"
        print "Total cells detected: ${totalDetections}"
        print "Total processing time: ${pipelineTotalTime}ms"
        print "Average time per image: ${(pipelineTotalTime / imageList.size()).round(0)}ms"
        if (totalDetections > 0) {
            print "Detection speed: ${(totalDetections / (pipelineTotalTime / 1000.0)).round(1)} cells/second"
        }
        
        print "TRUE PARALLEL StarDist detection completed for all images in the project."
        
    } catch (Exception e) {
        print "Error during parallel detection: " + e.getMessage()
        e.printStackTrace()
    }
}

// Execute the main function
runCellDetection()
print "StarDist nucleus detection script finished for the current image!"