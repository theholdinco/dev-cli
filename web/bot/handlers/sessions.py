"""Session management Telegram command handlers."""

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes

from bot.auth import authorized
from bot.formatters import (
    format_session,
    format_session_list,
    truncate,
    escape_md,
    bold,
    mono,
)
from core.sessions import list_sessions, get_session
from core.commands import new_session, kill_session, restart_session


HELP_TEXT = """Available commands:

*Session Management*
/ls \\- List active sessions
/ls all \\- List all sessions
/status \\<session\\> \\- Session details
/new \\<project\\> \\<branch\\> \\[agent\\] \\[\\-\\-from base\\] \\[\\-\\-yolo\\] \\- Create session
/kill \\<session\\> \\- Kill session
/restart \\<session\\> \\- Restart session

*Agent Management*
/agent\\_add \\<session\\> \\<type\\> \\- Add agent
/agent\\_remove \\<session\\> \\<type\\> \\- Remove agent
/agent\\_list \\<session\\> \\- List agents

*Commands*
/send \\<session\\> \\<prompt\\> \\- Send prompt to agent
/diff \\<session\\> \\- Show git diff
/logs \\<session\\> \\[lines\\] \\- Show recent output
/pr \\<session\\> \\[\\-\\-draft\\] \\- Create PR
/sync \\<session\\> \\- Sync upstream

*System*
/stats \\- Server resource usage
/ports \\- Port allocation table
/doctor \\- Run diagnostics
/url \\<session\\> \\- Show access URLs
/gc \\- Garbage collection"""


@authorized
async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start and /help commands."""
    welcome = f"\U0001f680 {bold('dev-cli Telegram Bot')}\n\n{HELP_TEXT}"
    await update.message.reply_text(welcome, parse_mode="MarkdownV2")


@authorized
async def cmd_ls(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /ls command. Optional 'all' argument to show dead sessions."""
    show_all = bool(context.args and context.args[0].lower() in ("all", "--all", "-a"))
    sessions = list_sessions(show_all=show_all)
    text = format_session_list(sessions)
    await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")


@authorized
async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status <session> command."""
    if not context.args:
        await update.message.reply_text("Usage: /status <session_name>")
        return

    name = context.args[0]
    session = get_session(name)

    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    text = format_session(session)
    await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")


@authorized
async def cmd_new(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /new <project> <branch> [agent] [--from base] [--yolo] command."""
    if not context.args or len(context.args) < 2:
        await update.message.reply_text("Usage: /new <project> <branch> [agent] [--from base] [--yolo]")
        return

    project = context.args[0]
    branch = context.args[1]
    agent = "claude"
    yolo = False
    from_branch = ""

    remaining = context.args[2:]
    i = 0
    while i < len(remaining):
        arg = remaining[i]
        if arg == "--yolo":
            yolo = True
        elif arg == "--from" and i + 1 < len(remaining):
            i += 1
            from_branch = remaining[i]
        elif arg in ("claude", "codex"):
            agent = arg
        i += 1

    msg = f"Creating session {project}/{branch}"
    if from_branch:
        msg += f" (from {from_branch})"
    msg += f" with {agent}..."
    await update.message.reply_text(msg)

    result = new_session(project, branch, agent=agent, yolo=yolo, from_branch=from_branch)

    if result.success:
        output = result.output.strip() if result.output else "Session created."
        await update.message.reply_text(f"\u2705 {output}")
    else:
        error = result.error.strip() if result.error else "Failed to create session."
        await update.message.reply_text(f"\u274c {error}")


@authorized
async def cmd_kill(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /kill <session> — shows confirmation inline keyboard."""
    if not context.args:
        await update.message.reply_text("Usage: /kill <session_name>")
        return

    name = context.args[0]
    session = get_session(name)

    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    keyboard = InlineKeyboardMarkup([
        [
            InlineKeyboardButton("\u2620\ufe0f Yes, kill", callback_data=f"kill_confirm:{session.name}"),
            InlineKeyboardButton("\u274e Cancel", callback_data="kill_cancel"),
        ]
    ])

    await update.message.reply_text(
        f"Kill session *{escape_md(session.name)}*?",
        reply_markup=keyboard,
        parse_mode="MarkdownV2",
    )


async def callback_kill(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle kill confirmation/cancel callback from inline keyboard."""
    query = update.callback_query
    await query.answer()

    data = query.data
    if data == "kill_cancel":
        await query.edit_message_text("Cancelled.")
        return

    if data.startswith("kill_confirm:"):
        name = data.split(":", 1)[1]
        await query.edit_message_text(f"Killing {name}...")

        result = kill_session(name)

        if result.success:
            output = result.output.strip() if result.output else "Session killed."
            await query.edit_message_text(f"\u2705 {output}")
        else:
            error = result.error.strip() if result.error else "Failed to kill session."
            await query.edit_message_text(f"\u274c {error}")


@authorized
async def cmd_restart(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /restart <session> command."""
    if not context.args:
        await update.message.reply_text("Usage: /restart <session_name>")
        return

    name = context.args[0]
    session = get_session(name)

    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    await update.message.reply_text(f"Restarting {session.name}...")

    result = restart_session(session.name)

    if result.success:
        output = result.output.strip() if result.output else "Session restarted."
        await update.message.reply_text(f"\u2705 {output}")
    else:
        error = result.error.strip() if result.error else "Failed to restart session."
        await update.message.reply_text(f"\u274c {error}")
