"""Task-oriented Telegram handlers: tasks, task_add, task_rm, task_run."""

from telegram import Update
from telegram.ext import ContextTypes

from bot.auth import authorized
from bot.formatters import format_task_list, format_task, format_command_result, truncate
from core.tasks import list_tasks, get_task, add_task, remove_task
from core.commands import task_run


@authorized
async def cmd_tasks(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /tasks — list all tasks with status."""
    tasks = list_tasks()
    text = format_task_list(tasks)
    await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")


@authorized
async def cmd_task_add(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /task_add <project> <branch> <description> [--from base]."""
    if not context.args or len(context.args) < 3:
        await update.message.reply_text(
            "Usage: /task_add <project> <branch> <description> [--from base]"
        )
        return

    project = context.args[0]
    branch = context.args[1]
    remaining = context.args[2:]

    # Parse --from flag from remaining args
    from_branch = ""
    desc_parts = []
    i = 0
    while i < len(remaining):
        if remaining[i] == "--from" and i + 1 < len(remaining):
            i += 1
            from_branch = remaining[i]
        else:
            desc_parts.append(remaining[i])
        i += 1
    description = " ".join(desc_parts)

    if not description:
        await update.message.reply_text(
            "Usage: /task_add <project> <branch> <description> [--from base]"
        )
        return

    task = add_task(project=project, branch=branch, description=description, from_branch=from_branch)
    text = format_task(task)
    await update.message.reply_text(truncate(text), parse_mode="MarkdownV2")


@authorized
async def cmd_task_rm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /task_rm <id> — remove a task."""
    if not context.args:
        await update.message.reply_text("Usage: /task_rm <id>")
        return

    task_id = context.args[0]
    removed = remove_task(task_id)

    if removed:
        await update.message.reply_text(f"Task #{task_id} removed.")
    else:
        await update.message.reply_text(f"Task #{task_id} not found.")


@authorized
async def cmd_task_run(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /task_run — trigger single runner pass."""
    await update.message.reply_text("Running task runner...")

    result = task_run()
    text = format_command_result(result)
    await update.message.reply_text(truncate(text))
