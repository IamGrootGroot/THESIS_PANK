// Cell segmentation annotations using StarDist2D implementation in QuPath and its pretrained H&E heavy model
// by A.Khellaf (updated 2025-01)
// createFullImageAnnotation(true)

import qupath.lib.gui.dialogs.Dialogs
import qupath.ext.stardist.StarDist2D

def modelPath = System.getProperty("MODEL_PATH") ?: 
               System.getenv("MODEL_PATH") ?: 
               "./models/he_heavy_augment.pb"

def stardist = StarDist2D.builder(modelPath)
      .threshold(0.25)              // Prediction threshold
      .preprocess(                 // Apply normalization - calculating values across the whole image
        StarDist2D.imageNormalizationBuilder()
            .maxDimension(8000)    // Figure out how much to downsample large images to make sure the width & height are <= this value
            .percentiles(1, 99.8)   // Calculate image percentiles to use for normalization; already semi-optimized (update: 2025-01)
            .build()
	)
      .pixelSize(0.23)              // Resolution of the slide for detection; here 0.23um per pixel
      .build()

// Run detection for the selected objects
def imageData = getCurrentImageData()
def pathObjects = getSelectedObjects()
if (pathObjects.isEmpty()) {
    Dialogs.showErrorMessage("StarDist", "Please select a parent object!")
    return
}
stardist.detectObjects(imageData, pathObjects)
println 'Done!'