// Simple diagnostic script to check available extensions and classes
println "=== QuPath Extension Diagnostic ==="

// Check available classes
println "Checking for StarDist classes..."
try {
    def stardistClass = Class.forName("qupath.ext.stardist.StarDist2D")
    println "SUCCESS: StarDist2D class found: ${stardistClass.name}"
} catch (ClassNotFoundException e) {
    println "ERROR: StarDist2D class not found"
}

// Check classpath
println "\nChecking classpath..."
def classLoader = this.class.classLoader
if (classLoader.hasProperty('URLs')) {
    classLoader.URLs.each { url ->
        if (url.toString().contains('stardist')) {
            println "Found StarDist in classpath: ${url}"
        }
    }
}

// Check system properties
println "\nChecking system properties..."
System.properties.each { key, value ->
    if (key.toString().toLowerCase().contains('path') || key.toString().toLowerCase().contains('class')) {
        if (value.toString().contains('stardist')) {
            println "${key}: ${value}"
        }
    }
}

println "\nDiagnostic complete." 