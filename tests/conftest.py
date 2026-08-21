import os
import mlflow
import pytest


@pytest.fixture(autouse=True, scope="session")
def isolated_mlflow_store(tmp_path_factory):
    """
    Tro MLflow vao mot thu muc tam rieng cho suot phien test.

    Neu khong lam vay, test se ghi de len store that (mlflow.db / mlruns) cua may
    ca nhan, va se hong khi thu muc mlruns/ dang o trang thai cua backend SQLite.
    Nho fixture nay, unit test chay duoc trong GitHub Actions ma khong can bat ky
    cau hinh MLflow hay xac thuc cloud nao.
    """
    store = tmp_path_factory.mktemp("mlruns")
    uri = store.as_uri()

    previous = os.environ.get("MLFLOW_TRACKING_URI")
    os.environ["MLFLOW_TRACKING_URI"] = uri
    mlflow.set_tracking_uri(uri)

    yield

    if previous is None:
        os.environ.pop("MLFLOW_TRACKING_URI", None)
    else:
        os.environ["MLFLOW_TRACKING_URI"] = previous
