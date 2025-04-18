import os
from pathlib import Path

# Base directories
BASE_DIR = Path(__file__).parent.absolute()
MODELS_DIR = BASE_DIR / "models"
DATA_DIR = BASE_DIR / "data"
OUTPUT_DIR = BASE_DIR / "output"

# Create directories if they don't exist
for dir_path in [MODELS_DIR, DATA_DIR, OUTPUT_DIR]:
    dir_path.mkdir(exist_ok=True)

# Model paths
STARDIST_MODEL = MODELS_DIR / "he_heavy_augment.pb"

# Data paths
PATCHES_DIR = DATA_DIR / "patches"
EMBEDDINGS_DIR = DATA_DIR / "embeddings"
VISUALIZATIONS_DIR = DATA_DIR / "visualizations"

# Output paths
TILES_OUTPUT = OUTPUT_DIR / "tiles"
FEATURES_OUTPUT = OUTPUT_DIR / "features"
UMAP_OUTPUT = OUTPUT_DIR / "umap"

# Create output subdirectories
for dir_path in [TILES_OUTPUT, FEATURES_OUTPUT, UMAP_OUTPUT]:
    dir_path.mkdir(exist_ok=True)

# Processing parameters
PATCH_SIZE = 224
MAGNIFICATION = 40.0
PIXEL_SIZE = 0.23  # um per pixel

# Feature extraction parameters
BATCH_SIZE = 32
FEATURE_DIM = 1536

# UMAP parameters
N_NEIGHBORS = 15
MIN_DIST = 0.1
N_COMPONENTS = 3

# Helper functions
def get_os_path(path):
    """Convert Path object to OS-specific string path"""
    return str(path)

def setup_directories():
    """Create all necessary directories"""
    for dir_path in [
        MODELS_DIR, DATA_DIR, OUTPUT_DIR,
        PATCHES_DIR, EMBEDDINGS_DIR, VISUALIZATIONS_DIR,
        TILES_OUTPUT, FEATURES_OUTPUT, UMAP_OUTPUT
    ]:
        dir_path.mkdir(exist_ok=True) 