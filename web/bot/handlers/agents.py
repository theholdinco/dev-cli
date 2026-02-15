"""Agent management Telegram command handlers."""

from telegram import Update
from telegram.ext import ContextTypes

from bot.auth import authorized
from bot.formatters import escape_md, bold, mono, truncate
from core.sessions import get_session
from core.commands import agent_add, agent_remove


@authorized
async def cmd_agent_add(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /agent_add <session> <type> command."""
    if not context.args or len(context.args) < 2:
        await update.message.reply_text("Usage: /agent_add <session> <type>\nTypes: claude, codex")
        return

    name = context.args[0]
    agent_type = context.args[1]

    session = get_session(name)
    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    if agent_type not in ("claude", "codex"):
        await update.message.reply_text(f"Invalid agent type '{agent_type}'. Use 'claude' or 'codex'.")
        return

    await update.message.reply_text(f"Adding {agent_type} to {session.name}...")

    result = agent_add(session.name, agent_type)

    if result.success:
        output = result.output.strip() if result.output else f"Agent {agent_type} added."
        await update.message.reply_text(f"\u2705 {output}")
    else:
        error = result.error.strip() if result.error else "Failed to add agent."
        await update.message.reply_text(f"\u274c {error}")


@authorized
async def cmd_agent_remove(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /agent_remove <session> <type> command."""
    if not context.args or len(context.args) < 2:
        await update.message.reply_text("Usage: /agent_remove <session> <type>\nTypes: claude, codex")
        return

    name = context.args[0]
    agent_type = context.args[1]

    session = get_session(name)
    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    await update.message.reply_text(f"Removing {agent_type} from {session.name}...")

    result = agent_remove(session.name, agent_type)

    if result.success:
        output = result.output.strip() if result.output else f"Agent {agent_type} removed."
        await update.message.reply_text(f"\u2705 {output}")
    else:
        error = result.error.strip() if result.error else "Failed to remove agent."
        await update.message.reply_text(f"\u274c {error}")


@authorized
async def cmd_agent_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /agent_list <session> command."""
    if not context.args:
        await update.message.reply_text("Usage: /agent_list <session>")
        return

    name = context.args[0]
    session = get_session(name)

    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    if not session.agents:
        text = f"No agents running in {bold(escape_md(session.name))}"
    else:
        agents_list = "\n".join(f"  \\- {mono(a)}" for a in session.agents)
        text = f"\U0001f916 Agents in {bold(escape_md(session.name))}:\n{agents_list}"

    await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")
