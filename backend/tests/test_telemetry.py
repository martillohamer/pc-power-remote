"""Pruebas unitarias para el WebSocket de telemetria (/ws/telemetry)."""

from unittest.mock import MagicMock, patch
import pytest
from starlette.websockets import WebSocketDisconnect
import main
from main import Telemetry


@pytest.fixture
def sample_telemetry():
    return Telemetry(
        cpu_usage=12.5,
        ram_usage=45.0,
        ram_used_mb=7200.0,
        ram_total_mb=16000.0,
        disk_usage=60.0,
        uptime_seconds=3600,
    )


def test_telemetry_socket_invalid_pin(client):
    """Conexion con PIN invalido es rechazada con codigo 1008."""
    with client.websocket_connect("/ws/telemetry?pin=pin_invalido") as ws:
        with pytest.raises(WebSocketDisconnect) as exc_info:
            ws.receive_json()
        assert exc_info.value.code == 1008


def test_telemetry_socket_normal_stream(client, sample_telemetry, monkeypatch):
    """Conexion normal recibe frames de telemetria validos."""
    monkeypatch.setattr(main, "collect_telemetry", lambda: sample_telemetry)
    monkeypatch.setattr(main, "TELEMETRY_INTERVAL", 0.05)
    monkeypatch.setattr(main, "CPU_SAMPLE_SECONDS", 0.01)

    with client.websocket_connect("/ws/telemetry?pin=134113") as ws:
        frame = ws.receive_json()
        assert frame["cpu_usage"] == 12.5
        assert frame["ram_usage"] == 45.0
        assert frame["uptime_seconds"] == 3600


def test_telemetry_exception_sends_error_frame_and_continues(client, sample_telemetry, monkeypatch):
    """Una excepcion en collect_telemetry envia {'error': '...'} y continua sin matar el WebSocket."""
    call_count = 0

    def mock_collect():
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            raise RuntimeError("Fallo transitorio en sensor de hardware")
        return sample_telemetry

    monkeypatch.setattr(main, "collect_telemetry", mock_collect)
    monkeypatch.setattr(main, "TELEMETRY_INTERVAL", 0.05)
    monkeypatch.setattr(main, "CPU_SAMPLE_SECONDS", 0.01)

    with client.websocket_connect("/ws/telemetry?pin=134113") as ws:
        # El primer frame debe ser el de error capturado
        frame1 = ws.receive_json()
        assert "error" in frame1
        assert "Fallo transitorio en sensor de hardware" in frame1["error"]

        # El segundo frame debe ser el payload recuperado exitosamente
        frame2 = ws.receive_json()
        assert "error" not in frame2
        assert frame2["cpu_usage"] == 12.5
        assert frame2["ram_usage"] == 45.0
