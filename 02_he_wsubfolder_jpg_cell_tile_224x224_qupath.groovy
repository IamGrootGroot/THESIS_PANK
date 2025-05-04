// Patch extraction script for QuPath 0.5.1
// Extracts 224x224 px patches centered around detected cell centroids
// Saves patches in subfolders named after each ROI in the specified output directory
// Updated to save patches with format: <annotation_name>_<centroidX>_<centroidY>_<counter>.jpg

import qupath.lib.images.servers.ImageServer
import qupath.lib.images.writers.ImageWriterTools
import qupath.lib.regions.RegionRequest
import qupath.lib.common.GeneralTools
import qupath.lib.objects.PathAnnotationObject

// Define configuration variables directly in the script
def TILES_OUTPUT = new File("/Users/maxencepelloux/PYTHON_Projects/THESIS_PANK/output/tiles")  // Base output directory
def PATCH_SIZE = 224  // Size of the patches in pixels
def MAGNIFICATION = 20.0  // Target magnification for the patches

// Get current image server and name
def server = getCurrentServer()
def imageName = GeneralTools.stripExtension(server.getMetadata().getName())

// Create output directory structure
def outputDir = new File(TILES_OUTPUT, imageName)  // Create folder for current image
if (!outputDir.exists()) {
    outputDir.mkdirs()
}

// Get image dimensions
def imageWidth = server.getWidth()
def imageHeight = server.getHeight()

// Retrieve base magnification and calculate downsample factor
def baseMagnification = server.getMetadata().getMagnification()
if (baseMagnification == null || Double.isNaN(baseMagnification) || baseMagnification <= 0) {
    print "Base magnification unavailable or invalid. Using default = ${MAGNIFICATION}"
    baseMagnification = MAGNIFICATION
}

def desiredMagnification = MAGNIFICATION
def downsample = baseMagnification / desiredMagnification
if (Double.isNaN(downsample) || downsample <= 0) {
    print "Invalid downsample (${downsample}). Using 1.0 instead."
    downsample = 1.0
}

// Define patch size from configuration
def patchSize = (int)(PATCH_SIZE * downsample)
def halfPatchSize = (int)(PATCH_SIZE / 2 * downsample)

// Loop over each annotation (ROI)
def annotations = getAnnotationObjects()
def totalROIs = annotations.size()
def processedROIs = 0

for (annotation in annotations) {
    processedROIs++
    // Get annotation name (if available)
    def annotationName = annotation.getName()
    if (annotationName == null || annotationName.isEmpty()) {
        annotationName = "ROI_${annotations.indexOf(annotation) + 1}"
    }

    // Create subfolder for this annotation (ROI) under the image folder
    def annotationOutputDir = new File(outputDir, annotationName)
    if (!annotationOutputDir.exists()) {
        annotationOutputDir.mkdirs()
    }

    // Get detections (cells) within the current annotation
    def detections = annotation.getChildObjects().findAll { it.isDetection() }
    def totalCells = detections.size()
    def processedCells = 0
    def counter = 0

    print "Processing ROI ${processedROIs}/${totalROIs} (${annotationName}) - ${totalCells} cells to process"

    // Iterate over each detected cell
    for (detection in detections) {
        processedCells++
        // Get centroid coordinates
        def centroidX = detection.getROI().getCentroidX()
        def centroidY = detection.getROI().getCentroidY()

        // Convert to integers
        def centroidX_int = (int) centroidX
        def centroidY_int = (int) centroidY

        // Calculate top-left coordinates of the patch
        def x = centroidX_int - halfPatchSize
        def y = centroidY_int - halfPatchSize

        // Check if the patch is within image boundaries
        if (x >= 0 && y >= 0 && x + patchSize <= imageWidth && y + patchSize <= imageHeight) {
            // Create a region request for the patch
            def region = RegionRequest.createInstance(
                server.getPath(),
                downsample,
                x,
                y,
                patchSize,
                patchSize
            )

            // Define output file with NEW requested naming format: <annotation_name>_<centroidX>_<centroidY>_<counter>.jpg
            def outputFile = new File(
                annotationOutputDir,
                String.format("%s_%d_%d_%06d.jpg", annotationName, centroidX_int, centroidY_int, counter)
            )

            // Save the image patch
            ImageWriterTools.writeImageRegion(
                server,
                region,
                outputFile.getAbsolutePath()
            )

            // Increment patch counter
            counter++
        } else {
            print "Patch at (${x}, ${y}) is out of bounds for annotation ${annotationName} and will be skipped."
        }

        // Print progress every 10% or at least every 100 cells
        if (processedCells % Math.max(100, (int)(totalCells/10)) == 0 || processedCells == totalCells) {
            def progress = (processedCells / totalCells * 100).round(1)
            print "ROI ${processedROIs}/${totalROIs} - Progress: ${progress}% (${processedCells}/${totalCells} cells processed)"
        }
    }

    // Print total patches saved for this ROI
    print "Total patches saved for ${annotationName}: ${counter}"
}

// Print completion message
print "Patch extraction completed. Processed ${processedROIs} ROIs in total."
