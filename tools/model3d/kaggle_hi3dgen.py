"""Send reference images to the Kaggle GPU, get high-poly meshes back.

    python -m tools.model3d.kaggle_hi3dgen out/ref/chest.png [more.png ...] -o out/high

Needs `pip install kaggle` and Kaggle credentials (~/.kaggle/kaggle.json or
KAGGLE_USERNAME + KAGGLE_KEY). Phone-verify the Kaggle account once so GPU +
internet are allowed in notebooks. Free tier: ~30 GPU hours/week.
"""
import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).parent
WORK = pathlib.Path("build/kaggle")


def kaggle(*args, check=True):
    r = subprocess.run(["kaggle", *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"kaggle {' '.join(args)} failed:\n{r.stdout}\n{r.stderr}")
    return r


def username():
    if os.environ.get("KAGGLE_USERNAME"):
        return os.environ["KAGGLE_USERNAME"]
    cfg = pathlib.Path.home() / ".kaggle" / "kaggle.json"
    if not cfg.exists():
        sys.exit("No Kaggle credentials. See SETUP.md (Kaggle).")
    return json.loads(cfg.read_text())["username"]


def push_inputs(user, images):
    d = WORK / "dataset"
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    for img in images:
        shutil.copy(img, d / pathlib.Path(img).name)
    slug = f"{user}/rblx-3d-input"
    (d / "dataset-metadata.json").write_text(
        json.dumps({"title": "rblx-3d-input", "id": slug, "licenses": [{"name": "CC0-1.0"}]})
    )
    exists = kaggle("datasets", "status", slug, check=False).returncode == 0
    if exists:
        kaggle("datasets", "version", "-p", str(d), "-m", f"batch {int(time.time())}")
    else:
        kaggle("datasets", "create", "-p", str(d))
    return slug


def push_kernel(user, dataset):
    d = WORK / "kernel"
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    shutil.copy(HERE / "hi3dgen_kernel.py", d / "hi3dgen_kernel.py")
    slug = f"{user}/rblx-hi3dgen"
    meta = {
        "id": slug, "title": "rblx-hi3dgen", "code_file": "hi3dgen_kernel.py",
        "language": "python", "kernel_type": "script", "is_private": True,
        "enable_gpu": True, "enable_internet": True, "dataset_sources": [dataset],
    }
    (d / "kernel-metadata.json").write_text(json.dumps(meta))
    kaggle("kernels", "push", "-p", str(d))
    return slug


def wait(slug, timeout=3600):
    start = time.time()
    while time.time() - start < timeout:
        out = kaggle("kernels", "status", slug).stdout.lower()
        if "complete" in out:
            return
        if "error" in out or "cancel" in out:
            sys.exit(f"Kernel failed: {out}\nRun `kaggle kernels output {slug} -p build/kaggle/log` for the log.")
        time.sleep(30)
    sys.exit("Timed out waiting for Kaggle")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("-o", "--out", default="out/high")
    a = ap.parse_args()
    if shutil.which("kaggle") is None:
        sys.exit("Install the Kaggle CLI: pip install kaggle")
    user = username()
    dataset = push_inputs(user, a.images)
    time.sleep(20)  # dataset version must finish processing before the kernel mounts it
    slug = push_kernel(user, dataset)
    print(f"Running {slug} ... (https://www.kaggle.com/code/{slug})")
    wait(slug)
    pathlib.Path(a.out).mkdir(parents=True, exist_ok=True)
    kaggle("kernels", "output", slug, "-p", a.out)
    for g in sorted(pathlib.Path(a.out).glob("*.glb")):
        print(g)


if __name__ == "__main__":
    main()
