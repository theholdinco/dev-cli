"""Telegram MarkdownV2 formatting helpers."""

import re
from core.sessions import SessionInfo, get_ip


TELEGRAM_MAX_LENGTH = 4096

_MD_ESCAPE_RE = re.compile(r'([_*\[\]()~`>#+\-=|{}.!\\])')


def escape_md(text: str) -> str:
    """Escape special MarkdownV2 characters."""
    return _MD_ESCAPE_RE.sub(r'\\\1', str(text))


def code_block(text: str, language: str = "") -> str:
    """Wrap text in a MarkdownV2 code block (triple backticks)."""
    # Inside code blocks, only ` and \ need escaping
    inner = str(text).replace('\\', '\\\\').replace('`', '\\`')
    lang = escape_md(language)
    return f"```{lang}\n{inner}\n```"


def bold(text: str) -> str:
    """Wrap text in MarkdownV2 bold markers."""
    return f"*{escape_md(text)}*"


def mono(text: str) -> str:
    """Wrap text in inline code (single backtick)."""
    inner = str(text).replace('\\', '\\\\').replace('`', '\\`')
    return f"`{inner}`"


def _status_emoji(session: SessionInfo) -> str:
    """Return a status emoji for a session."""
    if not session.alive:
        return "\u26aa"  # white circle - dead
    if session.git_dirty > 0:
        return "\U0001f7e1"  # yellow circle - dirty
    return "\U0001f7e2"  # green circle - alive & clean


def format_session(session: SessionInfo) -> str:
    """Format a SessionInfo into a detailed Telegram message using MarkdownV2."""
    status = _status_emoji(session)
    ip = get_ip()

    lines = [
        f"{status} {bold(session.name)}",
        "",
        f"\U0001f4c1 Project: {mono(session.project)}",
        f"\U0001f33f Branch: {mono(session.branch)}",
        f"\U0001f522 Slot: {mono(str(session.slot))}",
        f"\U0001f4be Status: {escape_md('alive' if session.alive else 'dead')}",
    ]

    if session.age:
        lines.append(f"\u23f1 Age: {escape_md(session.age)}")

    if session.agents:
        agents_str = ", ".join(session.agents)
        lines.append(f"\U0001f916 Agents: {mono(agents_str)}")

    if session.ports:
        lines.append("")
        lines.append(bold("Ports:"))
        for key, port in session.ports.items():
            label = escape_md(key)
            lines.append(f"  {label}: {mono(str(port))}")

    if session.alive and session.ports:
        lines.append("")
        lines.append(bold("URLs:"))
        fe = session.ports.get("frontend")
        be = session.ports.get("backend")
        if fe:
            lines.append(f"  Frontend: {mono(f'http://{ip}:{fe}')}")
        if be:
            lines.append(f"  Backend: {mono(f'http://{ip}:{be}')}")

    git_parts = []
    if session.git_dirty:
        git_parts.append(f"{session.git_dirty} dirty")
    if session.git_ahead:
        git_parts.append(f"{session.git_ahead} ahead")
    if git_parts:
        lines.append(f"\U0001f4ca Git: {escape_md(', '.join(git_parts))}")

    return "\n".join(lines)


def format_session_list(sessions: list[SessionInfo]) -> str:
    """Format a list of sessions into a compact Telegram message."""
    if not sessions:
        return escape_md("No sessions found.")

    lines = [bold(f"Sessions ({len(sessions)})"), ""]

    for s in sessions:
        status = _status_emoji(s)
        agents = f" [{', '.join(s.agents)}]" if s.agents else ""
        age = f" ({s.age})" if s.age else ""
        line = f"{status} {mono(s.name)} \\- {escape_md(s.project)}/{escape_md(s.branch)}{escape_md(agents)}{escape_md(age)}"
        lines.append(line)

    return "\n".join(lines)


def format_ports_table(sessions: list[SessionInfo]) -> str:
    """Format port allocation as a code block table."""
    if not sessions:
        return escape_md("No sessions registered.")

    header = f"{'Name':<25} {'Slot':>4} {'FE':>6} {'BE':>6} {'Status':<6}"
    separator = "-" * len(header)
    rows = [header, separator]

    for s in sessions:
        fe = s.ports.get("frontend", "?")
        be = s.ports.get("backend", "?")
        status = "alive" if s.alive else "dead"
        rows.append(f"{s.name:<25} {s.slot:>4} {fe:>6} {be:>6} {status:<6}")

    return code_block("\n".join(rows))


def format_command_result(result) -> str:
    """Format a CommandResult with success/error indicator."""
    if result.success:
        icon = "\u2705"
        text = result.output.strip() if result.output else "Done."
    else:
        icon = "\u274c"
        text = result.error.strip() if result.error else result.output.strip() if result.output else "Unknown error."

    return f"{icon} {text}"


def truncate(text: str, max_length: int = TELEGRAM_MAX_LENGTH) -> str:
    """Truncate text to fit Telegram's message size limit."""
    if len(text) <= max_length:
        return text
    suffix = "\n... (truncated)"
    return text[: max_length - len(suffix)] + suffix
