# wireguard-bot

Self-hosted WireGuard VPN management through Telegram. A user sends `/create 30`, the bot asks a FastAPI backend to provision a WireGuard client, and the user gets back a `.conf` file and a QR code to scan. A scheduler removes expired clients automatically.

Built with FastAPI, python-telegram-bot, SQLAlchemy, APScheduler, and Bash, running entirely on your own Linux server. No third-party VPN service, no manual `wg` commands.

## Why it matters

Running a personal or small-team VPN usually means SSH-ing into the server for every new device and never cleaning up old peers. This bot turns provisioning into a chat command and makes expiry the default, so stale peers do not accumulate.

![Bot conversation](docs/demo.png)
*[ADD SCREENSHOT: docs/demo.png, the Telegram conversation showing /create and the returned QR code]*

## Architecture

```
Telegram user ──▶ Telegram bot (bot.py) ──▶ FastAPI backend (main.py) ──▶ wireguard-install.sh
                                                  │
                                                  ├── SQLite via SQLAlchemy (users, clients, expiry)
                                                  ├── QR code generator (qrcode)
                                                  └── scheduler.py: hourly cleanup of expired clients
```

## Tech stack

| Component | Technology |
|---|---|
| Backend API | FastAPI, Pydantic |
| Bot | python-telegram-bot |
| Database | SQLite + SQLAlchemy |
| Provisioning | Bash (WireGuard install script) |
| Scheduler | APScheduler |
| QR codes | qrcode |

## Requirements

- Linux server with root access and WireGuard installed
- Python 3.9+
- A Telegram bot token from @BotFather

## How to run

```bash
cd /opt/wireguard-server/
git clone git@github.com:YehiaSobeh/wireguard-bot.git
cd wireguard-bot/src
pip install -r requirements.txt
```

Create `config.py`:

```python
TELEGRAM_BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"
WIREGUARD_SCRIPT_PATH = "/opt/wireguard-server/wireguard-bot/src/wireguard-install.sh"
```

Start the three processes (as root, or as a user that can read `/root/wg0-client-*.conf`):

```bash
uvicorn main:app --host 0.0.0.0 --port 8000     # backend
python3 bot.py                                   # Telegram bot
python3 -c "from scheduler import start_scheduler; start_scheduler()"   # optional cleanup
```

For a permanent install, wrap each process in a systemd unit.

## Bot commands

| Command | Description |
|---|---|
| `/start` | Welcome and help |
| `/create <days>` | Create a new VPN client valid for `<days>` days |

## How it works

1. The bot forwards the request to `POST /create_client` with the Telegram ID, username, and duration.
2. The backend creates or finds the user, runs the WireGuard script to generate a new peer, reads the resulting config, renders a QR code, and stores the client with its expiry date.
3. The bot sends the config file and QR image back to the user.
4. Every hour the scheduler removes clients past their expiry from WireGuard and marks them inactive.

## Security notes

- The backend executes a shell script as root. Keep it bound to localhost or a private interface and do not expose port 8000 publicly.
- Config files contain private keys. They are deleted from disk after being sent.
- [ADD: whether the bot restricts who may call /create, e.g. an allowlist of Telegram IDs]

## What I learned

- Driving a system tool from a web service means thinking about the process boundary: exit codes, file paths, and permissions are the API.
- Expiry as a first-class field, with a cleanup loop, is what makes the system safe to leave running.
