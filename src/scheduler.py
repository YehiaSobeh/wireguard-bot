import os
import time
import logging
from datetime import datetime
from db import SessionLocal, Client

logger = logging.getLogger("wireguard-scheduler")


def cleanup_expired_clients(interval_hours: int = 1):
    """Continuously runs every X hours to clean up expired WireGuard clients."""
    while True:
        try:
            db = SessionLocal()
            now = datetime.utcnow()
            expired_clients = db.query(Client).filter(Client.expires_at < now).all()

            if expired_clients:
                logger.info("🧹 Found %d expired clients to clean up", len(expired_clients))
            else:
                logger.info("✅ No expired clients found")

            for client in expired_clients:
                conf_paths = [
                    f"/root/{client.client_name}.conf",
                    f"/root/wg0-client-{client.client_name}.conf",
                    f"/tmp/{client.client_name}.png",
                ]

                for path in conf_paths:
                    if os.path.exists(path):
                        os.remove(path)
                        logger.info("🗑️ Deleted file: %s", path)

                db.delete(client)
                db.commit()
                logger.info("✅ Removed client '%s' from DB", client.client_name)

        except Exception as e:
            logger.exception("❌ Error during cleanup: %s", e)

        time.sleep(interval_hours * 3600)
