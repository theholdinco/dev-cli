"""System-level Telegram command handlers."""

from telegram import Update
from telegram.ext import ContextTypes

from bot.auth import authorized
from bot.formatters import (
    format_ports_table,
    format_command_result,
    truncate,
    escape_md,
    bold,
    mono,
    code_block,
)
from core.sessions import list_sessions, get_session, get_ip
from core.system import get_stats
from core.commands import run_doctor, run_gc


@authorized
async def cmd_stats(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /stats — show server resource usage."""
    stats = get_stats()
    mem = stats["memory"]
    disk = stats["disk"]

    header = f"\U0001f4ca {bold(escape_md(stats['hostname']))}"

    body_lines = [
        f"Host:      {stats['ip']}  |  {stats['cpu_count']} CPUs",
        f"Uptime:    {stats['uptime']}",
        f"Load:      {stats['load']}",
        "",
        f"Memory:    {mem['used']} / {mem['total']}  ({mem['available']} free)",
        f"Disk:      {disk['used']} / {disk['total']}  ({disk['percent']})",
        "",
        f"Sessions:  {stats['sessions_alive']} alive / {stats['sessions_total']} total",
    ]

    text = header + "\n\n" + code_block("\n".join(body_lines))
    await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")


@authorized
async def cmd_ports(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /ports — show port allocation table."""
    import os
    requesting_user = os.environ.get("USER", "")
    sessions = list_sessions(show_all=True, requesting_user=requesting_user)
    text = format_ports_table(sessions)
    await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")


@authorized
async def cmd_doctor(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /doctor — run diagnostics."""
    await update.message.reply_text("Running diagnostics...")

    result = run_doctor()

    if result.success:
        output = result.output.strip() if result.output else "All checks passed."
        text = code_block(output)
        await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")
    else:
        text = format_command_result(result)
        await update.message.reply_text(truncate(text))


@authorized
async def cmd_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /url <session> — show access URLs."""
    if not context.args:
        await update.message.reply_text("Usage: /url <session>")
        return

    name = context.args[0]
    session = get_session(name)

    if not session:
        await update.message.reply_text(f"Session '{name}' not found.")
        return

    ip = get_ip()
    ports = session.ports

    lines = [bold(escape_md(f"URLs for {session.name}")), ""]

    fe = ports.get("frontend")
    be = ports.get("backend")
    supa_api = ports.get("supa_api")
    supa_studio = ports.get("supa_studio")

    if fe:
        lines.append(f"\U0001f310 Frontend: {mono(f'http://{ip}:{fe}')}")
    if be:
        lines.append(f"\u2699\ufe0f Backend: {mono(f'http://{ip}:{be}')}")
    if supa_api:
        lines.append(f"\U0001f5c4 Supabase API: {mono(f'http://{ip}:{supa_api}')}")
    if supa_studio:
        lines.append(f"\U0001f4ca Supabase Studio: {mono(f'http://{ip}:{supa_studio}')}")

    if not session.alive:
        lines.append("")
        lines.append(escape_md("(session is not currently running)"))

    text = "\n".join(lines)
    await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")


@authorized
async def cmd_gc(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /gc — run garbage collection."""
    await update.message.reply_text("Running garbage collection...")

    result = run_gc()
    text = format_command_result(result)
    await update.message.reply_text(truncate(text))
