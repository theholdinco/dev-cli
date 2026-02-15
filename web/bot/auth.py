import json
import functools
from core import GLOBAL_CONFIG


def get_allowed_ids():
    try:
        with open(GLOBAL_CONFIG) as f:
            config = json.load(f)
        return [int(x) for x in config.get("telegram", {}).get("allowed_chat_ids", [])]
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        return []


def authorized(func):
    @functools.wraps(func)
    async def wrapper(update, context):
        allowed = get_allowed_ids()
        if allowed and update.effective_chat.id not in allowed:
            await update.message.reply_text("\u26d4 Unauthorized.")
            return
        return await func(update, context)
    return wrapper
