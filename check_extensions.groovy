// Script to check what extensions and StarDist-related classes are available

print "=== QuPath Extension and Class Check ==="
print ""

// Check QuPath version
print "QuPath version information:"
try {
    def version = qupath.lib.common.GeneralTools.getVersion()
    print "QuPath version: ${version}"
} catch (Exception e) {
    print "Could not get QuPath version: ${e.getMessage()}"
}

print ""
print "=== Checking for StarDist-related classes ==="

// List of possible StarDist import paths to try
def starDistPaths = [
    "qupath.ext.stardist.StarDist2D",
    "qupath.stardist.StarDist2D", 
    "stardist.StarDist2D",
    "qupath.lib.algorithms.detection.StarDist2D",
    "qupath.ext.StarDist2D"
]

def foundStarDist = false

starDistPaths.each { path ->
    try {
        def clazz = Class.forName(path)
        print "✅ Found StarDist at: ${path}"
        foundStarDist = true
    } catch (ClassNotFoundException e) {
        print "❌ Not found: ${path}"
    } catch (Exception e) {
        print "❌ Error checking ${path}: ${e.getMessage()}"
    }
}

if (!foundStarDist) {
    print ""
    print "⚠️  No StarDist classes found!"
    print "StarDist extension may not be installed."
}

print ""
print "=== Checking Extension Manager ==="
try {
    // Try to access extension manager
    def extensionManager = qupath.lib.gui.extensions.QuPathExtension
    print "Extension manager accessible"
} catch (Exception e) {
    print "Extension manager not accessible: ${e.getMessage()}"
}

print ""
print "=== Available Packages/Classes ==="
try {
    // Get all available classes in the classpath
    def classLoader = Thread.currentThread().getContextClassLoader()
    print "ClassLoader: ${classLoader.getClass().getName()}"
    
    // Check for any stardist-related packages
    def urls = classLoader.getURLs()
    print "Number of URLs in classpath: ${urls.length}"
    
    urls.findAll { it.toString().toLowerCase().contains("stardist") }.each { url ->
        print "StarDist-related URL: ${url}"
    }
    
} catch (Exception e) {
    print "Could not check classpath: ${e.getMessage()}"
}

print ""
print "=== Alternative Detection Methods ==="
print "If StarDist is not available, consider these alternatives:"
print "1. Use built-in QuPath cell detection methods"
print "2. Install StarDist extension manually"
print "3. Use a different QuPath build with StarDist pre-installed"

print ""
print "Check completed!" 