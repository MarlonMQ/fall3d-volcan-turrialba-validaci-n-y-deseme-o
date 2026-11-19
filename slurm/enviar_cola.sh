#!/usr/bin/env bash
# Envía la matriz completa de escalabilidad: 5 mallas x 6 cantidades MPI.
# Requiere que SetTgsd, SetSrc y SetDbs ya hayan generado las entradas.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MASTER="$REPO_ROOT/slurm/solver_automatico.slurm"

# Directorio de trabajo separado del repositorio (evita versionar archivos grandes).
WORK_ROOT="${WORK_ROOT:-/work/$USER/fall3d/reproduccion-nz40}"
FALL3D_BIN="${FALL3D_BIN:-$HOME/cc_investigation/fall3d/build-openmpi-correcto/bin/Fall3d.x}"
DRY_RUN="${DRY_RUN:-0}"
# Si se acaban de programar preparaciones, el primer solver depende del último job.
AFTEROK_JOB_ID="${AFTEROK_JOB_ID:-}"
MANIFEST="$WORK_ROOT/trabajos_escalabilidad.tsv"

MESHES=(x1 x4 x16 x64 x256)
PROCESSES=(32 16 8 4 2 1)

[[ "$WORK_ROOT" == /* ]] || { echo "ERROR: WORK_ROOT debe ser absoluto." >&2; exit 1; }
[[ -f "$MASTER" ]] || { echo "ERROR: no existe $MASTER" >&2; exit 1; }
[[ "$DRY_RUN" == 0 || "$DRY_RUN" == 1 ]] || { echo "ERROR: DRY_RUN debe ser 0 o 1" >&2; exit 1; }
[[ -z "$AFTEROK_JOB_ID" || "$AFTEROK_JOB_ID" =~ ^[0-9]+$ ]] || {
    echo "ERROR: AFTEROK_JOB_ID debe ser un identificador numérico de Slurm" >&2; exit 1;
}

# En modo de prueba no se escriben archivos ni se envían trabajos.
if [[ "$DRY_RUN" == 0 ]]; then
    command -v sbatch >/dev/null || { echo 'ERROR: sbatch no está disponible.' >&2; exit 1; }
    command -v squeue >/dev/null || { echo 'ERROR: squeue no está disponible.' >&2; exit 1; }
    bash "$SCRIPT_DIR/verificar_particion.sh"
    [[ -x "$FALL3D_BIN" ]] || { echo "ERROR: ejecutable FALL3D no disponible: $FALL3D_BIN" >&2; exit 1; }
    [[ ! -e "$MANIFEST" ]] || { echo "ERROR: ya existe el manifiesto: $MANIFEST" >&2; exit 1; }

    # Inspección global: no enviar ningún trabajo si hay entradas incompletas
    # o resultados existentes de alguna de las 30 combinaciones.
    for MESH in "${MESHES[@]}"; do
        DIR="$WORK_ROOT/$MESH"
        # Configuración y meteorología deben existir ahora. Las entradas generadas
        # solo pueden faltar si los solvers dependen del último job de preparación.
        for FILE in Turrialba.inp Turrialba.era5.nc; do
            [[ -s "$DIR/$FILE" ]] || { echo "ERROR: falta $DIR/$FILE" >&2; exit 1; }
        done
        if [[ -z "$AFTEROK_JOB_ID" ]]; then
            for FILE in Turrialba.dbs.nc Turrialba.src Turrialba.tgsd.tephra Turrialba.grn; do
                [[ -s "$DIR/$FILE" ]] || { echo "ERROR: falta $DIR/$FILE" >&2; exit 1; }
            done
        fi
        [[ ! -e "$DIR/Turrialba.res.nc" ]] || {
            echo "ERROR: resultado sin archivar en $DIR/Turrialba.res.nc" >&2; exit 1;
        }
        for NPROC in "${PROCESSES[@]}"; do
            DEST="$DIR/resultados/mpi$NPROC"
            [[ ! -e "$DEST/Turrialba.res.nc" ]] || {
                echo "ERROR: ya existe $DEST/Turrialba.res.nc" >&2; exit 1;
            }
        done
    done

    if squeue -h -u "$USER" -o '%j' | grep -Eq '^turr-x(1|4|16|64|256)-mpi(32|16|8|4|2|1)$'; then
        echo 'ERROR: ya hay solvers de esta matriz activos o pendientes.' >&2
        exit 1
    fi
    mkdir -p "$WORK_ROOT"
    printf 'job_id\tmalla\tmpi\tpx\tpy\n' > "$MANIFEST"
else
    echo 'MODO PRUEBA: no se enviarán trabajos ni se crearán archivos.'
fi

# Variables heredadas por los trabajos Slurm.
export WORK_ROOT FALL3D_BIN
PREVIOUS="$AFTEROK_JOB_ID"
COUNT=0

for NPROC in "${PROCESSES[@]}"; do
    case "$NPROC" in
        32) PX=8; PY=4 ;;
        16) PX=4; PY=4 ;;
         8) PX=4; PY=2 ;;
         4) PX=2; PY=2 ;;
         2) PX=2; PY=1 ;;
         1) PX=1; PY=1 ;;
    esac

    for MESH in "${MESHES[@]}"; do
        DEST="$WORK_ROOT/$MESH/resultados/mpi$NPROC"
        if [[ "$MESH" == x256 ]]; then
            LIMIT='72:00:00'
        else
            LIMIT='12:00:00'
        fi

        ARGS=(
            "--job-name=turr-${MESH}-mpi${NPROC}"
            '--partition=kura'
            '--account=ucr'
            '--nodes=1'
            "--ntasks=$NPROC"
            '--cpus-per-task=1'
            '--mem=64G'
            "--time=$LIMIT"
            "--output=$DEST/slurm_%j.out"
            "--error=$DEST/slurm_%j.err"
            "--export=ALL,MESH=$MESH,NPROC=$NPROC,PX=$PX,PY=$PY"
        )
        if [[ -n "$PREVIOUS" ]]; then
            ARGS+=("--dependency=afterok:$PREVIOUS")
        fi

        COUNT=$((COUNT + 1))
        if [[ "$DRY_RUN" == 1 ]]; then
            printf 'Planificado %02d/30: %-4s MPI%-2s (%s x %s x 1), tiempo=%s\n' \
                "$COUNT" "$MESH" "$NPROC" "$PX" "$PY" "$LIMIT"
            continue
        fi

        mkdir -p "$DEST"
        JOB="$(sbatch --parsable "${ARGS[@]}" "$MASTER")"
        JOB="${JOB%%;*}"
        [[ "$JOB" =~ ^[0-9]+$ ]] || { echo "ERROR: ID de trabajo inesperado: $JOB" >&2; exit 1; }
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$JOB" "$MESH" "$NPROC" "$PX" "$PY" >> "$MANIFEST"
        PREVIOUS="$JOB"
        echo "Enviado $COUNT/30: $MESH MPI$NPROC -> Job $JOB"
    done
done

echo "=== TOTAL: $COUNT/30 ==="
if [[ "$DRY_RUN" == 0 ]]; then
    echo "Manifiesto: $MANIFEST"
else
    echo 'Para enviar de verdad, ejecutar sin DRY_RUN=1 tras preparar las entradas.'
fi
