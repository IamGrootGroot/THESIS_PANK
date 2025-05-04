#!/usr/bin/env python3
"""
UNI2 Feature Extraction Script

This script extracts features from images using the UNI2-h model from HuggingFace.
It processes images in batches and saves the extracted features to a CSV file.

Copyright (c) 2024 Maxence PELLOUX
All rights reserved.

This software is part of the PANK Thesis Project.
No part of this software may be reproduced, distributed, or transmitted in any form
or by any means, including photocopying, recording, or other electronic or mechanical
methods, without the prior written permission of the copyright holder.

Usage:
    python 03_uni2_feature_extraction_NEW2.py --image_dir /path/to/images --output_csv features.csv --batch_size 32

Requirements:
    - torch
    - timm
    - PIL
    - pandas
    - tqdm
    - huggingface_hub
"""

import os
import torch
import logging
import argparse
from torch.utils.data import DataLoader, Dataset
from PIL import Image
import pandas as pd
from tqdm import tqdm
import timm
from timm.data import resolve_data_config
from timm.data.transforms_factory import create_transform
from huggingface_hub import login

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ----------------------------------------
# 1) Custom Dataset for Image Tiles
# ----------------------------------------
class ImageDataset(Dataset):
    """Dataset class for loading and preprocessing images."""
    
    def __init__(self, image_dir, transform=None):
        """
        Initialize the dataset.
        
        Args:
            image_dir (str): Directory containing the images
            transform (callable, optional): Transform to apply to images
        """
        self.image_dir = image_dir
        self.transform = transform
        self.image_files = []

        if not os.path.exists(image_dir):
            raise FileNotFoundError(f"Image directory not found: {image_dir}")

        for root, _, files in os.walk(self.image_dir):
            for file in files:
                if file.lower().endswith(('.jpg', '.jpeg', '.png', '.tif', '.tiff')):
                    self.image_files.append(os.path.join(root, file))
        
        if not self.image_files:
            raise ValueError(f"No valid images found in {image_dir}")

        logger.info(f"Found {len(self.image_files)} images in {image_dir}")

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
            logger.error(f"Error loading image {img_path}: {str(e)}")
            raise

# ----------------------------------------
# 2) Model Initialization
# ----------------------------------------

def init_uni2_model(device, hf_token):
    """
    Initialize the UNI2-h model.
    
    Args:
        device (torch.device): Device to run the model on
        hf_token (str): HuggingFace API token
        
    Returns:
        torch.nn.Module: Initialized UNI2-h model
    """
    try:
        login(token=hf_token)
        
        timm_kwargs = {
            'img_size': 224,
            'patch_size': 14,
            'depth': 24,
            'num_heads': 24,
            'init_values': 1e-5,
            'embed_dim': 1536,
            'mlp_ratio': 2.66667 * 2,
            'num_classes': 0,
            'no_embed_class': True,
            'mlp_layer': timm.layers.SwiGLUPacked,
            'act_layer': torch.nn.SiLU,
            'reg_tokens': 8,
            'dynamic_img_size': True
        }

        model = timm.create_model("hf-hub:MahmoodLab/UNI2-h", pretrained=True, **timm_kwargs)
        model.eval().to(device)
        return model
    except Exception as e:
        logger.error(f"Error initializing model: {str(e)}")
        raise

# ----------------------------------------
# 3) Image Preprocessing (Transform)
# ----------------------------------------

def get_uni2_transform(model):
    """Get the preprocessing transform for the UNI2 model."""
    config = resolve_data_config(model.pretrained_cfg, model=model)
    return create_transform(**config)

# ----------------------------------------
# 4) Feature Extraction Function with Mixed Precision
# ----------------------------------------

def extract_embeddings(dataloader, model, device):
    """
    Extract embeddings from images using the UNI2 model.
    
    Args:
        dataloader (DataLoader): DataLoader containing the images
        model (torch.nn.Module): UNI2 model
        device (torch.device): Device to run inference on
        
    Returns:
        tuple: (embeddings tensor, list of filenames)
    """
    all_embeddings = []
    all_filenames = []
    
    with torch.inference_mode():
        for images, filenames in tqdm(dataloader, desc="Extracting Features"):
            try:
                images = images.to(device, non_blocking=True)
                
                with torch.cuda.amp.autocast():
                    features = model(images)
                
                if features.dim() == 1:
                    features = features.unsqueeze(0)
                
                all_embeddings.append(features.cpu())
                all_filenames.extend(filenames)
            except Exception as e:
                logger.error(f"Error processing batch: {str(e)}")
                continue
    
    if not all_embeddings:
        raise RuntimeError("No embeddings were successfully extracted")
        
    embeddings_tensor = torch.cat(all_embeddings, dim=0)
    return embeddings_tensor, all_filenames

# ----------------------------------------
# 5) Save Embeddings to CSV
# ----------------------------------------

def save_embeddings(embeddings_tensor, filenames, output_csv):
    """
    Save embeddings to a CSV file.
    
    Args:
        embeddings_tensor (torch.Tensor): Tensor containing the embeddings
        filenames (list): List of corresponding filenames
        output_csv (str): Path to save the CSV file
    """
    try:
        embeddings = embeddings_tensor.numpy()
        dim_cols = [f"dim_{i}" for i in range(embeddings.shape[1])]
        df = pd.DataFrame(embeddings, columns=dim_cols)
        df.insert(0, 'filename', filenames)
        df.to_csv(output_csv, index=False)
        logger.info(f"Embeddings saved to {output_csv}")
    except Exception as e:
        logger.error(f"Error saving embeddings: {str(e)}")
        raise

# ----------------------------------------
# 6) Main Pipeline
# ----------------------------------------

def main(args):
    """
    Main execution function.
    
    Args:
        args (argparse.Namespace): Command line arguments
    """
    try:
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        logger.info(f"Running on device: {device}")

        model = init_uni2_model(device, args.hf_token)
        transform = get_uni2_transform(model)

        dataset = ImageDataset(args.image_dir, transform=transform)
        dataloader = DataLoader(
            dataset,
            batch_size=args.batch_size,
            shuffle=False,
            num_workers=args.num_workers,
            pin_memory=True
        )

        embeddings_tensor, filenames = extract_embeddings(dataloader, model, device)
        save_embeddings(embeddings_tensor, filenames, args.output_csv)
        
        logger.info("Feature extraction completed successfully")
        
    except Exception as e:
        logger.error(f"Error in main execution: {str(e)}")
        raise

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract features from images using UNI2-h model")
    parser.add_argument("--image_dir", type=str, required=True,
                      help="Directory containing the images")
    parser.add_argument("--output_csv", type=str, required=True,
                      help="Path to save the output CSV file")
    parser.add_argument("--batch_size", type=int, default=32,
                      help="Batch size for processing (default: 32)")
    parser.add_argument("--num_workers", type=int, default=4,
                      help="Number of worker processes for data loading (default: 4)")
    parser.add_argument("--hf_token", type=str, required=True,
                      help="HuggingFace API token")
    
    args = parser.parse_args()
    main(args)
