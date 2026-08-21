import mlflow
import mlflow.sklearn
import pandas as pd
import yaml
import json
import joblib
import os
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    confusion_matrix,
    classification_report,
)

# Nguong mac dinh. Co the ghi de bang khoa `eval_threshold` trong params.yaml.
EVAL_THRESHOLD = 0.70

# Ten experiment tren MLflow. Dat ten tuong minh de moi lan chay deu nam cung mot cho,
# thay vi roi vao experiment "Default" (id 0) von co the khong ton tai tren store moi.
EXPERIMENT_NAME = os.environ.get("MLFLOW_EXPERIMENT_NAME", "wine-quality")

# Bonus 5: canh bao neu mot lop chiem it hon ti le nay trong tap huan luyen.
MIN_CLASS_RATIO = 0.10

CLASS_LABELS = {0: "thap", 1: "trung_binh", 2: "cao"}


def configure_tracking() -> str:
    """
    Bonus 1: chon noi ghi ket qua thi nghiem.

    Neu MLFLOW_TRACKING_URI duoc dat (vi du tracking server cua DagsHub, kem
    MLFLOW_TRACKING_USERNAME / MLFLOW_TRACKING_PASSWORD), MLflow tu dung no.
    Neu khong, quay ve file SQLite cuc bo de chay o may ca nhan van hoat dong
    ma khong can bat ky cau hinh nao.
    """
    uri = os.environ.get("MLFLOW_TRACKING_URI", "").strip()
    if not uri:
        uri = "sqlite:///mlflow.db"
        mlflow.set_tracking_uri(uri)
    print(f"MLflow tracking URI: {uri}")
    return uri


def build_model(model_type: str, model_params: dict):
    """
    Bonus 2: chon thuat toan theo khoa `model_type` trong params.yaml.

    LogisticRegression duoc boc trong Pipeline voi StandardScaler vi mo hinh tuyen
    tinh nhay cam voi thang do dac trung (total_sulfur_dioxide co gia tri hang tram,
    trong khi density quanh 0.99). Hai mo hinh cay khong can chuan hoa.
    """
    if model_type == "random_forest":
        return RandomForestClassifier(**model_params, random_state=42)
    if model_type == "gradient_boosting":
        return GradientBoostingClassifier(**model_params, random_state=42)
    if model_type == "logistic_regression":
        return make_pipeline(
            StandardScaler(),
            LogisticRegression(**model_params, random_state=42),
        )
    raise ValueError(
        f"model_type khong hop le: {model_type!r}. "
        "Chon mot trong: random_forest, gradient_boosting, logistic_regression."
    )


def check_label_distribution(y_train) -> dict:
    """
    Bonus 5: kiem tra phan phoi nhan truoc khi huan luyen.

    Mot lop qua hiem lam mo hinh gan nhu khong bao gio du doan ra lop do, va accuracy
    tong the van co the trong ve dep. In canh bao ro rang de nguoi doc log nhin thay
    van de truoc khi tin vao con so accuracy.
    """
    ratios = y_train.value_counts(normalize=True).sort_index()
    distribution = {str(int(k)): round(float(v), 4) for k, v in ratios.items()}

    print("Phan phoi nhan trong tap huan luyen:")
    for label, ratio in distribution.items():
        name = CLASS_LABELS.get(int(label), "?")
        print(f"  lop {label} ({name:11s}): {ratio:6.2%}")

    rare = {k: v for k, v in distribution.items() if v < MIN_CLASS_RATIO}
    if rare:
        for label, ratio in rare.items():
            print(
                f"CANH BAO LECH LAC DU LIEU: lop {label} chi chiem {ratio:.2%}, "
                f"duoi nguong {MIN_CLASS_RATIO:.0%}. Mo hinh se hoc kem tren lop nay."
            )
    else:
        print(f"Khong co lop nao duoi nguong {MIN_CLASS_RATIO:.0%}.")

    return distribution


def write_report(y_eval, preds) -> str:
    """
    Bonus 3: ghi confusion matrix va precision/recall tung lop ra outputs/report.txt.

    Bao cao dang van ban thuan de doc truc tiep trong log cua GitHub Actions, khong
    can tai artifact ve may.
    """
    labels = sorted(set(y_eval) | set(preds))
    cm = confusion_matrix(y_eval, preds, labels=labels)
    target_names = [f"{lbl}-{CLASS_LABELS.get(int(lbl), '?')}" for lbl in labels]

    lines = ["BAO CAO HIEU SUAT MO HINH", "=" * 60, "", "Confusion matrix (hang = that, cot = du doan):", ""]
    header = " " * 14 + "".join(f"{name:>14s}" for name in target_names)
    lines.append(header)
    for name, row in zip(target_names, cm):
        lines.append(f"{name:>14s}" + "".join(f"{v:>14d}" for v in row))

    lines += ["", "Precision / Recall / F1 theo tung lop:", ""]
    lines.append(
        classification_report(y_eval, preds, labels=labels, target_names=target_names, digits=4)
    )

    report = "\n".join(lines)
    os.makedirs("outputs", exist_ok=True)
    with open("outputs/report.txt", "w", encoding="utf-8") as f:
        f.write(report)
    return report


def load_dataset(path: str) -> pd.DataFrame:
    """
    Doc CSV va chuan hoa ten cot ve dang snake_case.

    File CSV goc tu UCI dung ten co dau cach ("fixed acidity") trong khi README
    va tests/test_train.py dung dau gach duoi ("fixed_acidity"). Chuan hoa o day
    de hai nguon dung chung mot schema.
    """
    df = pd.read_csv(path)
    df.columns = [c.strip().replace(" ", "_") for c in df.columns]
    return df


def train(
    params: dict,
    data_path: str = "data/train_phase1.csv",
    eval_path: str = "data/eval.csv",
) -> float:
    """
    Huan luyen mo hinh va ghi nhan ket qua vao MLflow.

    Tham so:
        params     : dict chua cac sieu tham so cho mo hinh. Hai khoa dac biet
                     khong duoc truyen vao mo hinh:
                       - `model_type`     : chon thuat toan (mac dinh random_forest)
                       - `eval_threshold` : nguong cho eval gate trong CI/CD
        data_path  : duong dan den file du lieu huan luyen.
        eval_path  : duong dan den file du lieu danh gia.

    Tra ve:
        accuracy (float): do chinh xac tren tap danh gia.
    """

    model_params = dict(params)
    threshold = float(model_params.pop("eval_threshold", EVAL_THRESHOLD))
    model_type = model_params.pop("model_type", "random_forest")

    df_train = load_dataset(data_path)
    df_eval = load_dataset(eval_path)

    X_train = df_train.drop(columns=["target"])
    y_train = df_train["target"]
    X_eval = df_eval.drop(columns=["target"])
    y_eval = df_eval["target"]

    label_distribution = check_label_distribution(y_train)

    configure_tracking()
    mlflow.set_experiment(EXPERIMENT_NAME)

    with mlflow.start_run():

        mlflow.log_params(model_params)
        mlflow.log_param("model_type", model_type)
        mlflow.log_param("eval_threshold", threshold)
        mlflow.log_param("n_train_samples", len(df_train))

        model = build_model(model_type, model_params)
        model.fit(X_train, y_train)

        preds = model.predict(X_eval)
        acc = float(accuracy_score(y_eval, preds))
        f1 = float(f1_score(y_eval, preds, average="weighted"))

        mlflow.log_metric("accuracy", acc)
        mlflow.log_metric("f1_score", f1)
        for label, ratio in label_distribution.items():
            mlflow.log_metric(f"train_class_{label}_ratio", ratio)
        mlflow.sklearn.log_model(model, "model")

        print(f"Accuracy: {acc:.4f} | F1: {f1:.4f}")

        report = write_report(y_eval, preds)
        print()
        print(report)
        mlflow.log_artifact("outputs/report.txt")

        # File nay duoc doc boi GitHub Actions o Buoc 2
        os.makedirs("outputs", exist_ok=True)
        with open("outputs/metrics.json", "w") as f:
            json.dump(
                {
                    "accuracy": acc,
                    "f1_score": f1,
                    "eval_threshold": threshold,
                    "model_type": model_type,
                    "n_train_samples": len(df_train),
                    "label_distribution": label_distribution,
                },
                f,
                indent=2,
            )

        # File nay duoc upload len S3 o Buoc 2
        os.makedirs("models", exist_ok=True)
        joblib.dump(model, "models/model.pkl")

    return acc


if __name__ == "__main__":
    with open("params.yaml") as f:
        params = yaml.safe_load(f)
    train(params)
