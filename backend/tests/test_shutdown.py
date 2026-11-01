"""Pruebas para los endpoints de apagado y cancelacion (/api/shutdown, /api/cancel)."""

import subprocess
from unittest.mock import MagicMock
import pytest
from main import MAX_MINUTES, _read_pending


@pytest.fixture
def mock_subprocess(monkeypatch):
    """Mockea subprocess.run y desactiva DRY_RUN para comprobar los comandos exactos sin riesgo."""
    import main
    monkeypatch.setattr(main, "DRY_RUN", False)
    mock = MagicMock()
    mock.return_value = subprocess.CompletedProcess(
        args=[],
        returncode=0,
        stdout=b"",
        stderr=b"",
    )
    monkeypatch.setattr(subprocess, "run", mock)
    monkeypatch.setattr(main.subprocess, "run", mock)
    return mock


def test_shutdown_minutes_zero(client, auth_headers, mock_subprocess):
    """POST /api/shutdown con {'minutes': 0} -> 200 y comando forzado inmediato."""
    response = client.post("/api/shutdown", json={"minutes": 0}, headers={**auth_headers, "Content-Type": "application/json"})
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert data["minutes"] == 0
    assert data["seconds"] == 0
    assert "ends_at" in data
    assert _read_pending() is None

    mock_subprocess.assert_called_once_with(
        ["shutdown", "/s", "/f", "/t", "0"],
        capture_output=True,
        timeout=15,
        check=False,
    )


def test_shutdown_empty_json(client, auth_headers, mock_subprocess):
    """POST /api/shutdown con {} -> 200 y default minutos = 0."""
    response = client.post("/api/shutdown", json={}, headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert data["minutes"] == 0
    assert data["seconds"] == 0
    mock_subprocess.assert_called_once_with(
        ["shutdown", "/s", "/f", "/t", "0"],
        capture_output=True,
        timeout=15,
        check=False,
    )


def test_shutdown_empty_body(client, auth_headers, mock_subprocess):
    """POST /api/shutdown con cuerpo vacio -> 200 y default minutos = 0."""
    response = client.post("/api/shutdown", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert data["minutes"] == 0
    mock_subprocess.assert_called_once_with(
        ["shutdown", "/s", "/f", "/t", "0"],
        capture_output=True,
        timeout=15,
        check=False,
    )


def test_shutdown_timed_five_minutes(client, auth_headers, mock_subprocess):
    """POST /api/shutdown con minutes=5 -> aborta previos (/a) y programa /s /t 300."""
    response = client.post("/api/shutdown", json={"minutes": 5}, headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert data["minutes"] == 5
    assert data["seconds"] == 300

    pending = _read_pending()
    assert pending is not None
    assert pending.minutes == 5

    assert mock_subprocess.call_count == 2
    first_call = mock_subprocess.call_args_list[0][0][0]
    second_call = mock_subprocess.call_args_list[1][0][0]
    assert first_call == ["shutdown", "/a"]
    assert second_call == ["shutdown", "/s", "/t", "300"]


def test_shutdown_timed_ignores_previous_409(client, auth_headers, mock_subprocess):
    """Si no habia apagado previo, shutdown /a da 1116 (409), pero se ignora y se programa."""
    # Primer llamado (shutdown /a) devuelve 1116
    mock_subprocess.side_effect = [
        subprocess.CompletedProcess(args=["shutdown", "/a"], returncode=1116, stdout=b"", stderr=b"No shutdown"),
        subprocess.CompletedProcess(args=["shutdown", "/s", "/t", "300"], returncode=0, stdout=b"", stderr=b""),
    ]

    response = client.post("/api/shutdown", json={"minutes": 5}, headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["minutes"] == 5


def test_shutdown_negative_minutes(client, auth_headers):
    """POST /api/shutdown con minutes=-1 -> 422."""
    response = client.post("/api/shutdown", json={"minutes": -1}, headers=auth_headers)
    assert response.status_code == 422


def test_shutdown_over_max_minutes(client, auth_headers):
    """POST /api/shutdown con minutes > MAX_MINUTES -> 422."""
    response = client.post("/api/shutdown", json={"minutes": MAX_MINUTES + 1}, headers=auth_headers)
    assert response.status_code == 422


def test_cancel_shutdown_success(client, auth_headers, mock_subprocess):
    """POST /api/cancel cuando hay apagado -> returncode 0, cancelado ok."""
    mock_subprocess.return_value = subprocess.CompletedProcess(
        args=["shutdown", "/a"],
        returncode=0,
        stdout=b"",
        stderr=b"",
    )
    response = client.post("/api/cancel", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert "cancelado" in data["message"].lower()
    assert _read_pending() is None


def test_cancel_shutdown_none_pending_1116(client, auth_headers, mock_subprocess):
    """POST /api/cancel con returncode 1116 -> 200 con mensaje 'no había apagado pendiente'."""
    mock_subprocess.return_value = subprocess.CompletedProcess(
        args=["shutdown", "/a"],
        returncode=1116,
        stdout=b"",
        stderr=b"No hay ningun apagado en curso.",
    )
    response = client.post("/api/cancel", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert "no hab" in data["message"].lower() or "no había" in data["message"].lower()
    assert _read_pending() is None


def test_cancel_shutdown_error_other_code(client, auth_headers, mock_subprocess):
    """POST /api/cancel con error distinto a 1116 -> 500."""
    mock_subprocess.return_value = subprocess.CompletedProcess(
        args=["shutdown", "/a"],
        returncode=1,
        stdout=b"",
        stderr=b"Acceso denegado.",
    )
    response = client.post("/api/cancel", headers=auth_headers)
    assert response.status_code == 500
    assert "Acceso denegado" in response.json()["detail"]
