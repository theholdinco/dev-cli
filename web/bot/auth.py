"""Authorization for the Telegram bot.

Only chats listed in telegram.allowed_chat_ids (config.json) may use the bot.
The check fails closed: a missing, empty or unreadable list means nobody is
allowed. The bot can start agents and send them prompts, so an open bot would
let any Telegram user run commands on this machine.
"""

import functools
import json
import logging

from core import GLOBAL_CONFIG

logger = logging.getLogger(__name__)

UNAUTHORIZED_TEXT = "⛔ Unauthorized."


def get_allowed_ids() -> set[int]:
    """Return the allowed chat ids from config.json.

    Returns an empty set (nobody allowed) when the file is missing or
    unreadable, the JSON is invalid, or any entry is not an integer chat id.
    """
    try:
        with open(GLOBAL_CONFIG) as f:
            config = json.load(f)
        ids = config.get("telegram", {}).get("allowed_chat_ids", [])
        if not isinstance(ids, list):
            raise ValueError("telegram.allowed_chat_ids must be a list")
        return {int(x) for x in ids}
    except Exception as e:  # any failure must deny, never allow
        logger.error(
            "Cannot read telegram.allowed_chat_ids from %s (%s): rejecting all Telegram updates",
            GLOBAL_CONFIG,
            e,
        )
        return set()


def is_authorized(update) -> bool:
    """True only if the update comes from a chat in the allowlist."""
    chat = getattr(update, "effective_chat", None)
    chat_id = getattr(chat, "id", None)
    if chat_id is None:
        logger.warning("Rejected Telegram update without a chat")
        return False

    allowed = get_allowed_ids()
    if not allowed:
        logger.warning(
            "Rejected Telegram update from chat %s: telegram.allowed_chat_ids is empty or unreadable, "
            "so the bot answers nobody. Add your chat id to %s to use the bot.",
            chat_id,
            GLOBAL_CONFIG,
        )
        return False
    if chat_id not in allowed:
        logger.warning("Rejected Telegram update from chat %s: not in telegram.allowed_chat_ids", chat_id)
        return False
    return True


async def deny(update) -> None:
    """Tell the sender they are not allowed, without failing if that is impossible."""
    try:
        query = getattr(update, "callback_query", None)
        if query is not None:
            await query.answer(UNAUTHORIZED_TEXT, show_alert=True)
            return
        message = getattr(update, "effective_message", None)
        if message is not None:
            await message.reply_text(UNAUTHORIZED_TEXT)
    except Exception:
        logger.debug("Could not send the unauthorized reply", exc_info=True)


def authorized(func):
    """Run the handler only for chats in telegram.allowed_chat_ids."""

    @functools.wraps(func)
    async def wrapper(update, context):
        if not is_authorized(update):
            await deny(update)
            return
        return await func(update, context)

    return wrapper
