import pytest


@pytest.fixture(autouse=True)
def isolated_state(tmp_path, monkeypatch):
    monkeypatch.setenv("CAIRN_STATE_DIR", str(tmp_path / "state"))
