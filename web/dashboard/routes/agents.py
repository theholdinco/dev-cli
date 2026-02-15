from flask import Blueprint, render_template, request

from core.sessions import get_session
from core.commands import agent_add, agent_remove

agents_bp = Blueprint("agents", __name__, url_prefix="/sessions")


@agents_bp.route("/<name>/agents/add", methods=["POST"])
def add_agent(name):
    agent_type = request.form.get("agent_type", "claude")
    result = agent_add(name, agent_type)

    if result.success:
        session = get_session(name)
        return render_template("partials/flash.html", message=f"Agent '{agent_type}' added", category="success")

    return render_template("partials/flash.html", message=f"Error adding agent: {result.error}", category="error")


@agents_bp.route("/<name>/agents/<agent_type>/remove", methods=["POST"])
def remove_agent(name, agent_type):
    result = agent_remove(name, agent_type)

    if result.success:
        return render_template("partials/flash.html", message=f"Agent '{agent_type}' removed", category="success")

    return render_template("partials/flash.html", message=f"Error removing agent: {result.error}", category="error")
