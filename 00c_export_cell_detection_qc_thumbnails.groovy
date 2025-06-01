/*
 * Copyright (c) 2024 Maxence PELLOUX
 * All rights reserved.
 *
 * This script exports QC thumbnails showing both TRIDENT tissue annotations
 * and StarDist cell detections overlaid on the original images.
 * Perfect for comprehensive pipeline quality control.
 */

import qupath.lib.images.ImageData
import qupath.lib.projects.Project
import qupath.lib.common.GeneralTools
import qupath.lib.images.servers.ImageServer
import qupath.lib.regions.RegionRequest
import qupath.lib.objects.PathObject
import qupath.lib.objects.classes.PathClass
import javax.imageio.ImageIO
import java.awt.image.BufferedImage
import java.awt.Graphics2D
import java.awt.Color
import java.awt.BasicStroke
import java.awt.RenderingHints
import java.awt.geom.Ellipse2D

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
def QC_OUTPUT_DIR = "qc_cell_detection_thumbnails"
def THUMBNAIL_WIDTH = 2048  // High resolution for detailed QC
def TRIDENT_STROKE_WIDTH = 8.0f
def CELL_STROKE_WIDTH = 1.0f
def CELL_RADIUS = 3.0f  // Radius for cell detection circles
def TRIDENT_COLOR = Color.GREEN
def CELL_COLOR = Color.RED
def NUCLEUS_COLOR = Color.CYAN
def TRIDENT_CLASS_NAME = "Tissue (TRIDENT)"
def NUCLEUS_CLASS_NAME = "Nucleus"

// Expected arguments:
// args[0]: Optional output directory path (if not provided, uses QC_OUTPUT_DIR)
// args[1]: Optional number of images to process (if not provided or "all", processes all images)

def outputDir = QC_OUTPUT_DIR
if (args.size() > 0 && !args[0].isEmpty()) {
    outputDir = args[0]
}

def maxImages = -1  // -1 means process all images
if (args.size() > 1 && !args[1].isEmpty() && args[1] != "all") {
    try {
        maxImages = Integer.parseInt(args[1])
        if (maxImages <= 0) {
            println "Warning: Invalid number of images specified (${args[1]}), processing all images"
            maxImages = -1
        }
    } catch (NumberFormatException e) {
        println "Warning: Could not parse number of images (${args[1]}), processing all images"
        maxImages = -1
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

println "Starting Cell Detection QC thumbnail export process..."
println "Output directory: ${outputDirectory.getAbsolutePath()}"
def totalProjectImages = project.getImageList().size()
def imagesToProcess = (maxImages > 0 && maxImages < totalProjectImages) ? maxImages : totalProjectImages
println "Processing ${imagesToProcess} of ${totalProjectImages} images..."
if (maxImages > 0 && maxImages < totalProjectImages) {
    println "Note: Limited to first ${maxImages} images as requested"
}

def exportedCount = 0
def errorCount = 0
def noAnnotationCount = 0
def noCellsCount = 0

// Create detailed summary file
def summaryFile = new File(outputDirectory, "cell_detection_qc_summary.txt")
def summaryWriter = summaryFile.newWriter()
summaryWriter.writeLine("QuPath Cell Detection QC Thumbnail Export Summary")
summaryWriter.writeLine("Generated: ${new Date()}")
summaryWriter.writeLine("Project: ${project.getPath()}")
summaryWriter.writeLine("Legend:")
summaryWriter.writeLine("  - GREEN outlines: TRIDENT tissue annotations")
summaryWriter.writeLine("  - RED/CYAN dots: Detected cells/nuclei")
summaryWriter.writeLine("=" * 60)

def totalCellsDetected = 0
def totalTridentAnnotations = 0

project.getImageList().eachWithIndex { entry, index ->
    // Check if we've reached the maximum number of images to process
    if (maxImages > 0 && index >= maxImages) {
        println "Reached maximum number of images to process (${maxImages}), stopping..."
        return false  // This will exit the eachWithIndex closure
    }
    
    def imageName = "Unknown"  // Declare outside try block
    try {
        def imageData = entry.readImageData()
        def server = imageData.getServer()
        imageName = GeneralTools.stripExtension(server.getMetadata().getName())
        
        println "Processing (${index + 1}/${imagesToProcess}): ${imageName}"
        
        // Get hierarchy and all objects
        def hierarchy = imageData.getHierarchy()
        def tridentClass = getPathClass(TRIDENT_CLASS_NAME)
        def nucleusClass = getPathClass(NUCLEUS_CLASS_NAME)
        
        // Find TRIDENT annotations
        def tridentAnnotations = []
        if (tridentClass != null) {
            tridentAnnotations = hierarchy.getAnnotationObjects().findAll { 
                it.getPathClass() == tridentClass 
            }
        }
        
        // If no exact match, try flexible matching
        if (tridentAnnotations.isEmpty()) {
            tridentAnnotations = hierarchy.getAnnotationObjects().findAll { annotation ->
                def className = annotation.getPathClass()?.getName()
                return className != null && className.toLowerCase().contains("trident")
            }
        }
        
        // Get all cell detections (both nucleus class and unclassified detections)
        def allDetections = hierarchy.getDetectionObjects()
        def nucleusDetections = []
        def otherDetections = []
        
        allDetections.each { detection ->
            if (detection.getPathClass() == nucleusClass) {
                nucleusDetections.add(detection)
            } else {
                otherDetections.add(detection)
            }
        }
        
        def totalDetections = allDetections.size()
        totalCellsDetected += totalDetections
        totalTridentAnnotations += tridentAnnotations.size()
        
        println "  Found ${tridentAnnotations.size()} TRIDENT annotations"
        println "  Found ${totalDetections} cell detections (${nucleusDetections.size()} nucleus, ${otherDetections.size()} other)"
        
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
        
        // Draw overlays on the image
        def g2d = bufferedImg.createGraphics()
        g2d.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        
        // Draw TRIDENT annotations first (as background)
        if (!tridentAnnotations.isEmpty()) {
            g2d.setColor(TRIDENT_COLOR)
            g2d.setStroke(new BasicStroke(TRIDENT_STROKE_WIDTH))
            
            tridentAnnotations.each { annotation ->
                def roi = annotation.getROI()
                if (roi != null) {
                    def shape = roi.getShape()
                    def transform = java.awt.geom.AffineTransform.getScaleInstance(
                        1.0/downsample, 1.0/downsample
                    )
                    def scaledShape = transform.createTransformedShape(shape)
                    g2d.draw(scaledShape)
                }
            }
        }
        
        // Draw cell detections as small circles
        if (!allDetections.isEmpty()) {
            g2d.setStroke(new BasicStroke(CELL_STROKE_WIDTH))
            
            // Draw nucleus detections in cyan
            g2d.setColor(NUCLEUS_COLOR)
            nucleusDetections.each { detection ->
                def roi = detection.getROI()
                if (roi != null) {
                    def centroidX = roi.getCentroidX()
                    def centroidY = roi.getCentroidY()
                    def x = (centroidX / downsample) - CELL_RADIUS
                    def y = (centroidY / downsample) - CELL_RADIUS
                    def circle = new Ellipse2D.Double(x, y, CELL_RADIUS * 2, CELL_RADIUS * 2)
                    g2d.fill(circle)
                }
            }
            
            // Draw other detections in red
            g2d.setColor(CELL_COLOR)
            otherDetections.each { detection ->
                def roi = detection.getROI()
                if (roi != null) {
                    def centroidX = roi.getCentroidX()
                    def centroidY = roi.getCentroidY()
                    def x = (centroidX / downsample) - CELL_RADIUS
                    def y = (centroidY / downsample) - CELL_RADIUS
                    def circle = new Ellipse2D.Double(x, y, CELL_RADIUS * 2, CELL_RADIUS * 2)
                    g2d.fill(circle)
                }
            }
        }
        
        g2d.dispose()
        
        // Write summary information
        def status = ""
        if (tridentAnnotations.isEmpty()) {
            status += "⚠ No TRIDENT annotations; "
            noAnnotationCount++
        } else {
            status += "✓ ${tridentAnnotations.size()} TRIDENT annotations; "
        }
        
        if (totalDetections == 0) {
            status += "⚠ No cell detections"
            noCellsCount++
        } else {
            status += "✓ ${totalDetections} cells detected"
        }
        
        summaryWriter.writeLine("${imageName}: ${status}")
        
        // Save the annotated thumbnail
        def outputFile = new File(outputDirectory, "${imageName}_cell_detection_qc.jpg")
        ImageIO.write(bufferedImg, "jpg", outputFile)
        
        exportedCount++
        println "  Exported: ${outputFile.getName()}"
        
    } catch (Exception e) {
        println "  Error processing image: ${e.getMessage()}"
        summaryWriter.writeLine("✗ ${imageName}: Error - ${e.getMessage()}")
        e.printStackTrace()
        errorCount++
    }
    
    println "-----------------------------------------------------"
}

// Write comprehensive summary
summaryWriter.writeLine("=" * 60)
summaryWriter.writeLine("COMPREHENSIVE SUMMARY:")
summaryWriter.writeLine("Total images in project: ${totalProjectImages}")
summaryWriter.writeLine("Images processed: ${exportedCount + errorCount}")
if (maxImages > 0 && maxImages < totalProjectImages) {
    summaryWriter.writeLine("Note: Processing limited to first ${maxImages} images")
}
summaryWriter.writeLine("Successfully exported: ${exportedCount}")
summaryWriter.writeLine("Images with no TRIDENT annotations: ${noAnnotationCount}")
summaryWriter.writeLine("Images with no cell detections: ${noCellsCount}")
summaryWriter.writeLine("Errors encountered: ${errorCount}")
summaryWriter.writeLine("")
summaryWriter.writeLine("DETECTION STATISTICS:")
summaryWriter.writeLine("Total TRIDENT annotations: ${totalTridentAnnotations}")
summaryWriter.writeLine("Total cells detected: ${totalCellsDetected}")
def processedImages = exportedCount + errorCount
if (processedImages > 0) {
    def avgCellsPerImage = totalCellsDetected / processedImages
    summaryWriter.writeLine("Average cells per processed image: ${avgCellsPerImage.round(1)}")
}
summaryWriter.writeLine("")
summaryWriter.writeLine("COLOR LEGEND:")
summaryWriter.writeLine("GREEN outlines = TRIDENT tissue annotations")
summaryWriter.writeLine("CYAN dots = Nucleus class detections")
summaryWriter.writeLine("RED dots = Other cell detections")
summaryWriter.close()

println "Cell Detection QC thumbnail export completed!"
println "Summary:"
println "  Total images in project: ${totalProjectImages}"
if (maxImages > 0 && maxImages < totalProjectImages) {
    println "  Images processed (limited): ${exportedCount + errorCount} of ${totalProjectImages}"
} else {
    println "  Images processed: ${exportedCount + errorCount}"
}
println "  Successfully exported: ${exportedCount} thumbnails"
println "  Images with no TRIDENT annotations: ${noAnnotationCount}"
println "  Images with no cell detections: ${noCellsCount}"
println "  Errors encountered: ${errorCount}"
println "  Total cells detected across processed images: ${totalCellsDetected}"
println "  Output directory: ${outputDirectory.getAbsolutePath()}"
println "  Summary file: ${summaryFile.getAbsolutePath()}" 