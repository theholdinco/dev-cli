from flask import Blueprint, render_template, request, flash, redirect, url_for

from core.tasks import list_tasks, add_task, remove_task, task_status_color
from core.commands import task_run
from core.system import get_projects

tasks_bp = Blueprint("tasks", __name__, url_prefix="/tasks")


@tasks_bp.route("/")
def list_tasks_view():
    tasks = list_tasks()
    return render_template(
        "tasks/list.html",
        tasks=tasks,
        task_status_color=task_status_color,
    )


@tasks_bp.route("/new")
def new_task_form():
    projects = get_projects()
    return render_template("tasks/new.html", projects=projects)


@tasks_bp.route("/new", methods=["POST"])
def create_task():
    project = request.form.get("project", "")
    branch = request.form.get("branch", "")
    from_branch = request.form.get("from_branch", "").strip()
    description = request.form.get("description", "")

    if not project or not branch or not description:
        flash("All fields are required.", "error")
        return redirect(url_for("tasks.new_task_form"))

    task = add_task(project=project, branch=branch, description=description, from_branch=from_branch)
    flash(f"Task #{task.id} added: {project}/{branch}", "success")
    return redirect(url_for("tasks.list_tasks_view"))


@tasks_bp.route("/<task_id>/remove", methods=["POST"])
def remove_task_view(task_id):
    removed = remove_task(task_id)
    if removed:
        message = f"Task #{task_id} removed"
        category = "success"
    else:
        message = f"Task #{task_id} not found"
        category = "error"

    if request.headers.get("HX-Request"):
        return render_template("partials/flash.html", message=message, category=category)

    flash(message, category)
    return redirect(url_for("tasks.list_tasks_view"))


@tasks_bp.route("/run", methods=["POST"])
def run_tasks_view():
    result = task_run()
    if result.success:
        flash("Task runner pass completed", "success")
    else:
        flash(f"Task runner error: {result.error or result.output}", "error")

    if request.headers.get("HX-Request"):
        msg = "Task runner pass completed" if result.success else f"Error: {result.error}"
        cat = "success" if result.success else "error"
        return render_template("partials/flash.html", message=msg, category=cat)

    return redirect(url_for("tasks.list_tasks_view"))
