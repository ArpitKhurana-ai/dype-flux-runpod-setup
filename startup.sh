#!/usr/bin/env bash
# DyPE + FLUX FP16 auto-setup for ComfyUI (RunPod-friendly)
# - Installs Miniconda + PyTorch 2.4 (CUDA 12.1) in env "comfy"
# - Clones ComfyUI + KJNodes (Sage Attention) + DyPE repo (for reference)
# - Downloads FP16 FLUX UNet, CLIP-L, T5-XXL, and VAE via huggingface-cli
# - Starts ComfyUI headless on 0.0.0.0:8188
# Re-runnable: safe if you run it again.
set -euo pipefail

########################
# Config via .env (optional)
########################
# You can create a .env file next to this script to set:
#   HF_TOKEN=hf_xxx
#   PYTHON_VERSION=3.10
#   TORCH_VERSION=2.4.0
#   CUDA_TAG=cu121
#   COMFY_PORT=8188
#   GIT_BRANCH_COMFY=master
#   GIT_BRANCH_KJNODES=main
#   FLUX_REPO=black-forest-labs/FLUX.1-dev
#   FLUX_FILE=flux1-dev.safetensors
#   CLIP_REPO=black-forest-labs/CLIP-L
#   CLIP_FILE=clip_l.safetensors
#   T5_REPO=black-forest-labs/T5-XXL
#   T5_FILE=t5xxl_fp16.safetensors
#   VAE_REPO=madebyollin/ae-sdxl-v1
#   VAE_FILE=ae.safetensors
if [ -f ".env" ]; then
  set -a; source .env; set +a
fi

########################
# Defaults (can be overridden by .env)
########################
PYTHON_VERSION="${PYTHON_VERSION:-3.10}"
TORCH_VERSION="${TORCH_VERSION:-2.4.0}"
CUDA_TAG="${CUDA_TAG:-cu121}"
COMFY_PORT="${COMFY_PORT:-8188}"
GIT_BRANCH_COMFY="${GIT_BRANCH_COMFY:-master}"
GIT_BRANCH_KJNODES="${GIT_BRANCH_KJNODES:-main}"

# Model repos/files (override if your filenames differ)
FLUX_REPO="${FLUX_REPO:-black-forest-labs/FLUX.1-dev}"
FLUX_FILE="${FLUX_FILE:-flux1-dev.safetensors}"     # FP16 UNet (ensure FP16 variant)
CLIP_REPO="${CLIP_REPO:-black-forest-labs/CLIP-L}"
CLIP_FILE="${CLIP_FILE:-clip_l.safetensors}"        # FP16 CLIP-L
T5_REPO="${T5_REPO:-black-forest-labs/T5-XXL}"
T5_FILE="${T5_FILE:-t5xxl_fp16.safetensors}"        # FP16 T5-XXL
VAE_REPO="${VAE_REPO:-madebyollin/ae-sdxl-v1}"
VAE_FILE="${VAE_FILE:-ae.safetensors}"              # FP16 VAE

########################
# Helpers
########################
need_cmd () { command -v "$1" >/dev/null 2>&1 || return 1; }
ensure_pkg () {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y "$@"
}

mkdir -p /workspace && cd /workspace

########################
# System deps
########################
ensure_pkg git wget curl unzip ffmpeg libgl1-mesa-glx libglib2.0-0

########################
# Miniconda (clean, reliable)
########################
if ! need_cmd conda; then
  echo "[*] Installing Miniconda..."
  cd /tmp
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O m.sh
  bash m.sh -b -p /opt/conda
  rm m.sh
  /opt/conda/bin/conda init bash >/dev/null 2>&1 || true
fi
# shellcheck disable=SC1090
source ~/.bashrc || true
export PATH="/opt/conda/bin:$PATH"

########################
# Python env + Torch
########################
if ! conda env list | grep -q "^comfy"; then
  conda create -y -n comfy "python=${PYTHON_VERSION}"
fi
conda activate comfy

python -c "import torch" >/dev/null 2>&1 || {
  echo "[*] Installing PyTorch ${TORCH_VERSION} (${CUDA_TAG})..."
  pip install --upgrade pip
  pip install "torch==${TORCH_VERSION}" "torchvision==0.19.0" --index-url "https://download.pytorch.org/whl/${CUDA_TAG}"
}

########################
# ComfyUI
########################
cd /workspace
if [ ! -d "ComfyUI" ]; then
  echo "[*] Cloning ComfyUI..."
  git clone --branch "${GIT_BRANCH_COMFY}" https://github.com/comfyanonymous/ComfyUI.git
fi
cd ComfyUI
pip install -r requirements.txt

########################
# Custom Nodes: KJNodes (Sage Attention) + DyPE (reference)
########################
cd /workspace/ComfyUI/custom_nodes
if [ ! -d "ComfyUI-KJNodes" ]; then
  echo "[*] Cloning KJNodes..."
  git clone --branch "${GIT_BRANCH_KJNODES}" https://github.com/kijai/ComfyUI-KJNodes.git
fi
if [ ! -d "DyPE" ]; then
  echo "[*] Cloning DyPE repo (for reference/docs)..."
  git clone https://github.com/guyyariv/DyPE.git
fi

########################
# Models
########################
mkdir -p /workspace/ComfyUI/models/diffusion_models
mkdir -p /workspace/ComfyUI/models/text_encoders
mkdir -p /workspace/ComfyUI/models/vae

HF_BIN="/opt/conda/envs/comfy/bin/huggingface-cli"
if ! need_cmd "${HF_BIN}"; then
  pip install "huggingface_hub>=0.23"
fi

if [ -n "${HF_TOKEN-}" ]; then
  echo "[*] Logging into Hugging Face with provided token..."
  "${HF_BIN}" login --token "${HF_TOKEN}" --add-to-git-credential >/dev/null 2>&1 || true
else
  echo "[!] HF_TOKEN not set. If any model requires gated access, set HF_TOKEN in .env."
fi

echo "[*] Downloading FP16 models via huggingface-cli (skip if already present)..."
pushd /workspace/ComfyUI/models/diffusion_models >/dev/null
  if [ ! -f "${FLUX_FILE}" ]; then
    "${HF_BIN}" download "${FLUX_REPO}" "${FLUX_FILE}" --local-dir . --resume
  fi
popd >/dev/null

pushd /workspace/ComfyUI/models/text_encoders >/dev/null
  if [ ! -f "${CLIP_FILE}" ]; then
    "${HF_BIN}" download "${CLIP_REPO}" "${CLIP_FILE}" --local-dir . --resume
  fi
  if [ ! -f "${T5_FILE}" ]; then
    "${HF_BIN}" download "${T5_REPO}" "${T5_FILE}" --local-dir . --resume
  fi
popd >/dev/null

pushd /workspace/ComfyUI/models/vae >/dev/null
  if [ ! -f "${VAE_FILE}" ]; then
    "${HF_BIN}" download "${VAE_REPO}" "${VAE_FILE}" --local-dir . --resume
  fi
popd >/dev/null

echo "[✓] Models present:"
ls -lh /workspace/ComfyUI/models/diffusion_models || true
ls -lh /workspace/ComfyUI/models/text_encoders || true
ls -lh /workspace/ComfyUI/models/vae || true

########################
# Launch ComfyUI headless
########################
echo
echo "================================================================="
echo "Starting ComfyUI on 0.0.0.0:${COMFY_PORT}"
echo "Open from RunPod Connect panel: https://<pod-host>:${COMFY_PORT}"
echo "Next steps in UI:"
echo "  • Load your DyPE/FLUX workflow JSON"
echo "  • Ensure KJNodes Sage Attention is patched"
echo "  • Set Model Patch Torch Settings → enable_fp16_accumulation = true"
echo "  • Use these presets for EmptySD3LatentImage:"
echo "      Square    4096x4096"
echo "      Landscape 4096x2304"
echo "      Portrait  2304x4096"
echo "================================================================="
echo

cd /workspace/ComfyUI
exec python main.py --listen 0.0.0.0 --port "${COMFY_PORT}" --enable-cors-header --disable-metadata
