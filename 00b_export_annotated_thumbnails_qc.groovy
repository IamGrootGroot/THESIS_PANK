/*
 * Copyright (c) 2024 Maxence PELLOUX
 * All rights reserved.
 *
 * This script exports annotated thumbnails from QuPath for quality control.
 * It creates high-resolution thumbnails with TRIDENT tissue annotations overlaid.
 */

import qupath.lib.images.ImageData
import qupath.lib.projects.Project
import qupath.lib.common.GeneralTools
import qupath.lib.gui.images.stores.DefaultImageRegionStore
import qupath.lib.images.servers.ImageServer
import qupath.lib.regions.RegionRequest
import qupath.lib.images.writers.ImageWriterTools
import qupath.lib.objects.PathObject
import qupath.lib.gui.viewer.overlays.PathOverlay
import qupath.lib.gui.viewer.overlays.HierarchyOverlay
import qupath.fx.utils.FXUtils
import javafx.scene.image.WritableImage
import javafx.embed.swing.SwingFXUtils
import java.awt.image.BufferedImage
import javax.imageio.ImageIO
import java.awt.Graphics2D
import java.awt.Color
import java.awt.BasicStroke
import java.awt.RenderingHints

// =============================================================================
// EXECUTION GUARD - Only run once per project (not once per image)
// =============================================================================
// Check if we're running in a per-image context and only proceed for the first image
def currentImage = getCurrentImageData()
if (currentImage != null) {
    def currentImageName = currentImage.getServer().getMetadata().getName()
    def project = getProject()
    if (project != null) {
        def allImages = project.getImageList()
        if (allImages.size() > 0) {
            def firstImageName = allImages[0].readImageData().getServer().getMetadata().getName()
            if (currentImageName != firstImageName) {
                println "QC Export: Skipping ${currentImageName} - only running once per project on first image"
                return
            }
        }
    }
}

println "QC Export: Running on first image - will process entire project"

// Configuration
def QC_OUTPUT_DIR = "qc_thumbnails"
def THUMBNAIL_WIDTH = 2048  // High resolution for QC
def ANNOTATION_STROKE_WIDTH = 8.0f
def ANNOTATION_COLOR = Color.GREEN
def TRIDENT_CLASS_NAME = "Tissue (TRIDENT)"
def DEFAULT_MAX_IMAGES = -1  // Process all images by default

// Expected arguments:
// args[0]: Optional output directory path (if not provided, uses QC_OUTPUT_DIR)
// args[1]: Optional max number of images to process (if not provided or -1, processes all images)

def outputDir = QC_OUTPUT_DIR
if (args.size() > 0 && !args[0].isEmpty()) {
    outputDir = args[0]
}

def maxImages = DEFAULT_MAX_IMAGES
if (args.size() > 1 && !args[1].isEmpty()) {
    try {
        maxImages = Integer.parseInt(args[1])
        if (maxImages <= 0) {
            maxImages = DEFAULT_MAX_IMAGES  // Process all if invalid number
        }
    } catch (NumberFormatException e) {
        println "Warning: Invalid number for max images '${args[1]}', processing all images"
        maxImages = DEFAULT_MAX_IMAGES
    }
}

def outputDirectory = new File(outputDir)
if (!outputDirectory.exists()) {
    outputDirectory.mkdirs()
    println "Created QC output directory: ${outputDirectory.getAbsolutePath()}"
}

def project = getProject()
if (project == null) {
    println "Error: No QuPath project is currently open."
    return
}

// Check if this script has already been run by looking for a completion marker
def completionMarkerFile = new File(outputDirectory, ".qc_export_completed")
if (completionMarkerFile.exists()) {
    println "QC export already completed for this project. Skipping..."
    println "Delete ${completionMarkerFile.getAbsolutePath()} to re-run the export."
    return
}

// Create a lock file to prevent multiple simultaneous runs
def lockFile = new File(outputDirectory, ".qc_export_running")
if (lockFile.exists()) {
    println "QC export is already running for this project. Skipping this instance..."
    return
}

// Create lock file
try {
    lockFile.createNewFile()
    println "Created lock file: ${lockFile.getAbsolutePath()}"
} catch (Exception e) {
    println "Warning: Could not create lock file, proceeding anyway..."
}

def totalImages = project.getImageList().size()
def imagesToProcess = (maxImages > 0) ? Math.min(totalImages, maxImages) : totalImages

println "Starting QC thumbnail export process..."
println "Output directory: ${outputDirectory.getAbsolutePath()}"
println "Total images in project: ${totalImages}"
if (maxImages > 0) {
    println "Processing first ${imagesToProcess} images for QC (limited by argument)..."
} else {
    println "Processing all ${imagesToProcess} images..."
}

def exportedCount = 0
def errorCount = 0
def noAnnotationCount = 0

// Create summary file
def summaryFile = new File(outputDirectory, "qc_summary.txt")
def summaryWriter = summaryFile.newWriter()
summaryWriter.writeLine("QuPath QC Thumbnail Export Summary")
summaryWriter.writeLine("Generated: ${new Date()}")
summaryWriter.writeLine("Project: ${project.getPath()}")
summaryWriter.writeLine("Total images in project: ${totalImages}")
summaryWriter.writeLine("Images processed: ${imagesToProcess}")
if (maxImages > 0) {
    summaryWriter.writeLine("Limited by argument: ${maxImages}")
}
summaryWriter.writeLine("=" * 50)

// Process images (limited by maxImages if specified)
def imageList = (maxImages > 0) ? project.getImageList().take(maxImages) : project.getImageList()
imageList.eachWithIndex { entry, index ->
    try {
        def imageData = entry.readImageData()
        def server = imageData.getServer()
        def imageName = GeneralTools.stripExtension(server.getMetadata().getName())
        
        println "Processing (${index + 1}/${imagesToProcess}): ${imageName}"
        
        // Get TRIDENT annotations
        def hierarchy = imageData.getHierarchy()
        def tridentClass = getPathClass(TRIDENT_CLASS_NAME)
        def tridentAnnotations = []
        
        // Debug: List all annotations and their classes
        def allAnnotations = hierarchy.getAnnotationObjects()
        println "  Debug: Found ${allAnnotations.size()} total annotations"
        if (!allAnnotations.isEmpty()) {
            allAnnotations.eachWithIndex { annotation, idx ->
                def className = annotation.getPathClass()?.getName() ?: "No class"
                println "    Annotation ${idx + 1}: Class = '${className}'"
            }
        }
        
        // Try to find TRIDENT annotations with exact class name first
        if (tridentClass != null) {
            tridentAnnotations = hierarchy.getAnnotationObjects().findAll { 
                it.getPathClass() == tridentClass 
            }
            println "  Found ${tridentAnnotations.size()} annotations with exact class '${TRIDENT_CLASS_NAME}'"
        } else {
            println "  PathClass '${TRIDENT_CLASS_NAME}' not found in project"
            
            // Try to find annotations with "TRIDENT" in the name (case insensitive)
            tridentAnnotations = hierarchy.getAnnotationObjects().findAll { annotation ->
                def className = annotation.getPathClass()?.getName()
                return className != null && className.toLowerCase().contains("trident")
            }
            println "  Found ${tridentAnnotations.size()} annotations containing 'trident' in class name"
            
            // If still no TRIDENT annotations, try "Tissue" class
            if (tridentAnnotations.isEmpty()) {
                def tissueClass = getPathClass("Tissue")
                if (tissueClass != null) {
                    tridentAnnotations = hierarchy.getAnnotationObjects().findAll { 
                        it.getPathClass() == tissueClass 
                    }
                    println "  Found ${tridentAnnotations.size()} annotations with 'Tissue' class"
                }
            }
        }
        
        // Calculate downsample to achieve target width
        def downsample = server.getWidth() / THUMBNAIL_WIDTH
        if (downsample < 1) downsample = 1
        
        // Create region request for full image at lower resolution
        def region = RegionRequest.createInstance(
            server.getPath(),
            downsample,
            0, 0,
            server.getWidth(),
            server.getHeight()
        )
        
        // Read the image
        def img = server.readRegion(region)
        
        // Convert to BufferedImage if needed
        BufferedImage bufferedImg
        if (img instanceof BufferedImage) {
            bufferedImg = img
        } else {
            bufferedImg = new BufferedImage(img.getWidth(), img.getHeight(), BufferedImage.TYPE_INT_RGB)
            bufferedImg.getGraphics().drawImage(img, 0, 0, null)
        }
        
        // Draw annotations on the image
        if (!tridentAnnotations.isEmpty()) {
            def g2d = bufferedImg.createGraphics()
            g2d.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
            g2d.setColor(ANNOTATION_COLOR)
            g2d.setStroke(new BasicStroke(ANNOTATION_STROKE_WIDTH))
            
            tridentAnnotations.each { annotation ->
                def roi = annotation.getROI()
                if (roi != null) {
                    // Convert ROI coordinates to thumbnail coordinates
                    def shape = roi.getShape()
                    def transform = java.awt.geom.AffineTransform.getScaleInstance(
                        1.0/downsample, 1.0/downsample
                    )
                    def scaledShape = transform.createTransformedShape(shape)
                    
                    g2d.draw(scaledShape)
                }
            }
            g2d.dispose()
            
            summaryWriter.writeLine("✓ ${imageName}: ${tridentAnnotations.size()} TRIDENT annotations")
        } else {
            summaryWriter.writeLine("⚠ ${imageName}: No TRIDENT annotations found")
            noAnnotationCount++
        }
        
        // Save the annotated thumbnail
        def outputFile = new File(outputDirectory, "${imageName}_qc_thumbnail.jpg")
        ImageIO.write(bufferedImg, "jpg", outputFile)
        
        exportedCount++
        println "  Exported: ${outputFile.getName()}"
        
    } catch (Exception e) {
        println "  Error processing image: ${e.getMessage()}"
        summaryWriter.writeLine("✗ Error processing image: ${e.getMessage()}")
        e.printStackTrace()
        errorCount++
    }
    
    println "-----------------------------------------------------"
}

// Write summary
summaryWriter.writeLine("=" * 50)
summaryWriter.writeLine("SUMMARY:")
summaryWriter.writeLine("Total images in project: ${totalImages}")
summaryWriter.writeLine("Images processed: ${imagesToProcess}")
summaryWriter.writeLine("Successfully exported: ${exportedCount}")
summaryWriter.writeLine("Images with no annotations: ${noAnnotationCount}")
summaryWriter.writeLine("Errors encountered: ${errorCount}")
summaryWriter.close()

// Clean up lock file and create completion marker
try {
    lockFile.delete()
    println "Removed lock file"
} catch (Exception e) {
    println "Warning: Could not remove lock file: ${e.getMessage()}"
}

try {
    completionMarkerFile.createNewFile()
    println "Created completion marker: ${completionMarkerFile.getAbsolutePath()}"
} catch (Exception e) {
    println "Warning: Could not create completion marker: ${e.getMessage()}"
}

println "QC thumbnail export completed!"
println "Summary:"
println "  Total images in project: ${totalImages}"
println "  Images processed: ${imagesToProcess}"
println "  Successfully exported: ${exportedCount} thumbnails"
println "  Images with no annotations: ${noAnnotationCount}"
println "  Errors encountered: ${errorCount}"
println "  Output directory: ${outputDirectory.getAbsolutePath()}"
println "  Summary file: ${summaryFile.getAbsolutePath()}" 