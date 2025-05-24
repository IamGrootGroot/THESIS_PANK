import qupath.lib.projects.Project
import qupath.lib.images.ImageData
import qupath.lib.common.GeneralTools
import qupath.lib.io.PathIO
import qupath.lib.objects.PathObject
import qupath.lib.objects.classes.PathClassFactory
import qupath.lib.scripting.QP // QuPath
import java.awt.Color

// Script to import TRIDENT-generated GeoJSON tissue segmentations into QuPath

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
            // Import GeoJSON objects
            // PathIO.importGeoJSON returns a Collection<PathObject>
            Collection<PathObject> importedObjects = PathIO.importGeoJSON(geojsonFile.toPath())
            
            if (importedObjects.isEmpty()) {
                println "  Warning: GeoJSON file ${geojsonFile.getName()} was empty or contained no valid QuPath objects."
            } else {
                // Optional: Clear existing annotations of a specific type if needed before importing
                // Example: clearExistingAnnotations(imageData, PathClass.fromString("Tissue"))
                // imageData.getHierarchy().removeObjects(imageData.getHierarchy().getAnnotationObjects().findAll{it.getPathClass() == tissueClass}, true)

                // Add imported objects to the hierarchy
                imageData.getHierarchy().addObjects(importedObjects) 
                
                // Get or create a PathClass for the imported tissue annotations
                def tissueClassName = "Tissue (TRIDENT)"
                def tissueColor = Color.GREEN
                def tissueClass = getPathClass(tissueClassName) // Check if class already exists
                if (tissueClass == null) {
                   tissueClass = PathClassFactory.getPathClass(tissueClassName, tissueColor)
                   addPathClass(tissueClass) // Add to the project's list of classes
                   println "    Created new PathClass: ${tissueClassName}"
                }
                
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