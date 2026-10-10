# Runs ON KAGGLE (GPU T4/P100, internet on). Pushed by tools/model3d/kaggle_hi3dgen.py.
# Image -> normal map (StableNormal) -> mesh (Hi3DGen, MIT licence) -> /kaggle/working/mesh.glb
# ~100 GPU-seconds per asset once the environment is cached.
import glob
import os
import subprocess
import sys


def sh(cmd):
    print("+", cmd, flush=True)
    subprocess.run(cmd, shell=True, check=True)


if not os.path.exists("/kaggle/working/Hi3DGen"):
    sh("git clone --depth 1 --recursive https://github.com/Stable-X/Hi3DGen /kaggle/working/Hi3DGen")
    sh("pip install -q -r /kaggle/working/Hi3DGen/requirements.txt")
    sh("pip install -q spconv-cu120 xformers")
sys.path.insert(0, "/kaggle/working/Hi3DGen")
os.environ.setdefault("ATTN_BACKEND", "xformers")
os.environ.setdefault("SPCONV_ALGO", "native")

import torch  # noqa: E402
from PIL import Image  # noqa: E402
from hi3dgen.pipelines import Hi3DGenPipeline  # noqa: E402

inputs = sorted(glob.glob("/kaggle/input/**/*.png", recursive=True))
assert inputs, "no input png in the attached dataset"
seed = int(os.environ.get("HI3D_SEED", "1"))

pipeline = Hi3DGenPipeline.from_pretrained("Stable-X/trellis-normal-v0-1")
pipeline.cuda()
normal_predictor = torch.hub.load(
    "hugoycj/StableNormal", "StableNormal_turbo", trust_repo=True, yoso_version="yoso-normal-v1-8-1"
)

for path in inputs:
    name = os.path.splitext(os.path.basename(path))[0]
    image = pipeline.preprocess_image(Image.open(path).convert("RGBA"), resolution=1024)
    normal = normal_predictor(image, resolution=768, match_input_resolution=True, data_type="object")
    normal.save(f"/kaggle/working/{name}_normal.png")
    outputs = pipeline.run(
        normal,
        seed=seed,
        formats=["mesh"],
        preprocess_image=False,
        sparse_structure_sampler_params={"steps": 50, "cfg_strength": 3.0},
        slat_sampler_params={"steps": 6, "cfg_strength": 3.0},
    )
    mesh = outputs["mesh"][0].to_trimesh(transform_pose=True)
    mesh.export(f"/kaggle/working/{name}.glb")
    print("WROTE", name, len(mesh.faces), "faces", flush=True)
