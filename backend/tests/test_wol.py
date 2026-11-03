"""Pruebas unitarias para el módulo Wake-on-LAN (/api/wake y /api/config)."""

import pytest
from unittest.mock import patch
import main


def test_wol_config(client, auth_headers):
    """Verifica que /api/config devuelve la configuración WOL correcta."""
    response = client.get("/api/config", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert "mac_address" in data
    assert "broadcast" in data
    assert "port" in data
    assert "source" in data


def test_wake_unauthorized(client):
    """Verifica que /api/wake sin PIN rechaza la petición con 401."""
    response = client.post("/api/wake", json={"mac": "AA:BB:CC:DD:EE:FF"})
    assert response.status_code == 401


@patch("main.send_magic_packet")
def test_wake_success_default_mac(mock_send, client, auth_headers, monkeypatch):
    """Verifica que /api/wake exitoso usa la MAC por defecto y envía el paquete mágico."""
    monkeypatch.setattr(main, "APP_MAC_ADDRESS", "11:22:33:44:55:66")
    response = client.post("/api/wake", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert data["mac"] == "11:22:33:44:55:66"
    mock_send.assert_called_once()


@patch("main.send_magic_packet")
def test_wake_success_custom_mac(mock_send, client, auth_headers):
    """Verifica que /api/wake con MAC en el payload envía el paquete a dicha MAC."""
    response = client.post(
        "/api/wake",
        headers=auth_headers,
        json={"mac": "AA:BB:CC:DD:EE:FF"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert data["mac"] == "AA:BB:CC:DD:EE:FF"
    mock_send.assert_called_once_with("AA:BB:CC:DD:EE:FF", ip_address=main.WOL_BROADCAST, port=main.WOL_PORT)


def test_wake_invalid_mac_format(client, auth_headers):
    """Verifica que una MAC inválida en el payload produce error 422."""
    response = client.post(
        "/api/wake",
        headers=auth_headers,
        json={"mac": "INVALID_MAC"},
    )
    assert response.status_code == 422


@patch("main.send_magic_packet", None)
def test_wake_library_missing(client, auth_headers, monkeypatch):
    """Verifica error 503 si la librería wakeonlan no está disponible."""
    monkeypatch.setattr(main, "APP_MAC_ADDRESS", "11:22:33:44:55:66")
    response = client.post("/api/wake", headers=auth_headers)
    assert response.status_code == 503
    assert "wakeonlan" in response.json()["detail"].lower()


@patch("main.send_magic_packet")
def test_wake_os_error(mock_send, client, auth_headers, monkeypatch):
    """Verifica error 500 si send_magic_packet lanza OSError."""
    mock_send.side_effect = OSError("Network unreachable")
    monkeypatch.setattr(main, "APP_MAC_ADDRESS", "11:22:33:44:55:66")
    response = client.post("/api/wake", headers=auth_headers)
    assert response.status_code == 500
    assert "network unreachable" in response.json()["detail"].lower()
