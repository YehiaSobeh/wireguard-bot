#main.py
import logging
import os
import subprocess
import qrcode
import glob
from datetime import datetime, timedelta
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from db import SessionLocal, User, Client
from config import WIREGUARD_SCRIPT_PATH

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("wireguard-backend")

app = FastAPI()

class CreateClientRequest(BaseModel):
    telegram_id: int
    username: str
    duration_days: int

@app.post("/create_client")
def create_client(req: CreateClientRequest):
    logger.info("Received create_client request: %s", req)
    telegram_id = req.telegram_id
    username = req.username
    duration_days = req.duration_days

    try:
        db = SessionLocal()
    except Exception as e:
        logger.exception("Database connection failed")
        raise HTTPException(500, "Database connection failed")

    try:
        user = db.query(User).filter_by(telegram_id=telegram_id).first()
        if not user:
            user = User(telegram_id=telegram_id, username=username)
            db.add(user)
            db.commit()
    except Exception as e:
        logger.exception("Failed to get or create user")
        raise HTTPException(500, "Database operation failed")

    client_name = f"{username}_{int(datetime.utcnow().timestamp())}"
    expires_at = datetime.utcnow() + timedelta(days=duration_days)

    if not os.path.exists(WIREGUARD_SCRIPT_PATH):
        logger.error("WireGuard script not found at %s", WIREGUARD_SCRIPT_PATH)
        raise HTTPException(500, f"Script not found at {WIREGUARD_SCRIPT_PATH}")

    # Run the WireGuard script to create a client
    script_input = f"1\n{client_name}\n\n\n"
    try:
        result = subprocess.run(
            [WIREGUARD_SCRIPT_PATH],
            input=script_input,
            text=True,
            capture_output=True,
            check=True
        )
        logger.info("WireGuard script output: %s", result.stdout)
    except subprocess.CalledProcessError as e:
        logger.exception("WireGuard script failed: %s", e.stderr)
        raise HTTPException(500, f"WireGuard script failed: {e.stderr}")

    # --- FIX: Find the latest client conf file automatically ---
    matching_files = glob.glob("/root/wg0-client-*.conf")
    if not matching_files:
        existing_files = os.listdir("/root")
        logger.error(
            "No WireGuard client configs found in /root. Existing files: %s", existing_files
        )
        raise HTTPException(500, "No WireGuard client configs found")

    # Take the newest file based on creation time
    client_conf_path = max(matching_files, key=os.path.getctime)
    logger.info("Using client config: %s", client_conf_path)

    # Read the config file
    try:
        with open(client_conf_path, "r") as f:
            config_data = f.read()
    except Exception as e:
        logger.exception("Failed to read config file")
        raise HTTPException(500, "Failed to read config file")

    # Generate QR code
    qr_path = f"/tmp/{os.path.basename(client_conf_path)}.png"
    try:
        img = qrcode.make(config_data)
        img.save(qr_path)
    except Exception as e:
        logger.exception("Failed to generate QR code")
        raise HTTPException(500, "Failed to generate QR code")

    # Save client to DB
    try:
        client = Client(user_id=user.id, client_name=os.path.basename(client_conf_path), expires_at=expires_at)
        db.add(client)
        db.commit()
    except Exception as e:
        logger.exception("Failed to save client to database")
        raise HTTPException(500, "Failed to save client to database")

    logger.info("Client %s created successfully", client_name)
    return {
        "client": client_name,
        "expires_at": expires_at,
        "config_path": client_conf_path,
        "qr_path": qr_path,
        "config_content": config_data
    }
