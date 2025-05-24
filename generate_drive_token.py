#!/usr/bin/env python3
"""
Generate Google Drive Token Script

This script helps generate a token.json file that can be used for
Google Drive API authentication without browser interaction.

Run this script locally (on a machine with a browser) first, then
transfer the generated token.json to your server.
"""

import os
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Google Drive API scope
SCOPES = ['https://www.googleapis.com/auth/drive.file']

def generate_token(credentials_file):
    """
    Generate a new token.json file using the provided credentials.
    """
    creds = None
    token_file = 'token.json'

    if os.path.exists(token_file):
        logger.info(f"Found existing token file: {token_file}")
        try:
            creds = Credentials.from_authorized_user_file(token_file, SCOPES)
        except Exception as e:
            logger.warning(f"Error reading existing token: {e}")
            creds = None

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            logger.info("Refreshing expired token...")
            creds.refresh(Request())
        else:
            logger.info("Generating new token through OAuth flow...")
            flow = InstalledAppFlow.from_client_secrets_file(credentials_file, SCOPES)
            creds = flow.run_local_server(port=0)

        # Save the credentials for future use
        with open(token_file, 'w') as token:
            token.write(creds.to_json())
            logger.info(f"Token saved to {token_file}")

    # Verify the token works
    try:
        service = build('drive', 'v3', credentials=creds)
        about = service.about().get(fields="user").execute()
        logger.info(f"Successfully authenticated as: {about['user']['emailAddress']}")
    except Exception as e:
        logger.error(f"Error verifying token: {e}")
        return False

    return True

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Generate Google Drive API token file.")
    parser.add_argument("--credentials_file", type=str, required=True,
                      help="Path to the Google Drive API credentials JSON file.")
    
    args = parser.parse_args()
    
    if generate_token(args.credentials_file):
        logger.info("Token generation successful! You can now copy token.json to your server.")
    else:
        logger.error("Token generation failed!") 