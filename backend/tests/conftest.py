"""Configuración y fixtures para pruebas del backend T-800."""

import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch
import pytest

# Garantizar APP_DRY_RUN=1 y APP_PIN antes de importar la app
os.environ["APP_DRY_RUN"] = "1"
os.environ["APP_PIN"] = "134113"

BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import main
main.DRY_RUN = True
main.APP_PIN = "134113"

from fastapi.testclient import TestClient


@pytest.fixture
def auth_headers():
    return {"X-App-Pin": "134113"}


@pytest.fixture
def client():
    with TestClient(main.app) as test_client:
        yield test_client


@pytest.fixture(autouse=True)
def protect_system(monkeypatch):
    """Garantiza que nunca se ejecuten comandos reales y limpia estado entre tests."""
    monkeypatch.setattr(main, "DRY_RUN", True)
    main._set_pending(None)
