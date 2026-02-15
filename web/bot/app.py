"""Telegram bot initialization and entry point for dev-cli."""

import json
import logging
import sys
import traceback

from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, CallbackQueryHandler, ContextTypes

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

from core import GLOBAL_CONFIG
from bot.handlers.sessions import (
    cmd_start,
    cmd_ls,
    cmd_status,
    cmd_new,
    cmd_kill,
    cmd_restart,
    callback_kill,
)
from bot.handlers.agents import cmd_agent_add, cmd_agent_remove, cmd_agent_list
from bot.handlers.commands import cmd_send, cmd_diff, cmd_logs, cmd_pr, cmd_sync
from bot.handlers.system import cmd_stats, cmd_ports, cmd_doctor, cmd_url, cmd_gc


def get_bot_token() -> str:
    """Read bot_token from ~/.config/dev-cli/config.json."""
    try:
        with open(GLOBAL_CONFIG) as f:
            config = json.load(f)
        token = config.get("telegram", {}).get("bot_token", "")
        if not token:
            print("Error: telegram.bot_token not set in config.json", file=sys.stderr)
            sys.exit(1)
        return token
    except FileNotFoundError:
        print(f"Error: {GLOBAL_CONFIG} not found", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: {GLOBAL_CONFIG} is not valid JSON", file=sys.stderr)
        sys.exit(1)


def main():
    """Build and run the Telegram bot with polling."""
    token = get_bot_token()

    app = ApplicationBuilder().token(token).build()

    # Session management
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_start))
    app.add_handler(CommandHandler("ls", cmd_ls))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(CommandHandler("new", cmd_new))
    app.add_handler(CommandHandler("kill", cmd_kill))
    app.add_handler(CommandHandler("restart", cmd_restart))

    # Agent management
    app.add_handler(CommandHandler("agent_add", cmd_agent_add))
    app.add_handler(CommandHandler("agent_remove", cmd_agent_remove))
    app.add_handler(CommandHandler("agent_list", cmd_agent_list))

    # Commands
    app.add_handler(CommandHandler("send", cmd_send))
    app.add_handler(CommandHandler("diff", cmd_diff))
    app.add_handler(CommandHandler("logs", cmd_logs))
    app.add_handler(CommandHandler("pr", cmd_pr))
    app.add_handler(CommandHandler("sync", cmd_sync))

    # System
    app.add_handler(CommandHandler("stats", cmd_stats))
    app.add_handler(CommandHandler("ports", cmd_ports))
    app.add_handler(CommandHandler("doctor", cmd_doctor))
    app.add_handler(CommandHandler("url", cmd_url))
    app.add_handler(CommandHandler("gc", cmd_gc))

    # Inline keyboard callbacks (kill confirmation)
    app.add_handler(CallbackQueryHandler(callback_kill, pattern=r"^kill_"))

    # Error handler
    async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE):
        logger.error("Exception while handling an update:", exc_info=context.error)
        if isinstance(update, Update) and update.message:
            try:
                await update.message.reply_text(f"Error: {context.error}")
            except Exception:
                pass

    app.add_error_handler(error_handler)

    logger.info("Bot started. Polling for updates...")
    app.run_polling()


if __name__ == "__main__":
    main()
