// Patchifier using cell centroids (cf. 01): single patch image in .jpg (or other) by cell centroid with adjustable patch size with distinct subfolders by original ROI
// note: patch images touching the borders of the ROI are excluded (see below)
// by A.Khellaf (updated 2025-01)

// Import necessary QuPath classes
import qupath.lib.images.servers.ImageServer
import qupath.lib.images.writers.ImageWriterTools
import qupath.lib.regions.RegionRequest
import qupath.lib.common.GeneralTools

// Get the current image server
def server = getCurrentServer()

// Get the image name without extension
def imageName = GeneralTools.stripExtension(server.getMetadata().getName())

// Define the base output directory
def outputPath = "C:/Users/LA0122630/Documents/Khellaf_Kassab_Brassard_UniClusteringColon/5_ROI_patches"   // Replace with your desired base path

// Create the base output directory if it doesn't exist
def outputDir = new File(outputPath)
if (!outputDir.exists()) {
    outputDir.mkdirs()
}

// Create a subfolder named after the image
def imageOutputDir = new File(outputDir, imageName)
if (!imageOutputDir.exists()) {
    imageOutputDir.mkdirs()
}

// Get all detected cells
def detections = getDetectionObjects()

// Get image dimensions
def imageWidth = server.getWidth()
def imageHeight = server.getHeight()

// Initialize a counter
def counter = 0

// Safely get base magnification (avoid NaN or 0 if missing)
def baseMagnification = server.getMetadata().getMagnification()
if (baseMagnification == null || Double.isNaN(baseMagnification) || baseMagnification <= 0) {
    print 'Base magnification not available (or invalid). Using downsample = 1.0'
    baseMagnification = 40.0  // Fallback
}

// Desired magnification
def desiredMagnification = 40.0

// Calculate downsample factor (ensure it isn't zero or NaN)
def downsample = baseMagnification / desiredMagnification
if (Double.isNaN(downsample) || downsample <= 0) {
    print "Invalid downsample (${downsample}). Using 1.0 instead."
    downsample = 1.0
}

// Iterate over each detected cell
for (detection in detections) {
    // Get centroid coordinates
    def centroidX = detection.getROI().getCentroidX()
    def centroidY = detection.getROI().getCentroidY()
    
    // Convert to integers
    def centroidX_int = (int) centroidX
    def centroidY_int = (int) centroidY
    
    // Calculate top-left coordinates
    def x = centroidX_int - (int)(112 * downsample) // EDIT (1/2) SIZE here: should be 0.5 * patchSize (e.g. 112 = 0.5*224)
    def y = centroidY_int - (int)(112 * downsample) // EDIT (1/2) SIZE as above 
    def patchSize = (int)(224 * downsample) // EDIT as needed: full patch size in px
    
    // Check boundaries
    if (x >= 0 && y >= 0 && x + patchSize <= imageWidth && y + patchSize <= imageHeight) {
        // Create a region request
        def region = RegionRequest.createInstance(
            server.getPath(),
            downsample,
            x,
            y,
            patchSize,
            patchSize
        )
        
        // Define output file (JPG or OME-TIFF)
        def outputFile = new File(
            imageOutputDir, 
            String.format("%s_%d_%d_%06d.jpg", imageName, centroidX_int, centroidY_int, counter) // format of the output patch image
        )
        
        // Write the image region
        ImageWriterTools.writeImageRegion(
        
            server,
            region,
            outputFile.getAbsolutePath()
        )
        
        // Increment counter
        counter++
    } else {
        print "Patch at (${x}, ${y}) is out of bounds and will be skipped."
    }
}

// Print total patches saved
print "Total patches saved: ${counter}"
