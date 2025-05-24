#!/bin/bash

# Enhanced pipeline script that includes StarDist in classpath
STARDIST_JAR="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build/qupath/build/dist/QuPath/lib/app/qupath-extension-stardist-0.6.0-rc1.jar"
QUPATH_CLASSPATH="$STARDIST_JAR:/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build/qupath/build/dist/QuPath/lib/app/*"

# Your original pipeline logic, but using java -cp instead of $QUPATH_PATH
# Fixed argument format: space-separated arguments
java -cp "$QUPATH_CLASSPATH" qupath.QuPath script \
  --project="$1" \
  --args="model=$2 gpu=true device=0" \
  ./THESIS_PANK/01_he_stardist_cell_segmentation_shell_compatible.groovy

echo "Waiting for project save..."
sleep 5

java -cp "$QUPATH_CLASSPATH" qupath.QuPath script \
  --project="$1" \
  ./THESIS_PANK/02_he_wsubfolder_jpg_cell_tile_224x224_shell_compatible.groovy

echo "Pipeline completed with StarDist!" 