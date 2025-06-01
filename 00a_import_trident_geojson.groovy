import qupath.lib.projects.Project
import qupath.lib.images.ImageData
import qupath.lib.common.GeneralTools
import qupath.lib.io.PathIO
import qupath.lib.objects.PathObject
import qupath.lib.objects.classes.PathClassFactory
import qupath.lib.scripting.QP // QuPath
import java.awt.Color

// Script to import TRIDENT-generated GeoJSON tissue segmentations into QuPath

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
                println "TRIDENT import: Skipping ${currentImageName} - only running once per project on first image"
                return
            }
        }
    }
}

println "TRIDENT import: Running on first image - will process entire project"

// Expected argument:
// args[0]: Absolute base path of TRIDENT's output directory 
//          (This is the directory that contains subdirectories for each slide, 
//           e.g., /path/to/trident_outputs/)

if (args.size() < 1) {
    println "Error: Missing argument. Required: <trident_base_output_dir>"
    println "  Example: qupath script 00a_import_trident_geojson.groovy --args /path/to/trident_outputs/"
    return
}

def tridentBaseOutputDirPath = args[0]
def tridentBaseOutputDir = new File(tridentBaseOutputDirPath)

if (!tridentBaseOutputDir.exists() || !tridentBaseOutputDir.isDirectory()) {
    println "Error: TRIDENT base output directory not found or is not a directory: ${tridentBaseOutputDirPath}"
    return
}

def project = getProject()
if (project == null) {
    println "Error: No QuPath project is currently open."
    return
}

println "Starting TRIDENT GeoJSON import process..."
println "Using TRIDENT output base directory: ${tridentBaseOutputDir.getAbsolutePath()}"
println "=" * 80

// =============================================================================
// Pre-import Validation and Diagnostics
// =============================================================================
println "=== PRE-IMPORT VALIDATION ==="

// Count images in QuPath project
def projectImages = project.getImageList()
def projectImageCount = projectImages.size()
println "QuPath project entries: ${projectImageCount}"

// Get list of image names from project (without extensions)
def projectImageNames = []
def failedToRead = []

projectImages.eachWithIndex { entry, index ->
    try {
        def imageData = entry.readImageData()
        def server = imageData.getServer()
        def imageNameWithExtension = server.getMetadata().getName()
        def imageNameNoExt = GeneralTools.stripExtension(imageNameWithExtension)
        projectImageNames.add(imageNameNoExt)
    } catch (Exception e) {
        def entryName = "Entry_${index}"
        try {
            // Try to get any identifying information
            entryName = entry.toString()
        } catch (Exception e2) {
            // Fallback to index if toString() also fails
        }
        failedToRead.add("${entryName}: ${e.getMessage()}")
        println "Warning: Could not read image ${index + 1}/${projectImageCount} (${entryName}): ${e.getMessage()}"
    }
}

def readableImageCount = projectImageNames.size()
def unreadableImageCount = failedToRead.size()

println "QuPath readable images: ${readableImageCount}"
if (unreadableImageCount > 0) {
    println "QuPath unreadable images: ${unreadableImageCount}"
    println "  Unreadable image details:"
    failedToRead.each { failInfo ->
        println "    - ${failInfo}"
    }
}
println "Total project entries: ${projectImageCount} = ${readableImageCount} readable + ${unreadableImageCount} unreadable"

// Count GeoJSON files in TRIDENT output
def geojsonDir = new File(tridentBaseOutputDir, "contours_geojson")
def geojsonFiles = []
def geojsonCount = 0

if (geojsonDir.exists() && geojsonDir.isDirectory()) {
    geojsonFiles = geojsonDir.listFiles().findAll { file ->
        file.isFile() && file.getName().toLowerCase().endsWith(".geojson")
    }
    geojsonCount = geojsonFiles.size()
    println "TRIDENT GeoJSON files found: ${geojsonCount}"
    println "GeoJSON directory: ${geojsonDir.getAbsolutePath()}"
} else {
    println "WARNING: TRIDENT GeoJSON directory not found: ${geojsonDir.getAbsolutePath()}"
}

// Check for discrepancies
println "\n--- VALIDATION RESULTS ---"
if (readableImageCount == geojsonCount) {
    println "✓ GOOD: Number of readable images matches GeoJSON files (${readableImageCount})"
} else {
    println "⚠ WARNING: Mismatch detected!"
    println "  Readable images: ${readableImageCount}"
    println "  GeoJSON files: ${geojsonCount}"
    println "  Difference: ${Math.abs(readableImageCount - geojsonCount)}"
    
    if (readableImageCount > geojsonCount) {
        println "  → Some readable images may not have corresponding TRIDENT segmentations"
    } else {
        println "  → Some GeoJSON files may not have corresponding readable images"
    }
    
    if (unreadableImageCount > 0) {
        println "  NOTE: ${unreadableImageCount} images in project are unreadable and excluded from comparison"
        println "        TRIDENT may have processed these images if they were accessible during segmentation"
    }
}

// Check for name matches
if (!geojsonFiles.isEmpty() && !projectImageNames.isEmpty()) {
    def geojsonNames = geojsonFiles.collect { file -> 
        GeneralTools.stripExtension(file.getName())
    }
    
    def missingInProject = geojsonNames.findAll { name -> !projectImageNames.contains(name) }
    def missingInTrident = projectImageNames.findAll { name -> !geojsonNames.contains(name) }
    
    if (missingInProject.isEmpty() && missingInTrident.isEmpty()) {
        println "✓ GOOD: All image names match between project and GeoJSON files"
    } else {
        if (!missingInProject.isEmpty()) {
            println "⚠ GeoJSON files without matching project images:"
            missingInProject.each { name -> println "  - ${name}.geojson" }
        }
        if (!missingInTrident.isEmpty()) {
            println "⚠ Project images without matching GeoJSON files:"
            missingInTrident.each { name -> println "  - ${name}" }
        }
    }
}

println "=" * 80
println "\n=== STARTING IMPORT PROCESS ==="

def importedCount = 0
def notFoundCount = 0
def errorCount = 0

project.getImageList().eachWithIndex { entry, index ->
    def imageData = entry.readImageData() // It is essential to read image data to modify it
    def server = imageData.getServer()
    def imageNameWithExtension = server.getMetadata().getName() // e.g., image1.ndpi
    def imageNameNoExt = GeneralTools.stripExtension(imageNameWithExtension)
    
    println "Processing QuPath image (${index + 1}/${project.getImageList().size()}): ${imageNameWithExtension} (stripped: ${imageNameNoExt})"

    // Construct the expected path to the GeoJSON file based on TRIDENT's actual output structure
    // TRIDENT outputs files directly in: trident_output/contours_geojson/<image_name>.geojson
    def geojsonFile = new File(tridentBaseOutputDir, "contours_geojson" + File.separator + imageNameNoExt + ".geojson")

    if (geojsonFile.exists() && geojsonFile.isFile()) {
        println "  Found corresponding GeoJSON: ${geojsonFile.getAbsolutePath()}"
        try {
            // Import GeoJSON objects using the correct PathIO method
            List<PathObject> importedObjects = PathIO.readObjects(geojsonFile.toPath())
            
            if (importedObjects.isEmpty()) {
                println "  Warning: GeoJSON file ${geojsonFile.getName()} was empty or contained no valid QuPath objects."
            } else {
                // Get or create a PathClass for the imported tissue annotations first
                def tissueClassName = "Tissue (TRIDENT)"
                def tissueColor = Color.GREEN
                def tissueClass = getPathClass(tissueClassName) // Check if class already exists
                if (tissueClass == null) {
                   tissueClass = PathClassFactory.getPathClass(tissueClassName, tissueColor)
                   addPathClass(tissueClass) // Add to the project's list of classes
                   println "    Created new PathClass: ${tissueClassName}"
                }
                
                // SYSTEMATIC CLEANUP: Always clear existing TRIDENT annotations before importing
                def existingTridentAnnotations = imageData.getHierarchy().getAnnotationObjects().findAll { 
                    it.getPathClass() == tissueClass 
                }
                
                if (!existingTridentAnnotations.isEmpty()) {
                    println "  Clearing ${existingTridentAnnotations.size()} existing TRIDENT annotations before import..."
                    imageData.getHierarchy().removeObjects(existingTridentAnnotations, true)
                } else {
                    println "  No existing TRIDENT annotations found - proceeding with fresh import"
                }
                
                // Add imported objects to the hierarchy
                imageData.getHierarchy().addObjects(importedObjects) 
                
                // Assign the PathClass to all imported objects
                importedObjects.each { pathObject ->
                    pathObject.setPathClass(tissueClass)
                }
                
                // Save the changes to the image data within the project
                entry.saveImageData(imageData)
                println "  Successfully imported ${importedObjects.size()} objects from GeoJSON for ${imageNameNoExt} and assigned class '${tissueClassName}'. Saved to project."
                importedCount++
            }
        } catch (Exception e_import) {
            println "  Error importing GeoJSON for ${imageNameNoExt}: ${e_import.getMessage()}"
            e_import.printStackTrace()
            errorCount++
        }
    } else {
        println "  Warning: Expected GeoJSON file not found for ${imageNameNoExt} at: ${geojsonFile.getAbsolutePath()}"
        notFoundCount++
    }
    println "-----------------------------------------------------"
}

// Sync all project changes at the end
project.syncChanges()
println "GeoJSON import process finished."
println "Summary:"
println "  Successfully imported annotations for: ${importedCount} images."
println "  GeoJSON files not found for: ${notFoundCount} images."
println "  Errors during import for: ${errorCount} images." 