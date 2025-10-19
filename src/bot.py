#bot.py
import os
import requests
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, ContextTypes
from config import TELEGRAM_BOT_TOKEN as BOT_TOKEN
#BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"
BACKEND_URL = "http://127.0.0.1:8000"  # adjust if backend runs on another server

# /start command
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "👋 Welcome to WireGuard Manager Bot!\n"
        "Use /create <days> to create a VPN client.\nExample: /create 30"
    )

# /create <days> command
async def create_client(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if len(context.args) != 1:
        await update.message.reply_text("❗️Usage: /create <duration_days>")
        return

    duration_days = context.args[0]
    if not duration_days.isdigit():
        await update.message.reply_text("⚠️ Duration must be a number of days.")
        return

    telegram_id = update.effective_chat.id
    username = update.effective_user.username or "user"

    await update.message.reply_text("⏳ Creating your VPN client...")

    try:
        response = requests.post(
            f"{BACKEND_URL}/create_client",
            json={
                "telegram_id": telegram_id,
                "username": username,
                "duration_days": int(duration_days),
            },
            timeout=180
        )

        if response.status_code != 200:
            await update.message.reply_text(f"❌ Error: {response.text}")
            return

        data = response.json()
        client_name = data["client"]
        qr_path = data["qr_path"]
        config_path = data["config_path"]

        # Send config file
        if config_path and os.path.exists(config_path):
            await context.bot.send_document(
                chat_id=update.effective_chat.id,
                document=open(config_path, "rb"),
                filename=f"{client_name}.conf",
                caption=f"📄 WireGuard Config for {client_name}"
            )

        # Send QR code
        if qr_path and os.path.exists(qr_path):
            await context.bot.send_photo(
                chat_id=update.effective_chat.id,
                photo=open(qr_path, "rb"),
                caption=f"🔐 Scan this QR to import {client_name}"
            )

        await update.message.reply_text(f"✅ VPN client `{client_name}` created successfully!")

    except Exception as e:
        await update.message.reply_text(f"🚨 Internal error: {e}")

# Run the bot
def main():
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("create", create_client))

    print("🤖 Bot is running...")
    app.run_polling()

if __name__ == "__main__":
    main()
