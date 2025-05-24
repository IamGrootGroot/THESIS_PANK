// Debug script to check what annotations exist in the QuPath project
// This will help identify if TRIDENT annotations are present and what their class names are

def project = getProject()
if (project == null) {
    print "Error: No QuPath project is currently open."
    return
}

print "=== QuPath Project Annotation Debug ==="
print "Project: ${project.getName()}"
print "Number of images in project: ${project.getImageList().size()}"
print ""

def totalAnnotations = 0
def annotationClassCounts = [:]

project.getImageList().eachWithIndex { entry, index ->
    def imageData = entry.readImageData()
    def server = imageData.getServer()
    def imageName = server.getMetadata().getName()
    def hierarchy = imageData.getHierarchy()
    
    def annotations = hierarchy.getAnnotationObjects()
    print "Image ${index + 1}: ${imageName}"
    print "  Total annotations: ${annotations.size()}"
    
    if (annotations.size() > 0) {
        def classCounts = [:]
        annotations.each { annotation ->
            def pathClass = annotation.getPathClass()
            def className = pathClass?.getName() ?: "No class"
            classCounts[className] = (classCounts[className] ?: 0) + 1
            annotationClassCounts[className] = (annotationClassCounts[className] ?: 0) + 1
        }
        
        classCounts.each { className, count ->
            print "    - ${className}: ${count} annotations"
        }
    } else {
        print "    - No annotations found"
    }
    
    totalAnnotations += annotations.size()
    print ""
}

print "=== Summary ==="
print "Total annotations across all images: ${totalAnnotations}"
print "Annotation classes found:"
annotationClassCounts.each { className, count ->
    print "  - ${className}: ${count} total"
}

print ""
print "=== Looking specifically for TRIDENT annotations ==="
def tridentClass = getPathClass("Tissue (TRIDENT)")
if (tridentClass != null) {
    print "PathClass 'Tissue (TRIDENT)' exists in project"
    
    def tridentCount = 0
    project.getImageList().each { entry ->
        def imageData = entry.readImageData()
        def hierarchy = imageData.getHierarchy()
        def tridentAnnotations = hierarchy.getAnnotationObjects().findAll { it.getPathClass() == tridentClass }
        tridentCount += tridentAnnotations.size()
    }
    print "Total 'Tissue (TRIDENT)' annotations: ${tridentCount}"
} else {
    print "PathClass 'Tissue (TRIDENT)' NOT found in project"
    print "Available PathClasses:"
    getPathClasses().each { pathClass ->
        print "  - ${pathClass.getName()}"
    }
}

print ""
print "Debug completed!" 