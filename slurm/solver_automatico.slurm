#!/usr/bin/env bash
#SBATCH --partition=kura
#SBATCH --account=ucr
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
# El número de tareas, memoria, tiempo y rutas de logs se fijan al invocar sbatch.
set -euo pipefail

: "${WORK_ROOT:?Falta WORK_ROOT}"
: "${FALL3D_BIN:?Falta FALL3D_BIN}"
: "${MESH:?Falta MESH}"
: "${NPROC:?Falta NPROC}"
: "${PX:?Falta PX}"
: "${PY:?Falta PY}"

DIR="$WORK_ROOT/$MESH"
DEST="$DIR/resultados/mpi$NPROC"

export PATH="/opt/compilers/gcc-9.3.0/bin:/opt/tools/openmpi-4.0.5/bin:$PATH"
export LD_LIBRARY_PATH="/opt/libs/netcdf-fortran-4.5.3-mpich/lib:/opt/libs/netcdf-c-4.7.4/lib:/opt/libs/hdf5-1.12.0-parallel/lib:/opt/tools/openmpi-4.0.5/lib:/opt/compilers/gcc-9.3.0/lib64:${LD_LIBRARY_PATH:-}"

cd "$DIR"
for FILE in Turrialba.inp Turrialba.era5.nc Turrialba.dbs.nc Turrialba.src Turrialba.tgsd.tephra Turrialba.grn; do
    [[ -s "$FILE" ]] || { echo "ERROR: falta la entrada $DIR/$FILE" >&2; exit 1; }
done
[[ "$SLURM_NTASKS" -eq "$NPROC" ]] || { echo 'ERROR: NPROC y SLURM_NTASKS no coinciden.' >&2; exit 1; }
[[ "$((PX * PY))" -eq "$NPROC" ]] || { echo 'ERROR: descomposición MPI inválida.' >&2; exit 1; }
[[ ! -e "$DEST/Turrialba.res.nc" && ! -e Turrialba.res.nc ]] || {
    echo 'ERROR: ya existe un resultado para esta ejecución.' >&2; exit 1;
}

echo "=== INICIO: $MESH MPI$NPROC ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Nodo: $(hostname)"
echo "Descomposición: $PX x $PY x 1"
echo "Fecha: $(date)"

START="$(date +%s)"
mpirun -np "$SLURM_NTASKS" "$FALL3D_BIN" Fall3d Turrialba.inp "$PX" "$PY" 1
END="$(date +%s)"
SECONDS_SOLVER=$((END - START))

test -s Turrialba.res.nc
test -s Turrialba.Fall3d.log

mv Turrialba.res.nc "$DEST/"
mv Turrialba.Fall3d.log "$DEST/"
if [[ -f Turrialba.Fall3d.json ]]; then
    mv Turrialba.Fall3d.json "$DEST/"
fi
shopt -s nullglob
for FILE in Turrialba.*.rst.nc; do
    mv "$FILE" "$DEST/"
done

printf 'job_id=%s\nmalla=%s\nmpi=%s\ndescomposicion=%sx%sx1\ntiempo_solver_segundos=%s\n' \
    "$SLURM_JOB_ID" "$MESH" "$NPROC" "$PX" "$PY" "$SECONDS_SOLVER" \
    > "$DEST/metricas.txt"

echo "Tiempo del solver: $SECONDS_SOLVER segundos"
echo "=== FIN: $MESH MPI$NPROC ==="
