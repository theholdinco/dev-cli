import time

from flask import Blueprint, Response, render_template, request, current_app

from core.sessions import list_sessions

sse_bp = Blueprint("sse", __name__, url_prefix="/sse")


@sse_bp.route("/sessions")
def session_stream():
    user = request.args.get("user", "")

    def generate():
        while True:
            try:
                sessions = list_sessions(user=user)
                html = render_template("partials/session_list.html", sessions=sessions)
                data = html.replace("\n", "\ndata: ")
                yield f"event: sessions\ndata: {data}\n\n"
            except Exception:
                yield f"event: error\ndata: <div class=\"text-red-400 p-4\">Error loading sessions</div>\n\n"

            time.sleep(3)

    return Response(
        generate(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )
