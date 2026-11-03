"""Pruebas unitarias para el rate-limiting de PIN (/api/state u otros endpoints protegidos)."""

import pytest
from main import FAILED_PIN_ATTEMPTS


def setup_function():
    """Limpiar el registro de intentos fallidos antes de cada test."""
    FAILED_PIN_ATTEMPTS.clear()


def test_ratelimit_six_failed_attempts(client):
    """Tras 5 intentos fallidos consecutivos de PIN, el 6.º intento devuelve HTTP 429."""
    for _ in range(5):
        response = client.get("/api/state", headers={"X-App-Pin": "PIN_INCORRECTO"})
        assert response.status_code == 401

    # El 6.º intento debe disparar 429 Too Many Requests
    response = client.get("/api/state", headers={"X-App-Pin": "PIN_INCORRECTO"})
    assert response.status_code == 429
    assert "Retry-After" in response.headers or response.json().get("detail")


def test_ratelimit_successful_pin_resets_counter(client, auth_headers):
    """Un intento exitoso de PIN resetea el contador de fallos para la IP cliente."""
    # 3 intentos fallidos
    for _ in range(3):
        response = client.get("/api/state", headers={"X-App-Pin": "PIN_INCORRECTO"})
        assert response.status_code == 401

    # 1 intento exitoso
    response = client.get("/api/state", headers=auth_headers)
    assert response.status_code == 200

    # Nuevamente 3 intentos fallidos (no debe disparar 429 porque se reseteó)
    for _ in range(3):
        response = client.get("/api/state", headers={"X-App-Pin": "PIN_INCORRECTO"})
        assert response.status_code == 401
