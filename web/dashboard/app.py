from flask import Flask, redirect, url_for


def create_app():
    app = Flask(
        __name__,
        template_folder="templates",
        static_folder="static",
    )
    app.secret_key = "dev-cli-dashboard-secret-key"

    from .routes.sessions import sessions_bp
    from .routes.agents import agents_bp
    from .routes.commands import commands_bp
    from .routes.system import system_bp
    from .routes.sse import sse_bp

    app.register_blueprint(sessions_bp)
    app.register_blueprint(agents_bp)
    app.register_blueprint(commands_bp)
    app.register_blueprint(system_bp)
    app.register_blueprint(sse_bp)

    @app.route("/")
    def index():
        return redirect(url_for("sessions.list_sessions_view"))

    @app.context_processor
    def utility_processor():
        def status_color(status):
            return "green" if status == "alive" else "red"
        return dict(status_color=status_color)

    return app
