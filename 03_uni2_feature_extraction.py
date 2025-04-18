## Feature extraction (1536 dim per tile) for H&E tiles (all subfolders) using UNI2-h pretrained encoder// timm // torch
## A. Khellaf (2025-01)

import os
import torch
from torch.utils.data import DataLoader, Dataset

from PIL import Image
import pandas as pd

import timm
from timm.data import resolve_data_config
from timm.data.transforms_factory import create_transform
from huggingface_hub import login
# If your version of PyTorch <2.0, do NOT pass extra args
from torch.cuda.amp import autocast  # For older torch versions, we'll use `autocast(enabled=...)`

######################################################
# 1) Custom dataset using .jpg tiles or other formats
######################################################
class ImageDataset(Dataset):
    def __init__(self, image_dir, transform=None):
        self.image_dir = image_dir
        self.transform = transform
        self.image_files = []

        for root, _, files in os.walk(self.image_dir):
            for file in files:
                # Include other extensions if needed: .png, .tif, etc.
                if file.lower().endswith('.jpg') or file.lower().endswith('.jpeg'):
                    self.image_files.append(os.path.join(root, file))

    def __len__(self):
        return len(self.image_files)

    def __getitem__(self, idx):
        img_path = self.image_files[idx]
        image = Image.open(img_path).convert('RGB')
        if self.transform:
            image = self.transform(image)
        return image, img_path

######################################################
# 2) Model initialization
######################################################
def init_uni2_model(device):
    """
    Logs in to HuggingFace Hub and returns the UNI2 model on the specified device.
    """
    login(token='YOUR_HUGGING_FACE_TOKEN_HERE') # Please keep it private (it's my personal token)

    # These hyperparameters come from:
    # https://huggingface.co/MahmoodLab/UNI2-h
    timm_kwargs = {
        'img_size': 224,
        'patch_size': 14,
        'depth': 24,
        'num_heads': 24,
        'init_values': 1e-5,
        'embed_dim': 1536,
        'mlp_ratio': 2.66667 * 2,
        'num_classes': 0,         # no classifier head
        'no_embed_class': True,
        'mlp_layer': timm.layers.SwiGLUPacked,
        'act_layer': torch.nn.SiLU,
        'reg_tokens': 8,
        'dynamic_img_size': True
    }

    model = timm.create_model(
        "hf-hub:MahmoodLab/UNI2-h",
        pretrained=True,
        **timm_kwargs
    )
    model.eval()
    model.to(device)
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
def obtain_embedding(dataloader, model, device):
    all_embeddings = []
    all_filenames = []

    for images, filenames in dataloader:
        images = images.to(device, non_blocking=True)

        # If you do not need mixed precision, remove autocast completely
        with torch.inference_mode(), autocast(enabled=(device.type == 'cuda')):
            # The model output should be of shape (batch_size, 1536)
            features = model(images)

        # Ensure it's at least 2D
        if features.dim() == 1:
            features = features.unsqueeze(0)

        features = features.cpu()  # move to CPU
        all_embeddings.append(features)
        all_filenames.extend(filenames)

    # Concatenate along batch dimension
    embeddings_tensor = torch.cat(all_embeddings, dim=0)
    return embeddings_tensor, all_filenames

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
def main(
    patch_dir,
    output_dir="./output_embeddings",
    output_csv_name="embeddings_colon.csv", # Specify your .csv file name with the features
    batch_size=32
):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Running on device = {device}")

    # 6.1. Initialize UNI2 model
    model = init_uni2_model(device)

    # 6.2. Define transform for the model
    transform = get_uni2_transform(model)

    # 6.3. Create dataset and dataloader
    dataset = ImageDataset(patch_dir, transform=transform)
    dataloader = DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=4,
        pin_memory=True
    )

    # 6.4. Extract embeddings
    embeddings_tensor, filenames = obtain_embedding(dataloader, model, device)

    # 6.5. Save embeddings (dim) + file names into a CSV file
    os.makedirs(output_dir, exist_ok=True)
    output_csv_path = os.path.join(output_dir, output_csv_name)
    save_embeddings_to_csv(embeddings_tensor, filenames, output_csv_path)

if __name__ == "__main__":
    patch_dir = r"C:\Users\LA0122630\Documents\Kassab_UniClusteringPancreas\02_ROI_patches" # Specify your input patch folder here
    main(patch_dir)