# wireguard-bot
🛡️ WireGuard Manager Bot

A complete automation system to manage WireGuard VPN clients via a Telegram bot.
Built with FastAPI, Python-Telegram-Bot, SQLAlchemy, and Bash scripting.

🚀 Features

✅ Create VPN clients directly from Telegram
✅ Auto-generate .conf and QR code for easy import
✅ Track users and clients in database
✅ Automatic expiration cleanup
✅ Lightweight, fast, and works entirely on your server

🧩 System Architecture
Telegram User ─▶ Telegram Bot ─▶ FastAPI Backend ─▶ WireGuard Script
                                  │
                                  ├── SQLite DB (User + Client)
                                  └── QR Code Generator

📦 Requirements

Linux with root access

WireGuard installed

Python 3.9+

Telegram Bot Token

⚙️ Installation
1️⃣ Clone and setup
cd /opt/wireguard-server/
git clone git@github.com:YehiaSobeh/wireguard-bot.git
cd wireguard-bot

2️⃣ Install dependencies
pip install -r requirements.txt

3️⃣ Set config

Create config.py:

TELEGRAM_BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"
WIREGUARD_SCRIPT_PATH = "/opt/wireguard-server/wireguard-bot/wireguard-install.sh"

4️⃣ Start the backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000

5️⃣ Start the Telegram bot
python3 bot.py

6️⃣ (Optional) Start scheduler
from scheduler import start_scheduler
start_scheduler()

💬 Bot Commands
Command	Description
/start	Show welcome/help message
/create <days>	Create new VPN client valid for <days> days
🧠 How It Works

User requests client → bot sends request to FastAPI.

FastAPI calls wireguard-install.sh → new config generated.

FastAPI reads config → generates QR → saves in DB.

Bot sends config + QR back to user.

📅 Expiration Handling

A background scheduler (scheduler.py) runs every hour:

Checks expired clients.

Removes them using the WireGuard script.

Marks them inactive in the DB.

🧰 Technologies Used
Component	Tech
Backend API	FastAPI
Bot	Python-Telegram-Bot
Database	SQLite + SQLAlchemy
Automation	Bash (WireGuard script)
Scheduler	APScheduler
QR Generator	qrcode Python library
🧑‍💻 Developer Notes

Run backend as root or ensure it has permission to access /root/wg0-client-*.conf.

You can change storage paths in WIREGUARD_SCRIPT_PATH and main.py.

Logs are stored directly in console output via Python’s logging.