#!/usr/bin/env bash
#
# yue2-dgx-launcher.sh
# -------------------------------------------------------------------------
# Headless launcher for the YuE2 native inference server (audiocpp_server)
# on a Linux NVIDIA DGX box. Starts ONLY the server half of YuE2 Studio;
# the PySide6 GUI is NOT started and is not needed here.
#
# Derived verbatim from the GUI's own launch logic in yue2_studio.py:
#   - binary name (non-Windows):           def engine_exe()        -> line ~7610
#   - working dir (model_specs | exe dir):  start_server()          -> line ~7742
#   - CUDA_VISIBLE_DEVICES env:             start_server()          -> line ~7737-7739
#   - launch args (--ui/--ui-management/--backend/--host/--port):   -> line ~7743-7748
#   - API/health lives at http://HOST:PORT (/health, /v1/...):      -> line ~431
#
# IMPORTANT DEVIATIONS from the GUI on purpose:
#   1. --backend cuda is forced. The GUI picks "cuda" only on Windows and
#      "metal" otherwise (line 7743) -- that "else metal" branch is a Mac
#      assumption and is WRONG on a Linux/NVIDIA box. We set cuda explicitly.
#   2. The GUI hardcodes --host 127.0.0.1. Here HOST is configurable so the
#      DGX server can accept a connection from another machine. See the
#      security note below before binding to 0.0.0.0.
#
# This script does NOT download anything and does NOT build audio.cpp.
# The audiocpp_server binary and the GGUF models must already be present
# (the upstream installer only ships Windows x64 CUDA zips -- on Linux you
# must build/obtain a Linux CUDA audiocpp_server yourself).
# -------------------------------------------------------------------------
set -euo pipefail

# --- configuration (override via environment) ----------------------------
# Directory that contains the audiocpp_server binary (and ideally model_specs/).
ENGINE_DIR="${YUE2_ENGINE_DIR:-$HOME/yue2/motor}"
# Directory holding the downloaded GGUF models (Yue2-3B-GGUF/, SheetSage2-GGUF/, ...).
MODELS_DIR="${YUE2_MODELS_DIR:-$HOME/yue2/modellek}"
# Bind address. 127.0.0.1 = localhost only (use an SSH tunnel to reach it; safest).
# Set to 0.0.0.0 ONLY on a trusted/isolated network -- the server has NO auth.
HOST="${YUE2_HOST:-127.0.0.1}"
PORT="${YUE2_PORT:-8080}"
# Which GPU(s). "0" = first card. Leave empty to expose all DGX GPUs.
GPU_DEVICE="${YUE2_GPU:-0}"
# --------------------------------------------------------------------------

# 1. Locate the binary exactly as engine_exe() does: direct child first,
#    then a recursive search under ENGINE_DIR.
BIN=""
if [[ -f "$ENGINE_DIR/audiocpp_server" ]]; then
  BIN="$ENGINE_DIR/audiocpp_server"
else
  BIN="$(find "$ENGINE_DIR" -type f -name audiocpp_server 2>/dev/null | head -n1 || true)"
fi
if [[ -z "$BIN" ]]; then
  echo "ERROR: audiocpp_server not found under $ENGINE_DIR" >&2
  echo "       Set YUE2_ENGINE_DIR or place the Linux CUDA binary there." >&2
  exit 1
fi
chmod +x "$BIN" 2>/dev/null || true

# 2. Working directory: engine dir if it holds model_specs/, else the binary's dir
#    (this mirrors start_server(): line 7742).
if [[ -d "$ENGINE_DIR/model_specs" ]]; then
  WORKDIR="$ENGINE_DIR"
else
  WORKDIR="$(dirname "$BIN")"
fi

# 3. Environment: pin the GPU(s) like the GUI's CUDA_VISIBLE_DEVICES setting.
if [[ -n "$GPU_DEVICE" ]]; then
  export CUDA_VISIBLE_DEVICES="$GPU_DEVICE"
fi

# 4. Preflight (read-only, no model run): report what we're about to do.
echo "== YuE2 headless server (DGX) =="
echo "  binary : $BIN"
echo "  workdir: $WORKDIR"
echo "  models : $MODELS_DIR  (loaded on demand via POST /v1/models/load)"
echo "  bind   : http://$HOST:$PORT   (health: /health, API: /v1/...)"
echo "  GPU    : CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<all>}"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader || true
else
  echo "  WARNING: nvidia-smi not found -- is this box CUDA-capable?" >&2
fi
if [[ "$HOST" == "0.0.0.0" ]]; then
  echo "  SECURITY: binding to 0.0.0.0 -- the server has no authentication." >&2
  echo "            Prefer HOST=127.0.0.1 + 'ssh -L 8080:127.0.0.1:8080 dgx'." >&2
fi

# 5. Launch. Same flag set the GUI uses, backend forced to cuda for NVIDIA.
cd "$WORKDIR"
exec "$BIN" \
  --ui --ui-management \
  --backend cuda \
  --host "$HOST" --port "$PORT"
