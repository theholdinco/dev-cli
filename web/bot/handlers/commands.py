"""Command-oriented Telegram handlers: send, diff, logs, pr, sync."""

from telegram import Update
from telegram.ext import ContextTypes

from bot.auth import authorized
from bot.formatters import format_command_result, truncate, code_block
from core.sessions import get_session, get_preview
from core.commands import send_to_session, get_diff, get_logs, create_pr, sync_session


@authorized
async def cmd_send(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /send <session> <prompt> — everything after session name is the prompt."""
    if not context.args or len(context.args) < 2:
        await update.message.reply_text("Usage: /send <session> <prompt>")
        return

    name = context.args[0]
    prompt = " ".join(context.args[1:])

    session = get_session(name)
    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    if not session.alive:
        await update.message.reply_text(f"Session '{session.name}' is not running.")
        return

    await update.message.reply_text(f"Sending to {session.name}...")

    result = send_to_session(session.name, prompt)
    text = format_command_result(result)
    await update.message.reply_text(truncate(text))


@authorized
async def cmd_diff(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /diff <session> — show git diff."""
    if not context.args:
        await update.message.reply_text("Usage: /diff <session>")
        return

    name = context.args[0]
    session = get_session(name)

    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    result = get_diff(session.name)

    if result.success:
        output = result.output.strip()
        if not output:
            await update.message.reply_text("No changes.")
        else:
            text = code_block(output, "diff")
            await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")
    else:
        error = result.error.strip() if result.error else "Failed to get diff."
        await update.message.reply_text(f"\u274c {error}")


@authorized
async def cmd_logs(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /logs <session> [lines] — show recent agent output."""
    if not context.args:
        await update.message.reply_text("Usage: /logs <session> [lines]")
        return

    name = context.args[0]
    lines = 30

    if len(context.args) >= 2:
        try:
            lines = int(context.args[1])
            lines = min(max(lines, 1), 200)
        except ValueError:
            await update.message.reply_text("Lines must be a number.")
            return

    session = get_session(name)
    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    # Try getting preview from tmux pane first, fall back to dev logs
    preview = get_preview(session.name, lines=lines)
    if preview.strip():
        text = code_block(preview.strip())
        await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")
    else:
        result = get_logs(session.name)
        if result.success and result.output.strip():
            text = code_block(result.output.strip())
            await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")
        else:
            await update.message.reply_text("No log output available.")


@authorized
async def cmd_pr(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /pr <session> [--draft] — create a pull request."""
    if not context.args:
        await update.message.reply_text("Usage: /pr <session> [--draft]")
        return

    name = context.args[0]
    draft = "--draft" in context.args[1:]

    session = get_session(name)
    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    await update.message.reply_text(f"Creating PR for {session.name}...")

    result = create_pr(session.name, draft=draft)
    text = format_command_result(result)
    await update.message.reply_text(truncate(text))


@authorized
async def cmd_sync(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /sync <session> — sync upstream."""
    if not context.args:
        await update.message.reply_text("Usage: /sync <session>")
        return

    name = context.args[0]
    session = get_session(name)

    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    await update.message.reply_text(f"Syncing {session.name}...")

    result = sync_session(session.name)
    text = format_command_result(result)
    await update.message.reply_text(truncate(text))
