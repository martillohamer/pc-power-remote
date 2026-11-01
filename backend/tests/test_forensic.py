"""Pruebas unitarias para el endpoint forense de procesos (/api/forensic/processes)."""

from unittest.mock import MagicMock, call, patch
import pytest
import main


def make_mock_process(pid, name, cpu_reads, rss_bytes, status="running"):
    """Crea un proceso simulado de psutil."""
    proc = MagicMock()
    proc.pid = pid
    proc.info = {
        "pid": pid,
        "name": name,
        "memory_info": MagicMock(rss=rss_bytes),
        "status": status,
    }
    # cpu_percent(None) retorna secuencialmente los valores de cpu_reads
    proc.cpu_percent.side_effect = list(cpu_reads)
    return proc


def test_forensic_processes_primes_cpu_and_sleeps(client, auth_headers, monkeypatch):
    """Verifica que se prime la CPU con None, se espere ~0.3s y se lea el valor real en la segunda pasada."""
    mock_proc = make_mock_process(101, "python.exe", [0.0, 15.5], 100 * 1024 * 1024)

    monkeypatch.setattr(main.psutil, "process_iter", lambda attrs: [mock_proc])
    
    sleep_calls = []
    monkeypatch.setattr(main.time, "sleep", lambda s: sleep_calls.append(s))
    monkeypatch.setattr(main.psutil, "cpu_count", lambda: 4)

    response = client.get("/api/forensic/processes", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["pid"] == 101
    assert data[0]["cpu_percent"] == 15.5
    assert data[0]["memory_mb"] == 100.0

    # Comprobar que cpu_percent fue llamado dos veces con None (primado y lectura)
    assert mock_proc.cpu_percent.call_count == 2
    mock_proc.cpu_percent.assert_has_calls([call(None), call(None)])

    # Comprobar que se durmio ~0.3 segundos
    assert len(sleep_calls) == 1
    assert pytest.approx(sleep_calls[0], abs=0.05) == 0.3


def test_forensic_processes_ordered_by_cpu_then_memory(client, auth_headers, monkeypatch):
    """Verifica el ordenamiento descendente por (cpu_percent, memory_mb).
    
    El bug antiguo sumaba cpu + memory_mb, por lo que ProcD (5% CPU, 1000 MB = 1005)
    ganaba indebidamente a ProcB (20% CPU, 100 MB = 120).
    Con la correccion: ProcC (20%, 200MB) > ProcB (20%, 100MB) > ProcA (10%, 500MB) > ProcD (5%, 1000MB).
    """
    procs = [
        make_mock_process(1, "ProcA", [0.0, 10.0], 500 * 1024 * 1024),
        make_mock_process(2, "ProcB", [0.0, 20.0], 100 * 1024 * 1024),
        make_mock_process(3, "ProcC", [0.0, 20.0], 200 * 1024 * 1024),
        make_mock_process(4, "ProcD", [0.0, 5.0], 1000 * 1024 * 1024),
    ]

    monkeypatch.setattr(main.psutil, "process_iter", lambda attrs: procs)
    monkeypatch.setattr(main.time, "sleep", lambda s: None)
    monkeypatch.setattr(main.psutil, "cpu_count", lambda: 4)

    response = client.get("/api/forensic/processes", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()

    pids_in_order = [p["pid"] for p in data]
    assert pids_in_order == [3, 2, 1, 4]


def test_forensic_processes_limit_ten(client, auth_headers, monkeypatch):
    """Verifica que se devuelvan como maximo 10 procesos."""
    procs = [
        make_mock_process(i, f"Proc{i}", [0.0, float(i)], 50 * 1024 * 1024)
        for i in range(1, 16)
    ]

    monkeypatch.setattr(main.psutil, "process_iter", lambda attrs: procs)
    monkeypatch.setattr(main.time, "sleep", lambda s: None)
    monkeypatch.setattr(main.psutil, "cpu_count", lambda: 8)

    response = client.get("/api/forensic/processes", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 10
    # El primero debe ser Proc15 con 15.0%
    assert data[0]["pid"] == 15


def test_forensic_processes_cpu_capped_at_cores(client, auth_headers, monkeypatch):
    """Verifica que el cpu_percent no exceda 100 * numero_de_nucleos."""
    # Simula 2 nucleos -> max 200%
    mock_proc = make_mock_process(42, "Runaway", [0.0, 350.0], 20 * 1024 * 1024)

    monkeypatch.setattr(main.psutil, "process_iter", lambda attrs: [mock_proc])
    monkeypatch.setattr(main.time, "sleep", lambda s: None)
    monkeypatch.setattr(main.psutil, "cpu_count", lambda: 2)

    response = client.get("/api/forensic/processes", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data[0]["cpu_percent"] == 200.0


def test_forensic_processes_ignores_system_processes(client, auth_headers, monkeypatch):
    """Verifica que 'System Idle Process' y 'System' se ignoren."""
    procs = [
        make_mock_process(0, "System Idle Process", [0.0, 99.0], 0),
        make_mock_process(4, "System", [0.0, 10.0], 10 * 1024 * 1024),
        make_mock_process(100, "app.exe", [0.0, 2.0], 10 * 1024 * 1024),
    ]

    monkeypatch.setattr(main.psutil, "process_iter", lambda attrs: procs)
    monkeypatch.setattr(main.time, "sleep", lambda s: None)

    response = client.get("/api/forensic/processes", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["pid"] == 100
