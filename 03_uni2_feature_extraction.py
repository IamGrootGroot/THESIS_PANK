## Feature extraction (1536 dim per tile) for H&E tiles (all subfolders) using UNI2-h pretrained encoder// timm // torch
## A. Khellaf (2025-01)

import os
import torch
import timm
import pandas as pd
from PIL import Image
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms
from tqdm import tqdm
from huggingface_hub import login
import numpy as np
from pathlib import Path
import sys
import argparse
import logging
import warnings

# Add the parent directory to the path so we can import config
sys.path.append(str(Path(__file__).parent.parent))
from config import (
    PATCHES_DIR, FEATURES_OUTPUT, BATCH_SIZE, FEATURE_DIM,
    get_os_path, setup_directories
)

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Ensure directories exist
setup_directories()

######################################################
# 1) Custom dataset using .jpg tiles or other formats
######################################################
class PatchDataset(Dataset):
    def __init__(self, image_dir, transform=None):
        self.image_dir = image_dir
        self.transform = transform or transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])
        self.image_files = []
        for root, _, files in os.walk(image_dir):
            for file in files:
                if file.lower().endswith(('.png', '.jpg', '.jpeg')):
                    self.image_files.append(os.path.join(root, file))

    def __len__(self):
        return len(self.image_files)

    def __getitem__(self, idx):
        img_path = self.image_files[idx]
        try:
            image = Image.open(img_path).convert('RGB')
            if self.transform:
                image = self.transform(image)
            return image, img_path
        except Exception as e:
            logger.error(f"Error loading image {img_path}: {e}")
            return None, img_path

######################################################
# 2) Model initialization
######################################################
def get_model(device):
    """
    Logs in to HuggingFace Hub and returns the UNI2 model on the specified device.
    """
    # Try to login to HuggingFace using environment variable
    hf_token = os.getenv('HUGGING_FACE_TOKEN')
    if hf_token:
        try:
            login(token=hf_token)
            logger.info("Successfully logged in to HuggingFace")
        except Exception as e:
            logger.warning(f"Failed to login to HuggingFace: {e}")
    else:
        logger.warning("HUGGING_FACE_TOKEN environment variable not set. Some models may not be accessible.")
    
    # These hyperparameters come from:
    # https://huggingface.co/mahmoodlab/uni2-h/blob/main/configs/uni2_h.yaml
    timm_kwargs = {
        "model_name": "vit_base_patch16_224",
        "pretrained": False,
        "num_classes": 0,
        "global_pool": "",
    }

    # Load the model
    model = timm.create_model(**timm_kwargs)
    
    # Load the weights
    state_dict = torch.load(get_os_path(PATCHES_DIR / "uni2_h.pth"), map_location=device)
    model.load_state_dict(state_dict)
    
    model = model.to(device)
    model.eval()
    return model

######################################################
# 3) Preprocessing (transform)
######################################################
def get_uni2_transform(model):
    """
    Builds a transform using the model's default config.
    The result is a composition of Resize / CenterCrop / ToTensor / Normalize, etc.
    """
    # timm stores its transforms in model.pretrained_cfg
    config = resolve_data_config(model.pretrained_cfg, model=model)
    transform = create_transform(**config)
    return transform

######################################################
# 4) Obtain embeddings - feature extraction
######################################################
def extract_features(model, dataloader, device):
    features_list = []
    paths_list = []
    
    with torch.no_grad():
        for images, paths in tqdm(dataloader, desc="Extracting features"):
            images = images.to(device)
            
            # Get features
            features = model(images)
            
            # Ensure it's at least 2D
            if features.dim() == 1:
                features = features.unsqueeze(0)
            
            features_list.append(features.cpu().numpy())
            paths_list.extend(paths)
    
    return np.vstack(features_list), paths_list

######################################################
# 5) Save embeddings to .csv
######################################################
def save_embeddings_to_csv(embeddings_tensor, filenames, output_csv_path):
    """
    Save final embeddings + filenames to a CSV.
    """
    # Convert torch -> numpy
    embeddings = embeddings_tensor.numpy()

    # Create columns
    dim_cols = [f"dim_{i}" for i in range(embeddings.shape[1])]
    df = pd.DataFrame(embeddings, columns=dim_cols)
    df.insert(0, 'filename', filenames)
    df.to_csv(output_csv_path, index=False)

    print(f"Embeddings saved to {output_csv_path}")

######################################################
# 6) Main pipeline
######################################################
def main():
    # Set device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")
    
    # Initialize model
    print("Loading model...")
    model = get_model(device)
    
    # Create dataset and dataloader
    print("Creating dataset...")
    dataset = PatchDataset(get_os_path(PATCHES_DIR))
    dataloader = DataLoader(dataset, batch_size=BATCH_SIZE, shuffle=False, num_workers=4)
    
    # Extract features
    print("Extracting features...")
    features, paths = extract_features(model, dataloader, device)
    
    # Create DataFrame
    print("Saving features...")
    df = pd.DataFrame(features)
    df['path'] = paths
    
    # Save to CSV
    output_path = get_os_path(FEATURES_OUTPUT / "features.csv")
    df.to_csv(output_path, index=False)
    print(f"Features saved to {output_path}")

if __name__ == "__main__":
    main()