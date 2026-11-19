#!/usr/bin/env bash
# Verifica que 'kura' permita el límite de 72 h requerido por la matriz x256.
set -euo pipefail

command -v scontrol >/dev/null || { echo 'ERROR: falta scontrol.' >&2; exit 1; }
PARTITION_INFO="$(scontrol show partition kura)" || {
    echo 'ERROR: no se pudo consultar la partición kura.' >&2; exit 1;
}
MAX_TIME="$(printf '%s\n' "$PARTITION_INFO" | tr '[:space:]' '\n' | sed -n 's/^MaxTime=//p' | head -n 1)"
[[ -n "$MAX_TIME" ]] || { echo 'ERROR: sin MaxTime para kura.' >&2; exit 1; }
if [[ "$MAX_TIME" == INFINITE || "$MAX_TIME" == UNLIMITED ]]; then
    echo "Partición kura: MaxTime=$MAX_TIME (compatible con 72 h)"
    exit 0
fi
if [[ "$MAX_TIME" =~ ^([0-9]+)-([0-9]+):([0-9]+):([0-9]+)$ ]]; then
    MAX_SECONDS=$((10#${BASH_REMATCH[1]} * 86400 + 10#${BASH_REMATCH[2]} * 3600 + 10#${BASH_REMATCH[3]} * 60 + 10#${BASH_REMATCH[4]}))
elif [[ "$MAX_TIME" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
    MAX_SECONDS=$((10#${BASH_REMATCH[1]} * 3600 + 10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]}))
else
    echo "ERROR: formato MaxTime no reconocido: $MAX_TIME" >&2
    exit 1
fi
if (( MAX_SECONDS < 72 * 3600 )); then
    echo "ERROR: kura permite MaxTime=$MAX_TIME, pero x256 solicita 72:00:00." >&2
    echo 'No se enviarán trabajos. Consultar las restricciones del clúster.' >&2
    exit 1
fi
echo "Partición kura: MaxTime=$MAX_TIME (compatible con 72 h)"
