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

// Configuration
def QC_OUTPUT_DIR = "qc_thumbnails"
def THUMBNAIL_WIDTH = 2048  // High resolution for QC
def ANNOTATION_STROKE_WIDTH = 8.0f
def ANNOTATION_COLOR = Color.GREEN
def TRIDENT_CLASS_NAME = "Tissue (TRIDENT)"

// Expected argument:
// args[0]: Optional output directory path (if not provided, uses QC_OUTPUT_DIR)

def outputDir = QC_OUTPUT_DIR
if (args.size() > 0 && !args[0].isEmpty()) {
    outputDir = args[0]
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

println "Starting QC thumbnail export process..."
println "Output directory: ${outputDirectory.getAbsolutePath()}"
println "Processing ${project.getImageList().size()} images..."

def exportedCount = 0
def errorCount = 0
def noAnnotationCount = 0

// Create summary file
def summaryFile = new File(outputDirectory, "qc_summary.txt")
def summaryWriter = summaryFile.newWriter()
summaryWriter.writeLine("QuPath QC Thumbnail Export Summary")
summaryWriter.writeLine("Generated: ${new Date()}")
summaryWriter.writeLine("Project: ${project.getPath()}")
summaryWriter.writeLine("=" * 50)

project.getImageList().eachWithIndex { entry, index ->
    try {
        def imageData = entry.readImageData()
        def server = imageData.getServer()
        def imageName = GeneralTools.stripExtension(server.getMetadata().getName())
        
        println "Processing (${index + 1}/${project.getImageList().size()}): ${imageName}"
        
        // Get TRIDENT annotations
        def hierarchy = imageData.getHierarchy()
        def tridentClass = getPathClass(TRIDENT_CLASS_NAME)
        def tridentAnnotations = []
        
        if (tridentClass != null) {
            tridentAnnotations = hierarchy.getAnnotationObjects().findAll { 
                it.getPathClass() == tridentClass 
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
                    def scaledShape = new java.awt.geom.AffineTransform.getScaleInstance(
                        1.0/downsample, 1.0/downsample
                    ).createTransformedShape(shape)
                    
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
summaryWriter.writeLine("Total images processed: ${project.getImageList().size()}")
summaryWriter.writeLine("Successfully exported: ${exportedCount}")
summaryWriter.writeLine("Images with no annotations: ${noAnnotationCount}")
summaryWriter.writeLine("Errors encountered: ${errorCount}")
summaryWriter.close()

println "QC thumbnail export completed!"
println "Summary:"
println "  Successfully exported: ${exportedCount} thumbnails"
println "  Images with no annotations: ${noAnnotationCount}"
println "  Errors encountered: ${errorCount}"
println "  Output directory: ${outputDirectory.getAbsolutePath()}"
println "  Summary file: ${summaryFile.getAbsolutePath()}" 