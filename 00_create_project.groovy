// This script allows the creation of a QuPath project, either from the command line
// or interactively by launching the script from within QuPath
//
// Script author: Egor Zindy
// Based on code by @melvingelbard -- Discussion over at:
// https://forum.image.sc/t/creating-project-from-command-line/45608/11
// Script should work with QuPath v0.5.0 or newer
// Modified to force Bio-Formats for NDPI files

import groovy.io.FileType
import java.awt.image.BufferedImage
import qupath.lib.images.servers.ImageServerProvider
import qupath.lib.gui.commands.ProjectCommands
import qupath.lib.gui.tools.GuiTools
import qupath.lib.gui.images.stores.DefaultImageRegionStore
import qupath.lib.gui.images.stores.ImageRegionStoreFactory
import qupath.fx.dialogs.FileChoosers
import qupath.lib.images.servers.ImageServers
import qupath.lib.images.servers.bioformats.BioFormatsServerBuilder
import qupath.lib.images.servers.openslide.OpenslideServerBuilder

// Define whether to pyramidalize images when adding them to the project
def pyramidalizeImages = true

//Did we receive a string via the command line args keyword?
if (args.size() > 0) {
    selectedDir = new File(args[0])
} else {
    if (getQuPath() == null) {
       println "Can't create directory: specify a directory with --args /path/to/your/directory/ in the command line"
       return
    } else {
        selectedDir = FileChoosers.promptForDirectory()
    }
    
}

if (selectedDir == null)
    return
    
// Check if we already have a QuPath Project directory in there...
projectName = "QuPathProject"
File directory = new File(selectedDir.toString() + File.separator + projectName)

if (!directory.exists())
{
    println "No project directory, creating one!"
    directory.mkdirs()
}

// Create project
def project = Projects.createProject(directory , BufferedImage.class)

// Set up cache
def imageRegionStore
if (getQuPath() == null) {
    imageRegionStore = ImageRegionStoreFactory.createImageRegionStore();
} else {
    imageRegionStore = getQuPath().getImageRegionStore()
}

// Some filetypes are split between a name and a folder and we need to eliminate the folder from our recursive search.
// This is the case for vsi files for instance.
def skipList = []
selectedDir.eachFileRecurse (FileType.FILES) { file ->
    if (file.name.endsWith(".vsi")) {
        print(file.name)
        f = new File(file.parent+File.separator+"_"+file.name.substring(0, file.name.length() - 4)+"_")
        skipList.add(f.toString()) //getCanonicalPath())
        return
    }
}

// Get the Bio-Formats server builder explicitly
def bioformatsBuilder = ImageServerProvider.getInstalledImageServerBuilders(BufferedImage.class).find {
    it instanceof BioFormatsServerBuilder
}

if (bioformatsBuilder == null) {
    println "ERROR: Bio-Formats server builder not found! Make sure the Bio-Formats extension is installed."
    return
}

// Add files to the project
selectedDir.eachFileRecurse (FileType.FILES) { file ->
    def imagePath = file.getCanonicalPath()
    skip = false
    for (p in skipList) {
        //print("--->"+p)
        if (imagePath.startsWith(p)) {
            skip = true
        }
        
    }
    if (skip == true) {
        //print("Skipping "+imagePath)
        return
    }
        
    // Skip a folder if there is a corresponding .vsi file.
    if (file.isDirectory()) {
        print(file.getParent())
        print(file.getName().startsWith('_') && file.getName().endsWith('_'))
        return
    }
    
    // Skip the project directory itself
    if (file.getCanonicalPath().startsWith(directory.getCanonicalPath() + File.separator))
        return
        
    // I tend to add underscores to the end of filenames I want excluded
    // MacOSX seems to add hidden files that start with a dot (._), don't add those
    if (file.getName().endsWith("_") || file.getName().startsWith("."))
        return

    // Process NDPI files
    if (file.getName().toLowerCase().endsWith(".ndpi")) {
        println "Processing NDPI file: " + file.getName()
        
        // Try different providers in order of preference
        def providers = [
            [name: "OpenSlide", builder: new OpenslideServerBuilder()],
            [name: "Bio-Formats", builder: new BioFormatsServerBuilder()],
            [name: "Default", builder: null]  // Will use default provider
        ]
        
        boolean success = false
        Exception lastError = null
        
        providers.find { provider ->
            try {
                println "Attempting to use ${provider.name} provider..."
                
                def support
                if (provider.builder != null) {
                    support = provider.builder.buildImageServers(new URI("file:" + imagePath))
                } else {
                    support = ImageServerProvider.getPreferredUriImageSupport(BufferedImage.class, imagePath)
                }
                
                if (support == null || support.builders.isEmpty()) {
                    println "No support available with ${provider.name} for " + file.getName()
                    return false
                }
                
                println "Using provider: " + support.getClass().getName()
                
                // Process each scene
                return support.builders.find { builder ->
                    def sceneName = file.getName()
                    
                    if (support.builders.size() > 1)
                        sceneName += " - Scene #" + (support.builders.indexOf(builder) + 1)
                    
                    // Create a pyramidalized server if requested
                    if (pyramidalizeImages) {
                        try {
                            def server = builder.build()
                            println "Successfully built server with ${provider.name}"
                            println "Server metadata: " + server.getMetadata()
                            
                            def pyramidBuilder = ImageServers.pyramidalize(server).getBuilder()
                            entry = project.addImage(pyramidBuilder)
                            success = true
                        } catch (Exception e) {
                            println "Error creating pyramidalized server with ${provider.name} for " + sceneName + ": " + e.getMessage()
                            lastError = e
                            // Try without pyramidalization as a fallback
                            try {
                                entry = project.addImage(builder)
                                success = true
                            } catch (Exception e2) {
                                println "Error adding non-pyramidalized image: " + e2.getMessage()
                                lastError = e2
                                return false
                            }
                        }
                    } else {
                        try {
                            entry = project.addImage(builder)
                            success = true
                        } catch (Exception e) {
                            println "Error adding image with ${provider.name}: " + e.getMessage()
                            lastError = e
                            return false
                        }
                    }
                    
                    try {
                        imageData = entry.readImageData()
                        // Print image server information
                        def server = imageData.getServer()
                        println "Image server for " + sceneName + ":"
                        println "  - Server class: " + server.getClass().getName()
                        println "  - Server metadata: " + server.getMetadata()
                        println "  - Server path: " + server.getPath()
                        println "  - Server URI: " + server.getURIs()
                        println "  - Server builder: " + server.getBuilder()
                        
                        println "Adding: " + sceneName
                    
                        // Set a particular image type automatically
                        def imageType = GuiTools.estimateImageType(server, imageRegionStore.getThumbnail(server, 0, 0, true));
                        imageData.setImageType(imageType)
                        println "Image type estimated to be " + imageType

                        // Adding image data to the project entry
                        entry.saveImageData(imageData)
                    
                        // Write a thumbnail if we can
                        var img = ProjectCommands.getThumbnailRGB(server);
                        entry.setThumbnail(img)
                        
                        // Add an entry name (the filename)
                        entry.setImageName(sceneName)
                        
                        success = true
                        return true
                    } catch (Exception ex) {
                        println sceneName +" -- Error reading image data " + ex
                        project.removeImage(entry, true)
                        lastError = ex
                        return false
                    }
                }
            } catch (Exception e) {
                println "Error with ${provider.name} provider for " + file.getName() + ": " + e.getMessage()
                lastError = e
                return false
            }
            return success
        }
        
        if (!success && lastError != null) {
            println "Failed to process file " + file.getName() + " with all providers. Last error: " + lastError.getMessage()
            println "Stack trace:"
            lastError.printStackTrace()
        }
    } else {
        // For non-NDPI files, use the default approach
        def support = ImageServerProvider.getPreferredUriImageSupport(BufferedImage.class, imagePath)
        if (support == null)
            return

        // iterate through the scenes contained in the image file
        support.builders.eachWithIndex { builder, i -> 
            sceneName = file.getName()
            
            if (sceneName.endsWith('.vsi')) {
                //This is specific to .vsi files, we do not add a scene name to a vsi file
                if (support.builders.size() >= 3 && i < 2) {
                    return;
                }
            } else {
                if (support.builders.size() > 1)
                    sceneName += " - Scene #" + (i+1)
            }
            
            // Add a new entry for the current builder and remove it if we weren't able to read the image.
            if (pyramidalizeImages) {
                entry = project.addImage(ImageServers.pyramidalize(builder.build()).getBuilder())
            } else {
                entry = project.addImage(builder)
            }
        
            try {
                imageData = entry.readImageData()
                // Print image server information
                def server = imageData.getServer()
                println "Image server for " + sceneName + ":"
                println "  - Server class: " + server.getClass().getName()
                println "  - Server metadata: " + server.getMetadata()
                println "  - Server path: " + server.getPath()
                println "  - Server URI: " + server.getURIs()
                println "  - Server builder: " + server.getBuilder()
            } catch (Exception ex) {
                println sceneName +" -- Error reading image data " + ex
                project.removeImage(entry, true)
                return
            }
            
            println "Adding: " + sceneName
        
            // Set a particular image type automatically (based on /qupath/lib/gui/QuPathGUI.java#L2847)
            def imageType = GuiTools.estimateImageType(imageData.getServer(), imageRegionStore.getThumbnail(imageData.getServer(), 0, 0, true));
            imageData.setImageType(imageType)
            println "Image type estimated to be " + imageType

            // Adding image data to the project entry
            entry.saveImageData(imageData)
        
            // Write a thumbnail if we can
            var img = ProjectCommands.getThumbnailRGB(imageData.getServer());
            entry.setThumbnail(img)
            
            // Add an entry name (the filename)
            entry.setImageName(sceneName)
        }
    }
}

// Changes should now be reflected in the project directory
project.syncChanges()