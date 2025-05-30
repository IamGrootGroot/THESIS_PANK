#!/bin/bash

# =============================================================================
# Test script for Google Drive upload functionality
# =============================================================================

echo "Testing Google Drive upload functionality..."

# Check required files
CREDENTIALS_FILE="drive_credentials.json"
TOKEN_FILE="token.json"
UPLOAD_SCRIPT="upload_qc_thumbnails_to_drive.py"

echo "Checking required files..."

if [ ! -f "$TOKEN_FILE" ]; then
    echo "❌ Token file not found: $TOKEN_FILE"
    echo "Please run: python3 generate_drive_token.py --credentials_file $CREDENTIALS_FILE"
    exit 1
else
    echo "✅ Token file found: $TOKEN_FILE"
fi

if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "⚠️  Credentials file not found: $CREDENTIALS_FILE (optional if token is valid)"
else
    echo "✅ Credentials file found: $CREDENTIALS_FILE"
fi

if [ ! -f "$UPLOAD_SCRIPT" ]; then
    echo "❌ Upload script not found: $UPLOAD_SCRIPT"
    exit 1
else
    echo "✅ Upload script found: $UPLOAD_SCRIPT"
fi

# Check Python dependencies
echo "Checking Python dependencies..."
python3 -c "
try:
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload
    print('✅ All required Python packages are installed')
except ImportError as e:
    print(f'❌ Missing Python package: {e}')
    print('Please install: pip install google-api-python-client google-auth-httplib2 google-auth-oauthlib')
    exit(1)
"

if [ $? -ne 0 ]; then
    exit 1
fi

# Create a test directory with a dummy image
TEST_DIR="test_qc_upload"
mkdir -p "$TEST_DIR"

# Create a simple test image (1x1 pixel PNG)
echo "Creating test image..."
python3 -c "
from PIL import Image
import os
img = Image.new('RGB', (100, 100), color='red')
img.save('$TEST_DIR/test_qc_thumbnail.jpg')
print('✅ Test image created: $TEST_DIR/test_qc_thumbnail.jpg')
"

if [ $? -ne 0 ]; then
    echo "❌ Failed to create test image. Installing Pillow..."
    pip3 install Pillow
    python3 -c "
from PIL import Image
img = Image.new('RGB', (100, 100), color='red')
img.save('$TEST_DIR/test_qc_thumbnail.jpg')
print('✅ Test image created: $TEST_DIR/test_qc_thumbnail.jpg')
"
fi

# Test the upload
echo "Testing upload to Google Drive..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FOLDER_NAME="Test_QC_Upload_${TIMESTAMP}"

if [ -f "$CREDENTIALS_FILE" ]; then
    python3 "$UPLOAD_SCRIPT" \
        --qc_thumbnails_dir "$TEST_DIR" \
        --folder_name "$FOLDER_NAME" \
        --credentials_file "$CREDENTIALS_FILE" \
        --token_file "$TOKEN_FILE"
else
    python3 "$UPLOAD_SCRIPT" \
        --qc_thumbnails_dir "$TEST_DIR" \
        --folder_name "$FOLDER_NAME" \
        --token_file "$TOKEN_FILE"
fi

if [ $? -eq 0 ]; then
    echo "✅ Upload test successful!"
    echo "Check your Google Drive for folder: $FOLDER_NAME"
else
    echo "❌ Upload test failed!"
    echo "Check the error messages above for troubleshooting"
fi

# Cleanup
echo "Cleaning up test files..."
rm -rf "$TEST_DIR"
echo "✅ Test completed" 