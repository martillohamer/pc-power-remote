"""Comprobaciones estaticas de frontend y configuracion (E6, E7).

Solo lee texto de archivos; no ejecuta procesos ni servidores.
"""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def _read(rel_path: str) -> str:
    p = REPO_ROOT / rel_path
    assert p.exists(), f"{rel_path} debe existir"
    return p.read_text(encoding="utf-8", errors="replace")


# --- E6: Frontend -----------------------------------------------------------


def test_app_no_class_attribute():
    """E6: App.jsx no debe usar el atributo HTML 'class=' (solo className)."""
    content = _read("frontend/src/App.jsx")
    assert 'class=' not in content, "App.jsx no debe contener 'class=' (usar className)"


def test_app_has_pb28():
    """E6: App.jsx debe tener pb-28 en el contenedor principal."""
    content = _read("frontend/src/App.jsx")
    assert "pb-28" in content, "App.jsx debe contener pb-28 (espacio inferior para el MIC)"


def test_app_voice_terminator_confirm():
    """E6: App.jsx debe confirmar la ruta de voz 'terminator' con window.confirm."""
    content = _read("frontend/src/App.jsx")
    assert "window.confirm" in content, "La ruta de voz terminator debe usar window.confirm"
    assert "TERMINATOR" in content, "El texto de confirmacion debe mencionar TERMINATOR"


def test_forensic_overflow_x_auto():
    """E6: ForensicPanel debe envolver la tabla en overflow-x-auto."""
    content = _read("frontend/src/ForensicPanel.jsx")
    assert "overflow-x-auto" in content, "ForensicPanel debe envolver la tabla en overflow-x-auto"


def test_forensic_no_transition_width():
    """E6: ForensicPanel no debe usar la clase invalida transition-width."""
    content = _read("frontend/src/ForensicPanel.jsx")
    assert "transition-width" not in content, "ForensicPanel no debe contener transition-width"


def test_voicecommandbutton_is_secure_context():
    """E6: VoiceCommandButton debe validar window.isSecureContext."""
    content = _read("frontend/src/VoiceCommandButton.jsx")
    assert "isSecureContext" in content, "VoiceCommandButton debe comprobar window.isSecureContext"


def test_vite_allowed_hosts():
    """E6: vite.config.js debe tener server.allowedHosts con '.trycloudflare.com'."""
    content = _read("frontend/vite.config.js")
    assert "allowedHosts" in content, "vite.config.js debe definir server.allowedHosts"
    assert ".trycloudflare.com" in content, "allowedHosts debe incluir '.trycloudflare.com'"


# --- E7: .gitignore ---------------------------------------------------------


def test_gitignore_pytest_cache_and_cloudflared():
    """E7: .gitignore debe ignorar .pytest_cache/ y .cloudflared/."""
    content = _read(".gitignore")
    assert ".pytest_cache/" in content, ".gitignore debe ignorar .pytest_cache/"
    assert ".cloudflared/" in content, ".gitignore debe ignorar .cloudflared/"
