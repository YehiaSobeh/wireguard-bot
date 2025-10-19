#scheduler.py
from apscheduler.schedulers.background import BackgroundScheduler
from db import SessionLocal, Client
from datetime import datetime
import subprocess
from config import WIREGUARD_SCRIPT_PATH

def remove_expired_clients():
    db = SessionLocal()
    now = datetime.utcnow()
    expired = db.query(Client).filter(Client.expires_at < now, Client.active == True).all()
    for client in expired:
        subprocess.run([WIREGUARD_SCRIPT_PATH, "--removeclient", client.client_name], check=False)
        client.active = False
    db.commit()

def start_scheduler():
    scheduler = BackgroundScheduler()
    scheduler.add_job(remove_expired_clients, "interval", hours=1)
    scheduler.start()
