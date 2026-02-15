from flask import Blueprint, render_template, request

from core.commands import get_logs, send_to_session, get_diff, sync_session, create_pr

commands_bp = Blueprint("commands", __name__, url_prefix="/sessions")


@commands_bp.route("/<name>/logs")
def view_logs(name):
    result = get_logs(name)
    output = result.output if result.success else f"Error: {result.error}"
    return render_template("partials/agent_output.html", output=output)


@commands_bp.route("/<name>/send", methods=["POST"])
def send_prompt_view(name):
    prompt = request.form.get("prompt", "")
    result = send_to_session(name, prompt)
    output = result.output if result.success else f"Error: {result.error}"
    return render_template("partials/agent_output.html", output=output, title="Sent")


@commands_bp.route("/<name>/diff")
def view_diff(name):
    result = get_diff(name)
    diff = result.output if result.success else f"Error: {result.error}"
    return render_template("partials/git_status.html", diff=diff)


@commands_bp.route("/<name>/sync", methods=["POST"])
def sync_session_view(name):
    result = sync_session(name)
    if result.success:
        return render_template("partials/flash.html", message=f"Session '{name}' synced", category="success")
    return render_template("partials/flash.html", message=f"Error syncing: {result.error}", category="error")


@commands_bp.route("/<name>/pr", methods=["POST"])
def create_pr_view(name):
    draft = request.form.get("draft") == "on"
    result = create_pr(name, draft=draft)
    if result.success:
        return render_template("partials/flash.html", message=f"PR created: {result.output.strip()}", category="success")
    return render_template("partials/flash.html", message=f"Error creating PR: {result.error}", category="error")
