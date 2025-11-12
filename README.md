# DyPE + FLUX (FP16) ComfyUI on RunPod – Public Safe Setup

## 🚀 Quick Start (on RunPod)
1. Launch a GPU pod (A40/A5000 or better).  
2. In the RunPod UI → **Environment Variables**, add:  
   - **Key:** `HF_TOKEN`  
   - **Value:** your Hugging Face token (`hf_...`) – read-only scope is enough.  
3. Open the terminal and run:
   ```bash
   cd /workspace
   git clone https://github.com/<YOUR_USER>/dype-flux-runpod-setup.git
   cd dype-flux-runpod-setup
   bash startup.sh
