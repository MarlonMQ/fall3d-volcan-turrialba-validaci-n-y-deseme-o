#!/usr/bin/env bash
# Prepara las 5 mallas: SetTgsd + SetSrc y después SetDbs para cada una.
# Cada trabajo depende de la terminación correcta del anterior (afterok).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MASTER="$SCRIPT_DIR/preparacion_automatica.slurm"
WORK_ROOT="${WORK_ROOT:-/work/$USER/fall3d/reproduccion-nz40}"
FALL3D_BIN="${FALL3D_BIN:-$HOME/cc_investigation/fall3d/build-openmpi-correcto/bin/Fall3d.x}"
METEO_FILE="${METEO_FILE:-}"
DRY_RUN="${DRY_RUN:-0}"
MANIFEST="$WORK_ROOT/trabajos_preparacion.tsv"
MESHES=(x1 x4 x16 x64 x256)

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "$WORK_ROOT" == /* ]] || fail 'WORK_ROOT debe ser una ruta absoluta.'
[[ "$DRY_RUN" == 0 || "$DRY_RUN" == 1 ]] || fail 'DRY_RUN debe ser 0 o 1.'
[[ -f "$MASTER" ]] || fail "No existe $MASTER"

for MESH in "${MESHES[@]}"; do
    [[ -s "$REPO_ROOT/config/Turrialba_${MESH}.inp" ]] || fail "Falta config/Turrialba_${MESH}.inp"
done

if [[ "$DRY_RUN" == 0 ]]; then
    [[ "$METEO_FILE" == /* ]] || fail 'METEO_FILE debe ser una ruta absoluta al NetCDF ERA5 preparado.'
    [[ -s "$METEO_FILE" ]] || fail "No existe o está vacío: $METEO_FILE"
    [[ -x "$FALL3D_BIN" ]] || fail "Falta ejecutable FALL3D: $FALL3D_BIN"
    command -v sbatch >/dev/null || fail 'No está disponible sbatch.'
    command -v squeue >/dev/null || fail 'No está disponible squeue.'
    [[ ! -e "$MANIFEST" ]] || fail "Existe un manifiesto anterior: $MANIFEST"
    [[ ! -e "$WORK_ROOT/trabajos_escalabilidad.tsv" ]] || fail 'Ya existe un manifiesto de solvers en WORK_ROOT.'

    # Comprobar todos los directorios antes de cambiar el sistema de archivos.
    for MESH in "${MESHES[@]}"; do
        DIR="$WORK_ROOT/$MESH"
        for FILE in Turrialba.inp Turrialba.era5.nc Turrialba.tgsd.tephra Turrialba.src Turrialba.grn Turrialba.dbs.nc Turrialba.dbs.pro Turrialba.res.nc; do
            [[ ! -e "$DIR/$FILE" && ! -L "$DIR/$FILE" ]] || fail "Existe archivo de una ejecución anterior: $DIR/$FILE"
        done
        [[ ! -d "$DIR/resultados" ]] || fail "Existe directorio de resultados anterior: $DIR/resultados"
    done

    if squeue -h -u "$USER" -o '%j' | grep -Eq '^turr-(prep|dbs)-x(1|4|16|64|256)$'; then
        fail 'Ya hay preparaciones FALL3D activas o pendientes.'
    fi

    mkdir -p "$WORK_ROOT"
    for MESH in "${MESHES[@]}"; do
        DIR="$WORK_ROOT/$MESH"
        mkdir -p "$DIR/logs"
        cp "$REPO_ROOT/config/Turrialba_${MESH}.inp" "$DIR/Turrialba.inp"
        ln -s "$METEO_FILE" "$DIR/Turrialba.era5.nc"
    done
    printf 'job_id\tmalla\tetapa\tdependencia\n' > "$MANIFEST"
else
    echo 'MODO PRUEBA: no se copian archivos ni se envían trabajos.'
    echo 'Requisitos en ejecución real: cinco config/Turrialba_x*.inp, METEO_FILE y FALL3D_BIN.'
fi

export WORK_ROOT FALL3D_BIN
PREVIOUS=''
COUNT=0
for MESH in "${MESHES[@]}"; do
    for STAGE in source dbs; do
        if [[ "$STAGE" == source ]]; then
            MEM='16G'; LIMIT='02:00:00'; TAG='prep'
        else
            MEM='32G'; LIMIT='04:00:00'; TAG='dbs'
        fi
        ARGS=(
            "--job-name=turr-${TAG}-${MESH}"
            '--partition=kura' '--account=ucr' '--nodes=1' '--ntasks=1' '--cpus-per-task=1'
            "--mem=$MEM" "--time=$LIMIT"
            "--output=$WORK_ROOT/$MESH/logs/${STAGE}_%j.out"
            "--error=$WORK_ROOT/$MESH/logs/${STAGE}_%j.err"
            "--export=ALL,MESH=$MESH,PREP_STAGE=$STAGE"
        )
        if [[ -n "$PREVIOUS" ]]; then
            ARGS+=("--dependency=afterok:$PREVIOUS")
        fi
        COUNT=$((COUNT+1))
        if [[ "$DRY_RUN" == 1 ]]; then
            printf 'Preparación %02d/10: %-4s etapa=%-6s mem=%-3s límite=%s\n' \
                "$COUNT" "$MESH" "$STAGE" "$MEM" "$LIMIT"
            continue
        fi
        JOB="$(sbatch --parsable "${ARGS[@]}" "$MASTER")"
        JOB="${JOB%%;*}"
        [[ "$JOB" =~ ^[0-9]+$ ]] || fail "sbatch devolvió un ID inesperado: $JOB"
        printf '%s\t%s\t%s\t%s\n' "$JOB" "$MESH" "$STAGE" "${PREVIOUS:--}" >> "$MANIFEST"
        PREVIOUS="$JOB"
        echo "Enviado $COUNT/10: $MESH $STAGE -> Job $JOB"
    done
done

echo "=== Preparaciones planificadas/enviadas: $COUNT/10 ==="
if [[ "$DRY_RUN" == 0 ]]; then
    echo "Último job de preparación: $PREVIOUS"
    echo "Manifiesto: $MANIFEST"
fi
