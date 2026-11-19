#!/bin/bash

set -euo pipefail

TARGET="/work/$USER/fall3d/experimentos-5h/escalabilidad-nz40"
MASTER="$TARGET/solver_automatico.slurm"
MANIFEST="$TARGET/trabajos_escalabilidad.tsv"

# No volver a enviar accidentalmente una cadena existente.
if [ -e "$MANIFEST" ]; then
    echo "ERROR: ya existe el manifiesto de envíos."
    exit 1
fi

if [ ! -s "$TARGET/x1/resultados/mpi32/Turrialba.res.nc" ]; then
    echo "ERROR: no se encuentra el resultado archivado de x1/MPI32."
    exit 1
fi

# Verificar las cinco preparaciones antes de enviar cualquier solver.
for MESH in x1 x4 x16 x64 x256; do
    DIR="$TARGET/$MESH"

    for FILE in \
        Turrialba.inp \
        Turrialba.dbs.nc \
        Turrialba.src \
        Turrialba.tgsd.tephra; do

        if [ ! -s "$DIR/$FILE" ]; then
            echo "ERROR: falta $DIR/$FILE"
            exit 1
        fi
    done
done

# Evitar solapamiento con otros solvers.
if squeue -h -u "$USER" -o "%j" | grep -Eq '^turr-x(1|4|16|64|256)-mpi(32|16|8|4|2|1)$'; then
    echo "ERROR: hay solvers activos o pendientes."
    exit 1
fi

printf 'job_id\tmalla\tmpi\tpx\tpy\n' > "$MANIFEST"

PREVIOUS=""
COUNT=0

for NPROC in 32 16 8 4 2 1; do
    case "$NPROC" in
        32) PX=8; PY=4 ;;
        16) PX=4; PY=4 ;;
         8) PX=4; PY=2 ;;
         4) PX=2; PY=2 ;;
         2) PX=2; PY=1 ;;
         1) PX=1; PY=1 ;;
    esac

    for MESH in x1 x4 x16 x64 x256; do
        # x1/MPI32 ya se ejecutó y archivó.
        if [ "$MESH" = x1 ] && [ "$NPROC" -eq 32 ]; then
            continue
        fi

        DIR="$TARGET/$MESH"
        DEST="$DIR/resultados/mpi$NPROC"
        mkdir -p "$DEST"

        if [ -e "$DEST/Turrialba.res.nc" ]; then
            echo "ERROR: resultado existente en $DEST"
            exit 1
        fi

        if [ "$MESH" = x256 ]; then
            LIMIT="72:00:00"
        else
            LIMIT="12:00:00"
        fi

        ARGS=(
            "--job-name=turr-${MESH}-mpi${NPROC}"
            "--ntasks=$NPROC"
            "--mem=64G"
            "--time=$LIMIT"
            "--output=$DEST/slurm_%j.out"
            "--error=$DEST/slurm_%j.err"
            "--export=ALL,MESH=$MESH,NPROC=$NPROC,PX=$PX,PY=$PY"
        )

        if [ -n "$PREVIOUS" ]; then
            ARGS+=("--dependency=afterok:$PREVIOUS")
        fi

        JOB=$(sbatch --parsable "${ARGS[@]}" "$MASTER")
        JOB="${JOB%%;*}"

        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$JOB" "$MESH" "$NPROC" "$PX" "$PY" >> "$MANIFEST"

        PREVIOUS="$JOB"
        COUNT=$((COUNT + 1))

        echo "Enviado $COUNT/29: $MESH MPI$NPROC -> Job $JOB"
    done
done

echo
echo "=== TOTAL ENVIADO: $COUNT ==="
echo "Manifiesto: $MANIFEST"
