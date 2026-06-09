#!/usr/bin/env python3
"""
BlackbeardBot: Backup verified_members.json to Google Drive.

Replaces the legacy cron-based backup. Reads config from env:
    GOOGLE_DRIVE_FOLDER_ID   — Google Drive folder ID for backups
    GOOGLE_CLIENT_SECRET     — path to OAuth client secret JSON (default: /etc/blackbeard-bot/credentials/gdrive_client_secret.json)
    GOOGLE_TOKEN_FILE         — path to persisted OAuth token (default: /etc/blackbeard-bot/credentials/token_gdrive.json)
    VERIFIED_MEMBERS_FILE     — path to verified_members.json source (default: data/verified_members.json)

On first run, opens an OAuth flow. Subsequent runs use the cached token.
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload


SCOPES = ["https://www.googleapis.com/auth/drive.file"]

FOLDER_ID = os.environ.get("GOOGLE_DRIVE_FOLDER_ID", "12ZScVdqRwwvzrQsABoc5D2Cs7rVQ_l4T")

# Resolve paths relative to the repo root (WorkingDirectory in systemd unit)
REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.environ.get("DATA_DIR", str(REPO_ROOT / "data")))
CREDENTIALS_DIR = Path("/etc/blackbeard-bot/credentials")
CLIENT_SECRET = os.environ.get(
    "GOOGLE_CLIENT_SECRET",
    str(CREDENTIALS_DIR / "gdrive_client_secret.json")
)
TOKEN_FILE = os.environ.get("GOOGLE_TOKEN_FILE", str(CREDENTIALS_DIR / "token_gdrive.json"))
SOURCE_FILE = os.environ.get("VERIFIED_MEMBERS_FILE", str(DATA_DIR / "verified_members.json"))


def authenticate() -> Credentials:
    creds = None
    token_path = Path(TOKEN_FILE)
    if token_path.exists():
        creds = Credentials.from_authorized_user_file(str(token_path), SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(CLIENT_SECRET, SCOPES)
            creds = flow.run_local_server(port=59587)
        token_path.parent.mkdir(parents=True, exist_ok=True)
        token_path.write_text(creds.to_json(), encoding="utf-8")
    return creds


def upload(service, source_path: Path) -> None:
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    filename = f"{timestamp}_verified_members.json"

    metadata = {"name": filename, "parents": [FOLDER_ID]}
    media = MediaFileUpload(str(source_path), mimetype="application/json", resumable=True)
    file = (
        service.files()
        .create(body=metadata, media_body=media, fields="id")
        .execute()
    )
    print(f"Uploaded {filename} (id={file['id']})")


def main() -> int:
    source = Path(SOURCE_FILE)
    if not source.exists():
        print(f"Source file not found: {source}", file=sys.stderr)
        return 1

    try:
        creds = authenticate()
    except Exception as e:
        print(f"Authentication failed: {e}", file=sys.stderr)
        return 1

    service = build("drive", "v3", credentials=creds)
    upload(service, source)
    return 0


if __name__ == "__main__":
    sys.exit(main())