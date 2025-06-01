#!/bin/bash

# =============================================================================
# PANK Thesis Project - TRIDENT GeoJSON Import Pipeline
# Copyright (c) 2024 Maxence PELLOUX
# All rights reserved.
#
# This script automates the import of TRIDENT-generated GeoJSON tissue 
# segmentations into QuPath projects.
# =============================================================================

# =============================================================================
# Default QuPath Configuration
# =============================================================================
# QuPath installation paths (same as unified pipeline)
QUPATH_051_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_gpu_build_0.5.1/qupath/build/dist/QuPath/bin/QuPath"
QUPATH_06_PATH="/u/trinhvq/Documents/maxencepelloux/qupath_cpu_build_0.6.0/qupath/build/dist/QuPath/bin/QuPath"

# =============================================================================
# Help Function
# =============================================================================
show_help() {
    echo -e "\033[1;35mUsage: $0 [OPTIONS]\033[0m"
    echo
    echo "Options:"
    echo "  -t, --trident PATH    Path to TRIDENT output base directory"
    echo "  -p, --project PATH    Path to QuPath project directory or .qpproj file"
    echo "  -q, --qupath PATH     Path to QuPath executable (optional)"
    echo "  -a, --all             Process all QuPath projects in current directory"
    echo "  -s, --test            Process only the test project (QuPath_MP_PDAC5)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -t ./trident_output/contours_geoJSON -s                    # Test project only"
    echo "  $0 -t ./trident_output/contours_geoJSON -p QuPath_MP_PDAC100  # Project directory"
    echo "  $0 -t ./trident_output/contours_geoJSON -p QuPath_MP_PDAC100/project.qpproj  # Project file"
    echo "  $0 -t ./trident_output/contours_geoJSON -a                    # All projects"
    echo "  $0 -t ./trident_output -q /path/to/QuPath -p project_dir      # Custom QuPath"
    echo
    echo "Note: TRIDENT output directory is required."
    echo "      Project path can be either directory (auto-appends /project.qpproj) or .qpproj file."
    echo "      If QuPath path not specified, uses default from script configuration."
    exit 1
}

# =============================================================================
# Logging Configuration
# =============================================================================
# Create timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/trident_import_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/trident_import_${TIMESTAMP}_error.log"
QUPATH_LOG="${LOG_DIR}/qupath_trident_${TIMESTAMP}.log"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# =============================================================================
# Script Path Configuration
# =============================================================================
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROOVY_SCRIPT="$SCRIPT_DIR/00a_import_trident_geojson.groovy"

# Validate Groovy script exists
if [ ! -f "$GROOVY_SCRIPT" ]; then
    echo "ERROR: Groovy script not found at $GROOVY_SCRIPT"
    exit 1
fi

# =============================================================================
# Logging Functions
# =============================================================================
# Function to log normal messages with timestamp and terminal output
log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;32m$1\033[0m" | tee -a "$LOG_FILE"
}

# Function to log error messages with timestamp and terminal output
error_log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;31mERROR: $1\033[0m" | tee -a "$LOG_FILE" "$ERROR_LOG"
}

# Function to log warning messages with timestamp and terminal output
warn_log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m \033[1;33mWARNING: $1\033[0m" | tee -a "$LOG_FILE"
}

# Function to display progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    # Ensure values are within range to avoid printf errors
    if [ "$completed" -lt 0 ]; then completed=0; fi
    if [ "$remaining" -lt 0 ]; then remaining=0; fi
    
    printf "\r\033[1;33mProgress: [%s%s] %d%%\033[0m" \
           "$(printf '%0.s#' $(seq 1 $completed))" \
           "$(printf '%0.s-' $(seq 1 $remaining))" \
           "$percentage"
}

# =============================================================================
# QuPath Auto-Detection Functions (from unified pipeline)
# =============================================================================
check_cuda_availability() {
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            return 0
        fi
    fi
    return 1
}

determine_optimal_qupath() {
    local cuda_available=false
    local qupath_051_available=false
    local qupath_06_available=false
    
    # Check CUDA availability
    if check_cuda_availability; then
        cuda_available=true
    fi
    
    # Check QuPath installations
    if [ -f "$QUPATH_051_PATH" ] && [ -x "$QUPATH_051_PATH" ]; then
        qupath_051_available=true
    fi
    
    if [ -f "$QUPATH_06_PATH" ] && [ -x "$QUPATH_06_PATH" ]; then
        qupath_06_available=true
    fi
    
    # Decision logic (prefer 0.5.1 when available)
    if [ "$qupath_051_available" = true ]; then
        echo "$QUPATH_051_PATH"
        if [ "$cuda_available" = true ]; then
            log "Auto-selected QuPath 0.5.1 (CUDA available for optimal performance)" >&2
        else
            log "Auto-selected QuPath 0.5.1 (preferred version)" >&2
        fi
    elif [ "$qupath_06_available" = true ]; then
        echo "$QUPATH_06_PATH"
        log "Auto-selected QuPath 0.6 (0.5.1 not available)" >&2
    else
        error_log "No suitable QuPath installation found" >&2
        return 1
    fi
}

# Redirect all output to log files while maintaining terminal output
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" "$ERROR_LOG" >&2)

# =============================================================================
# Command Line Argument Parsing
# =============================================================================
# Initialize variables
TRIDENT_DIR=""
PROJECT_PATH=""
CUSTOM_QUPATH_PATH=""
PROCESS_ALL=false
TEST_ONLY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--trident)
            TRIDENT_DIR="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        -q|--qupath)
            CUSTOM_QUPATH_PATH="$2"
            shift 2
            ;;
        -a|--all)
            PROCESS_ALL=true
            shift
            ;;
        -s|--test)
            TEST_ONLY=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            error_log "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate required arguments
if [ -z "$TRIDENT_DIR" ]; then
    error_log "Missing required TRIDENT output directory"
    show_help
fi

# Check that only one processing mode is selected
mode_count=0
[ "$PROCESS_ALL" = true ] && ((mode_count++))
[ "$TEST_ONLY" = true ] && ((mode_count++))
[ -n "$PROJECT_PATH" ] && ((mode_count++))

if [ "$mode_count" -ne 1 ]; then
    error_log "Please specify exactly one processing mode: --all, --test, or --project"
    show_help
fi

# =============================================================================
# Project Path Normalization
# =============================================================================
# If PROJECT_PATH is provided, check if it's a directory or file
if [ -n "$PROJECT_PATH" ]; then
    if [ -d "$PROJECT_PATH" ]; then
        # If it's a directory, append /project.qpproj
        PROJECT_PATH="${PROJECT_PATH%/}/project.qpproj"
        log "Project directory provided, using: $PROJECT_PATH"
    elif [[ "$PROJECT_PATH" == *.qpproj ]]; then
        # If it already ends with .qpproj, use as is
        log "Project file provided: $PROJECT_PATH"
    else
        # If it's neither a directory nor ends with .qpproj, assume it's a directory without trailing slash
        PROJECT_PATH="${PROJECT_PATH}/project.qpproj"
        log "Assuming project directory, using: $PROJECT_PATH"
    fi
fi

# =============================================================================
# Pipeline Initialization
# =============================================================================
# Clear screen and show welcome message
clear
echo -e "\033[1;35m===============================================\033[0m"
echo -e "\033[1;35m     PANK Thesis - TRIDENT GeoJSON Import     \033[0m"
echo -e "\033[1;35m===============================================\033[0m"
echo

# Log start of pipeline with configuration details
log "Starting TRIDENT GeoJSON import pipeline"
log "TRIDENT output directory: $TRIDENT_DIR"
echo

# =============================================================================
# Input Validation
# =============================================================================
log "Validating input directories..."

# Check TRIDENT output directory
if [ ! -d "$TRIDENT_DIR" ]; then
    error_log "TRIDENT output directory not found: $TRIDENT_DIR"
    exit 1
fi

# Convert to absolute path for QuPath
TRIDENT_DIR=$(realpath "$TRIDENT_DIR")
log "Using absolute TRIDENT path: $TRIDENT_DIR"

# =============================================================================
# QuPath Path Configuration
# =============================================================================
# Use custom QuPath path if provided, otherwise use auto-detection
if [ -n "$CUSTOM_QUPATH_PATH" ]; then
    QUPATH_PATH="$CUSTOM_QUPATH_PATH"
    log "Using custom QuPath path: $QUPATH_PATH"
else
    # Use auto-detection to prefer QuPath 0.5.1 when available
    QUPATH_PATH=$(determine_optimal_qupath)
    if [ $? -ne 0 ] || [ -z "$QUPATH_PATH" ]; then
        error_log "Failed to determine optimal QuPath installation"
        exit 1
    fi
    log "Using auto-detected QuPath path: $QUPATH_PATH"
fi

# Validate QuPath installation
if [ ! -f "$QUPATH_PATH" ]; then
    error_log "QuPath not found at $QUPATH_PATH"
    if [ -n "$CUSTOM_QUPATH_PATH" ]; then
        error_log "Custom QuPath path is invalid"
    else
        error_log "Auto-detection failed to find a valid QuPath installation"
    fi
    exit 1
fi

log "QuPath executable validated: $QUPATH_PATH"

# =============================================================================
# Function to Process a Single Project
# =============================================================================
process_project() {
    local project_file="$1"
    local project_name=$(basename "$(dirname "$project_file")")
    
    log "Processing project: $project_name"
    log "Project file: $project_file"
    
    if [ ! -f "$project_file" ]; then
        error_log "Project file not found: $project_file"
        return 1
    fi
    
    echo -e "\033[1;36m=== QuPath Pre-Import Validation ===\033[0m"
    
    # Create a temporary script to run validation only
    local temp_validation_script="/tmp/validation_only_${RANDOM}.groovy"
    
    # Extract validation portion from main script (everything before "STARTING IMPORT PROCESS")
    sed '/=== STARTING IMPORT PROCESS ===/q' "$GROOVY_SCRIPT" > "$temp_validation_script"
    echo 'return // Exit after validation' >> "$temp_validation_script"
    
    # Run validation and show output on console
    if "$QUPATH_PATH" script --project="$project_file" \
                    --args="$TRIDENT_DIR" \
                    "$temp_validation_script" \
                    2>&1 | tee -a "$QUPATH_LOG"; then
        
        echo -e "\033[1;36m=== End Pre-Import Validation ===\033[0m"
        echo
        
        # Clean up temp script
        rm -f "$temp_validation_script"
        
        # Now run the full import with progress bar
        echo -e "\033[1;33mImporting TRIDENT annotations...\033[0m"
        
        # Create a temporary import-only script that opens the project internally
        local temp_import_script="/tmp/import_only_${RANDOM}.groovy"
        
        cat > "$temp_import_script" << EOF
import qupath.lib.projects.Project
import qupath.lib.projects.ProjectIO
import qupath.lib.images.ImageData
import qupath.lib.common.GeneralTools
import qupath.lib.io.PathIO
import qupath.lib.objects.PathObject
import qupath.lib.objects.classes.PathClassFactory
import qupath.lib.scripting.QP
import java.awt.Color

// Import-only script - opens project and processes all images

if (args.size() < 2) {
    println "Error: Missing arguments. Required: <project_file> <trident_base_output_dir>"
    return
}

def projectFilePath = args[0]
def tridentBaseOutputDirPath = args[1]
def tridentBaseOutputDir = new File(tridentBaseOutputDirPath)

if (!tridentBaseOutputDir.exists() || !tridentBaseOutputDir.isDirectory()) {
    println "Error: TRIDENT base output directory not found: \${tridentBaseOutputDirPath}"
    return
}

// Open the project
def projectFile = new File(projectFilePath)
if (!projectFile.exists()) {
    println "Error: Project file not found: \${projectFilePath}"
    return
}

def project = ProjectIO.loadProject(projectFile.toURI(), BufferedImage.class, true)
if (project == null) {
    println "Error: Could not load project from \${projectFilePath}"
    return
}

println "=== STARTING IMPORT PROCESS ==="
println "Processing project: \${project.getName()}"

def importedCount = 0
def notFoundCount = 0
def errorCount = 0

project.getImageList().eachWithIndex { entry, index ->
    def imageData = entry.readImageData()
    def server = imageData.getServer()
    def imageNameWithExtension = server.getMetadata().getName()
    def imageNameNoExt = GeneralTools.stripExtension(imageNameWithExtension)
    
    println "Processing QuPath image (\${index + 1}/\${project.getImageList().size()}): \${imageNameWithExtension} (stripped: \${imageNameNoExt})"

    def geojsonFile = new File(tridentBaseOutputDir, "contours_geojson" + File.separator + imageNameNoExt + ".geojson")

    if (geojsonFile.exists() && geojsonFile.isFile()) {
        println "  Found corresponding GeoJSON: \${geojsonFile.getAbsolutePath()}"
        try {
            List<PathObject> importedObjects = PathIO.readObjects(geojsonFile.toPath())
            
            if (importedObjects.isEmpty()) {
                println "  Warning: GeoJSON file \${geojsonFile.getName()} was empty or contained no valid QuPath objects."
            } else {
                def tissueClassName = "Tissue (TRIDENT)"
                def tissueColor = Color.GREEN
                def tissueClass = project.getPathClasses().find { it.getName() == tissueClassName }
                if (tissueClass == null) {
                   tissueClass = PathClassFactory.getPathClass(tissueClassName, tissueColor)
                   project.getPathClasses().add(tissueClass)
                   println "    Created new PathClass: \${tissueClassName}"
                }
                
                // SYSTEMATIC CLEANUP: Always clear existing TRIDENT annotations before importing
                def existingTridentAnnotations = imageData.getHierarchy().getAnnotationObjects().findAll { 
                    it.getPathClass() == tissueClass 
                }
                
                if (!existingTridentAnnotations.isEmpty()) {
                    println "  Clearing \${existingTridentAnnotations.size()} existing TRIDENT annotations before import..."
                    imageData.getHierarchy().removeObjects(existingTridentAnnotations, true)
                } else {
                    println "  No existing TRIDENT annotations found - proceeding with fresh import"
                }
                
                imageData.getHierarchy().addObjects(importedObjects) 
                
                importedObjects.each { pathObject ->
                    pathObject.setPathClass(tissueClass)
                }
                
                entry.saveImageData(imageData)
                println "  Successfully imported \${importedObjects.size()} objects from GeoJSON for \${imageNameNoExt} and assigned class '\${tissueClassName}'. Saved to project."
                importedCount++
            }
        } catch (Exception e_import) {
            println "  Error importing GeoJSON for \${imageNameNoExt}: \${e_import.getMessage()}"
            e_import.printStackTrace()
            errorCount++
        }
    } else {
        println "  Warning: Expected GeoJSON file not found for \${imageNameNoExt} at: \${geojsonFile.getAbsolutePath()}"
        notFoundCount++
    }
    println "-----------------------------------------------------"
}

project.syncChanges()
println "GeoJSON import process finished."
println "Summary:"
println "  Successfully imported annotations for: \${importedCount} images."
println "  GeoJSON files not found for: \${notFoundCount} images."
println "  Errors during import for: \${errorCount} images."
EOF
        
        # Run import in background and capture output to log only (WITHOUT --project flag)
        if "$QUPATH_PATH" script \
                        --args="$project_file" "$TRIDENT_DIR" \
                        "$temp_import_script" \
                        >> "$QUPATH_LOG" 2>&1 & then
            
            local import_pid=$!
            
            # Show progress bar while import runs
            show_import_progress "$import_pid" "$project_name"
            
            # Wait for import to complete and get exit code
            wait "$import_pid"
            local exit_code=$?
            
            # Clean up temp script
            rm -f "$temp_import_script"
            
            if [ $exit_code -eq 0 ]; then
                echo -e "\n\033[1;32m✓ Successfully imported TRIDENT annotations for $project_name\033[0m"
                log "Successfully imported TRIDENT GeoJSON for project: $project_name"
                return 0
            else
                echo -e "\n\033[1;31m✗ Failed to import TRIDENT annotations for $project_name\033[0m"
                error_log "Failed to import TRIDENT GeoJSON for project: $project_name"
                return 1
            fi
        else
            echo -e "\n\033[1;31m✗ Failed to start import process for $project_name\033[0m"
            error_log "Failed to start import process for project: $project_name"
            rm -f "$temp_import_script"
            return 1
        fi
        
    else
        echo -e "\033[1;31m✗ Validation failed for $project_name\033[0m"
        error_log "Validation failed for project: $project_name"
        rm -f "$temp_validation_script"
        rm -f "$temp_import_script"
        return 1
    fi
}

# =============================================================================
# Function to Show Import Progress
# =============================================================================
show_import_progress() {
    local pid=$1
    local project_name=$2
    local progress=0
    local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        # Get current spinner character
        local spin_char=${spinner:$((i % ${#spinner})):1}
        
        # Show spinning progress indicator
        printf "\r\033[1;33m%s\033[0m Importing annotations for %s... \033[1;36m%s\033[0m" \
               "$spin_char" "$project_name" "$(date '+%H:%M:%S')"
        
        ((i++))
        sleep 0.1
    done
    
    # Clear the spinner line
    printf "\r\033[K"
}

# =============================================================================
# Main Processing Logic
# =============================================================================
successful_projects=0
failed_projects=0

if [ "$TEST_ONLY" = true ]; then
    # Process only the test project
    log "Processing test project only (QuPath_MP_PDAC5)"
    test_project="QuPath_MP_PDAC5/project.qpproj"
    
    if process_project "$test_project"; then
        ((successful_projects++))
    else
        ((failed_projects++))
    fi
    
elif [ -n "$PROJECT_PATH" ]; then
    # Process single specified project
    log "Processing single project: $PROJECT_PATH"
    
    if process_project "$PROJECT_PATH"; then
        ((successful_projects++))
    else
        ((failed_projects++))
    fi
    
elif [ "$PROCESS_ALL" = true ]; then
    # Process all QuPath projects in current directory
    log "Processing all QuPath projects in current directory"
    
    # Find all QuPath project files
    project_files=(QuPath_MP_PDAC*/project.qpproj)
    
    if [ ${#project_files[@]} -eq 0 ] || [ ! -f "${project_files[0]}" ]; then
        error_log "No QuPath project files found in current directory"
        exit 1
    fi
    
    total_projects=${#project_files[@]}
    log "Found $total_projects QuPath projects to process"
    
    current_project=0
    for project_file in "${project_files[@]}"; do
        ((current_project++))
        progress_bar "$current_project" "$total_projects"
        echo # New line after progress bar
        
        if process_project "$project_file"; then
            ((successful_projects++))
        else
            ((failed_projects++))
        fi
        
        # Allow QuPath to fully save changes between projects
        sleep 2
    done
fi

# =============================================================================
# Pipeline Completion
# =============================================================================
echo
echo -e "\033[1;32m===============================================\033[0m"
echo -e "\033[1;32m           Pipeline Execution Complete         \033[0m"
echo -e "\033[1;32m===============================================\033[0m"
log "TRIDENT GeoJSON import pipeline completed"
log "Successfully processed: $successful_projects projects"
log "Failed to process: $failed_projects projects"
log "Check $LOG_FILE for detailed logs"
log "Check $ERROR_LOG for error logs"
log "QuPath verbose output is in $QUPATH_LOG"

if [ "$failed_projects" -gt 0 ]; then
    exit 1
else
    exit 0
fi 