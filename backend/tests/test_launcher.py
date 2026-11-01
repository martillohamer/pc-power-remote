"""Pruebas para verificar los scripts de arranque y configuracion (run_backend.bat, iniciar_todo.bat, run_tunnel.bat)."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def _read_text(rel_path):
    p = REPO_ROOT / rel_path
    assert p.exists(), f"{rel_path} debe existir"
    return p.read_text(encoding="utf-8", errors="replace")


def test_run_backend_bat_reload_configuration():
    """Verifica que run_backend.bat configure reload solo en dev y no en prod."""
    bat_path = Path(__file__).resolve().parent.parent / "run_backend.bat"
    assert bat_path.exists(), "run_backend.bat debe existir en backend/"

    content = bat_path.read_text(encoding="utf-8", errors="replace")

    # Debe incluir la configuracion especificada en T2.3 para modo dev:
    # el script ya esta dentro de backend/ (cd /d "%~dp0"), por lo que
    # --reload-dir . apunta al directorio correcto.
    assert '--reload-dir . --reload-include "*.py"' in content or (
        "--reload-dir ." in content and '--reload-include "*.py"' in content
    ), "Debe configurar --reload-dir . --reload-include \"*.py\" en modo dev"
    assert "--reload-dir backend" not in content, (
        "No debe quedar la ruta obsoleta --reload-dir backend"
    )

    # Debe contemplar modo prod sin --reload
    assert "prod" in content.lower(), "Debe soportar parametro de modo prod"
    assert "uvicorn main:app --host 0.0.0.0 --port 8000" in content, (
        "Debe invocar uvicorn sin --reload en modo prod"
    )


def test_iniciar_todo_bat_no_reload_no_fixed_ip():
    """iniciar_todo.bat no debe lanzar uvicorn --reload ni IP fija 192.168."""
    content = _read_text("iniciar_todo.bat")
    assert "--reload" not in content, (
        "iniciar_todo.bat no debe contener --reload (delega a run_backend.bat dev)"
    )
    assert "192.168." not in content, (
        "iniciar_todo.bat no debe contener IP fija 192.168.x"
    )


def test_run_tunnel_bat_no_tunnel_run():
    """run_tunnel.bat no debe usar la sintaxis invalida 'tunnel run' de cloudflared."""
    content = _read_text("run_tunnel.bat")
    assert "tunnel run" not in content, (
        "run_tunnel.bat no debe contener 'tunnel run' (Quick Tunnel usa 'tunnel --url')"
    )
