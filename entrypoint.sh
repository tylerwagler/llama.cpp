#!/bin/bash
set -e

# Read the current model name from config file
MODEL_NAME=""
if [ -f /models/current_model.json ]; then
    MODEL_NAME=$(grep -o '"model": *"[^"]*"' /models/current_model.json | cut -d'"' -f4)
fi

# If no model configured, default to GLM 4.7 Flash
if [ -z "$MODEL_NAME" ]; then
    MODEL_NAME="GLM 4.7 Flash"
fi

echo "[llama-server] Selected model: $MODEL_NAME"

# Read the model file path from models.ini
MODEL_PATH=""
if [ -f /app/models.ini ]; then
    # Find the section for this model and extract the model= line
    MODEL_PATH=$(awk -v model="$MODEL_NAME" '
        /^\[/ { in_section=0 }
        $0 == "["model"]" { in_section=1 }
        in_section && /^model = / { print $3; exit }
    ' /app/models.ini)
fi

if [ -z "$MODEL_PATH" ]; then
    echo "[llama-server] ERROR: Could not find model path for: $MODEL_NAME"
    exit 1
fi

echo "[llama-server] Loading model file: $MODEL_PATH"

# Extract params from models.ini (defaults)
CTX_SIZE=$(awk -v model="$MODEL_NAME" '
    /^\[/ { in_section=0 }
    $0 == "["model"]" { in_section=1 }
    in_section && /^ctx-size = / { print $3; exit }
' /app/models.ini)

TENSOR_SPLIT=$(awk -v model="$MODEL_NAME" '
    /^\[/ { in_section=0 }
    $0 == "["model"]" { in_section=1 }
    in_section && /^tensor-split = / { print $3; exit }
' /app/models.ini)

PARALLEL=$(awk -v model="$MODEL_NAME" '
    /^\[/ { in_section=0 }
    $0 == "["model"]" { in_section=1 }
    in_section && /^parallel = / { print $3; exit }
' /app/models.ini)

CACHE_TYPE=$(awk -v model="$MODEL_NAME" '
    /^\[/ { in_section=0 }
    $0 == "["model"]" { in_section=1 }
    in_section && /^cache-type = / { print $3; exit }
' /app/models.ini)

# Read overrides from current_model.json (written by ai-proxy on each switch)
if [ -f /models/current_model.json ]; then
    CTX_OVERRIDE=$(python3 -c "import json; d=json.load(open('/models/current_model.json')); print(d.get('ctx_size',''))" 2>/dev/null || true)
    PARALLEL_OVERRIDE=$(python3 -c "import json; d=json.load(open('/models/current_model.json')); print(d.get('parallel',''))" 2>/dev/null || true)
    CACHE_TYPE_OVERRIDE=$(python3 -c "import json; d=json.load(open('/models/current_model.json')); print(d.get('cache_type',''))" 2>/dev/null || true)

    [ -n "$CTX_OVERRIDE" ] && CTX_SIZE="$CTX_OVERRIDE"
    [ -n "$PARALLEL_OVERRIDE" ] && PARALLEL="$PARALLEL_OVERRIDE"
    [ -n "$CACHE_TYPE_OVERRIDE" ] && CACHE_TYPE="$CACHE_TYPE_OVERRIDE"

    echo "[llama-server] Overrides applied: ctx_size=${CTX_OVERRIDE:-none} parallel=${PARALLEL_OVERRIDE:-none} cache_type=${CACHE_TYPE_OVERRIDE:-none}"
fi

# Build command args
ARGS=(
    --host 0.0.0.0
    --port 8082
    -m "$MODEL_PATH"
    --metrics
    --api-prefix /chat
    --poll 100
)

# Add params (with defaults)
[ -n "$CTX_SIZE" ] && ARGS+=(--ctx-size "$CTX_SIZE")
[ -n "$TENSOR_SPLIT" ] && ARGS+=(--tensor-split "$TENSOR_SPLIT")
[ -n "$PARALLEL" ] && ARGS+=(--parallel "$PARALLEL") || ARGS+=(--parallel 1)

# Add KV cache type flags if set (applies to both K and V)
if [ -n "$CACHE_TYPE" ] && [ "$CACHE_TYPE" != "f16" ]; then
    ARGS+=(--cache-type-k "$CACHE_TYPE" --cache-type-v "$CACHE_TYPE")
fi

echo "[llama-server] Starting with args: ${ARGS[*]}"

# Start llama-server
exec /app/llama-server "${ARGS[@]}"
