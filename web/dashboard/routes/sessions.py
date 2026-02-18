import os

from flask import Blueprint, render_template, request, flash, redirect, url_for

from core.sessions import list_sessions, get_session, get_users
from core.commands import new_session, kill_session, restart_session, run_dev
from core.system import get_projects

sessions_bp = Blueprint("sessions", __name__, url_prefix="/sessions")


@sessions_bp.route("/")
def list_sessions_view():
    user = request.args.get("user", "")
    users = get_users()
    requesting_user = os.environ.get("USER", "")
    sessions = list_sessions(user=user, requesting_user=requesting_user)
    return render_template("sessions/list.html", sessions=sessions, users=users, selected_user=user)


@sessions_bp.route("/new")
def new_session_form():
    projects = get_projects()
    return render_template("sessions/new.html", projects=projects)


@sessions_bp.route("/new", methods=["POST"])
def create_session():
    project = request.form.get("project", "")
    branch = request.form.get("branch", "")
    from_branch = request.form.get("from_branch", "").strip()
    agent_type = request.form.get("agent_type", "claude")
    yolo = request.form.get("yolo") == "on"
    private = request.form.get("private") == "on"

    result = new_session(project=project, branch=branch, agent=agent_type, yolo=yolo, from_branch=from_branch, private=private)
    if result.success:
        flash(f"Session created for {project}/{branch}", "success")
    else:
        flash(f"Error creating session: {result.error or result.output}", "error")

    return redirect(url_for("sessions.list_sessions_view"))


@sessions_bp.route("/<name>")
def session_detail(name):
    session = get_session(name)
    if session is None:
        flash(f"Session '{name}' not found", "error")
        return redirect(url_for("sessions.list_sessions_view"))
    return render_template("sessions/detail.html", session=session)


@sessions_bp.route("/<name>/kill", methods=["POST"])
def kill_session_view(name):
    result = kill_session(name)
    if result.success:
        message = f"Session '{name}' killed"
        category = "success"
    else:
        message = f"Error killing session: {result.error or result.output}"
        category = "error"

    if request.headers.get("HX-Request"):
        return render_template("partials/flash.html", message=message, category=category)

    flash(message, category)
    return redirect(url_for("sessions.list_sessions_view"))


@sessions_bp.route("/<name>/private", methods=["POST"])
def toggle_private_view(name):
    session = get_session(name)
    if session is None:
        flash(f"Session '{name}' not found", "error")
        return redirect(url_for("sessions.list_sessions_view"))

    new_state = "off" if session.private else "on"
    result = run_dev(["private", session.name, new_state])

    if result.success:
        label = "private" if new_state == "on" else "public"
        flash(f"Session '{session.name}' is now {label}", "success")
    else:
        flash(f"Error toggling privacy: {result.error or result.output}", "error")

    return redirect(url_for("sessions.session_detail", name=session.name))


@sessions_bp.route("/<name>/restart", methods=["POST"])
def restart_session_view(name):
    result = restart_session(name)
    if result.success:
        message = f"Session '{name}' restarted"
        category = "success"
    else:
        message = f"Error restarting session: {result.error or result.output}"
        category = "error"

    if request.headers.get("HX-Request"):
        return render_template("partials/flash.html", message=message, category=category)

    flash(message, category)
    return redirect(url_for("sessions.list_sessions_view"))
