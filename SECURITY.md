# Security Configuration

This repository has been configured for public release with the following security measures:

## Environment Variables

All sensitive information has been moved to environment variables:

### Required Variables
```bash
export HUGGING_FACE_TOKEN="your_huggingface_token_here"
export MODEL_PATH="/path/to/your/he_heavy_augment.pb"
```

### Optional Configuration
```bash
# QuPath installations (if not in default locations)
export QUPATH_06_PATH="/path/to/qupath_0.6/bin/QuPath"
export QUPATH_051_PATH="/path/to/qupath_0.5.1/bin/QuPath"

# Output directories
export TILES_OUTPUT="/path/to/tiles/output"
export OUTPUT_DIR="/path/to/general/output"
```

## Protected Files

The following files are automatically excluded from the repository:
- `token.json` - Google Drive authentication token
- `*credentials*.json` - Google Drive API credentials
- `drive_credentials.json` - Specific credentials file
- Model files (*.pb, *.h5, etc.) - Large trained models
- Output directories and generated files

## Removed Hardcoded Values

The following hardcoded values have been removed or made configurable:
- Personal directory paths (`/u/trinhvq/Documents/maxencepelloux/`)
- HuggingFace tokens
- Windows-specific paths (`C:/Users/...`)
- Fixed model paths

## Setup Instructions

1. **Set Environment Variables:**
   ```bash
   cp .env.example .env
   # Edit .env with your actual values
   source .env
   ```

2. **Configure Paths:**
   - QuPath installations: Set `QUPATH_06_PATH` and `QUPATH_051_PATH`
   - Model files: Set `MODEL_PATH` to your StarDist model
   - Output directories: Optionally set custom output paths

3. **Google Drive (Optional):**
   - Follow `GDRIVE_SETUP.md` for authentication setup
   - Keep credential files in your local directory (they're gitignored)

## Best Practices

- Never commit credential files or tokens
- Use environment variables for all sensitive configuration
- Keep model files in a separate directory (they're large and gitignored)
- Review `.gitignore` before committing new files 