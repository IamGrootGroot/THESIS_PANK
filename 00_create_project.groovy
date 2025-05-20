// This script allows the creation of a QuPath project, either from the command line
// or interactively by launching the script from within QuPath
//
// Script author: Egor Zindy
// Based on code by @melvingelbard -- Discussion over at:
// https://forum.image.sc/t/creating-project-from-command-line/45608/11
// Script should work with QuPath v0.5.0 or newer

import groovy.io.FileType
import java.awt.image.BufferedImage
import qupath.lib.images.servers.ImageServerProvider
import qupath.lib.gui.commands.ProjectCommands
import qupath.lib.gui.tools.GuiTools
import qupath.lib.gui.images.stores.DefaultImageRegionStore
import qupath.lib.gui.images.stores.ImageRegionStoreFactory
import qupath.fx.dialogs.FileChoosers
import qupath.lib.images.servers.ImageServers
import qupath.lib.images.servers.ImageServerBuilder

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

    // Is it a file we know how to read?
    def support
    if (file.getName().toLowerCase().endsWith('.ndpi')) {
        // For NDPI files, try to find a server builder that can handle it
        def builders = ImageServerProvider.getInstalledImageServerBuilders(BufferedImage.class)
        // Filter out ImageJ server builder for NDPI files
        builders = builders.findAll { builder ->
            !builder.getClass().getName().contains('ImageJServerBuilder')
        }
        
        // Try each non-ImageJ builder until we find one that works
        for (builder in builders) {
            try {
                def server = builder.build(imagePath)
                if (server != null) {
                    // Create a new support with just this builder
                    support = new qupath.lib.images.servers.ImageServerProvider.UriImageSupport(BufferedImage.class, [builder])
                    break
                }
            } catch (Exception e) {
                continue
            }
        }
    }
    
    // If no specific support found, try the default
    if (support == null) {
        support = ImageServerProvider.getPreferredUriImageSupport(BufferedImage.class, imagePath)
    }
    
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
        // I don't like it but I wasn't able to use PathIO.readImageData().
        if (pyramidalizeImages) {
            entry = project.addImage(ImageServers.pyramidalize(builder.build()).getBuilder())
        } else {
            entry = project.addImage(builder)
        }
    
        try {
            imageData = entry.readImageData()
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

// Changes should now be reflected in the project directory
project.syncChanges()