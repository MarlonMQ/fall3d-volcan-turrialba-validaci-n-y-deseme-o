#!/usr/bin/env bash
# En Kabré: preparar cinco mallas y encadenar 30 simulaciones.
# Ejemplo seguro: DRY_RUN=1 bash slurm/lanzar_todo.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK_ROOT="${WORK_ROOT:-/work/$USER/fall3d/reproduccion-nz40}"
DRY_RUN="${DRY_RUN:-0}"
[[ "$DRY_RUN" == 0 || "$DRY_RUN" == 1 ]] || { echo 'ERROR: DRY_RUN debe ser 0 o 1' >&2; exit 1; }

export WORK_ROOT DRY_RUN
if [[ "$DRY_RUN" == 1 ]]; then
    bash "$SCRIPT_DIR/preparar_entradas.sh"
    echo
    bash "$SCRIPT_DIR/enviar_cola.sh"
    echo 'MODO PRUEBA completado: 10 trabajos preparativos y 30 simulaciones planificados.'
    exit 0
fi

[[ ! -e "$WORK_ROOT/trabajos_preparacion.tsv" ]] || {
    echo 'ERROR: ya existe un manifiesto preparativo. No se reenviará la cadena.' >&2
    exit 1
}
[[ ! -e "$WORK_ROOT/trabajos_escalabilidad.tsv" ]] || {
    echo 'ERROR: ya existe un manifiesto de simulación.' >&2
    exit 1
}

# Validar el límite de tiempo ANTES de crear los 10 trabajos preparatorios.
bash "$SCRIPT_DIR/verificar_particion.sh"
bash "$SCRIPT_DIR/preparar_entradas.sh"

MANIFEST="$WORK_ROOT/trabajos_preparacion.tsv"
[[ -s "$MANIFEST" ]] || { echo "ERROR: falta el manifiesto $MANIFEST" >&2; exit 1; }
LAST_JOB="$(tail -n 1 "$MANIFEST" | cut -f1)"
[[ "$LAST_JOB" =~ ^[0-9]+$ ]] || { echo "ERROR: ID de preparación inválido: $LAST_JOB" >&2; exit 1; }

echo "La matriz MPI dependerá del último trabajo de preparación: $LAST_JOB"
export AFTEROK_JOB_ID="$LAST_JOB"
bash "$SCRIPT_DIR/enviar_cola.sh"
echo 'Envío completado: 10 trabajos preparativos seguidos de 30 solvers.'
