#!/bin/bash

# =============================================================================
# Simple test for Google Drive upload on remote server
# =============================================================================

echo "Testing Google Drive upload on remote server..."

# Check required files
TOKEN_FILE="token.json"
CREDENTIALS_FILE="drive_credentials.json"
UPLOAD_SCRIPT="upload_qc_thumbnails_to_drive.py"

echo "Checking files..."
if [ ! -f "$TOKEN_FILE" ]; then
    echo "❌ Token file not found: $TOKEN_FILE"
    exit 1
fi
echo "✅ Token file found"

if [ ! -f "$UPLOAD_SCRIPT" ]; then
    echo "❌ Upload script not found: $UPLOAD_SCRIPT"
    exit 1
fi
echo "✅ Upload script found"

# Create test directory and file
TEST_DIR="test_upload_$(date +%s)"
mkdir -p "$TEST_DIR"
echo "Test QC thumbnail" > "$TEST_DIR/test_qc_thumbnail.txt"
echo "✅ Test directory created: $TEST_DIR"

# Test upload (same command as in the fixed script)
echo "Testing upload command..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

python3 "$UPLOAD_SCRIPT" \
    --qc_thumbnails_dir "$TEST_DIR" \
    --credentials_file "$CREDENTIALS_FILE" \
    --token_file "$TOKEN_FILE" \
    --folder_name "Test_Upload_${TIMESTAMP}"

if [ $? -eq 0 ]; then
    echo "✅ Upload successful!"
else
    echo "❌ Upload failed!"
fi

# Cleanup
rm -rf "$TEST_DIR"
echo "✅ Test completed" 