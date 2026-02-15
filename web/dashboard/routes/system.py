from flask import Blueprint, jsonify, render_template, request

from core.system import get_port_table, get_stats
from core.commands import run_doctor

system_bp = Blueprint("system", __name__, url_prefix="/system")


@system_bp.route("/stats")
def stats_view():
    stats = get_stats()

    if request.headers.get("Accept") == "application/json":
        return jsonify(stats)

    return render_template("system/stats.html", stats=stats)


@system_bp.route("/ports")
def ports_view():
    ports_data = get_port_table()
    ports = [
        {
            "name": p["name"],
            "slot": p["slot"],
            "frontend": p["frontend_port"],
            "backend": p["backend_port"],
            "status": "alive" if p["alive"] else "dead",
        }
        for p in ports_data
    ]

    if request.headers.get("HX-Request"):
        return render_template("partials/ports_table.html", ports=ports)

    return render_template("system/ports.html", ports=ports)


@system_bp.route("/doctor")
def doctor_view():
    result = run_doctor()
    output = result.output if result.success else f"Error: {result.error}"
    return render_template("system/doctor.html", output=output)
