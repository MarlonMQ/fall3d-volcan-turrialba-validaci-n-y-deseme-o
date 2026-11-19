#!/bin/bash
#SBATCH --partition=kura
#SBATCH --account=ucr
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1

set -euo pipefail

BASE="$HOME/cc_investigation/fall3d"
TARGET="/work/$USER/fall3d/experimentos-5h/escalabilidad-nz40"
DIR="$TARGET/$MESH"
DEST="$DIR/resultados/mpi$NPROC"
FALL3D="$BASE/build-openmpi-correcto/bin/Fall3d.x"

export PATH="/opt/compilers/gcc-9.3.0/bin:/opt/tools/openmpi-4.0.5/bin:$PATH"
export LD_LIBRARY_PATH="/opt/libs/netcdf-fortran-4.5.3-mpich/lib:/opt/libs/netcdf-c-4.7.4/lib:/opt/libs/hdf5-1.12.0-parallel/lib:/opt/tools/openmpi-4.0.5/lib:/opt/compilers/gcc-9.3.0/lib64:${LD_LIBRARY_PATH:-}"

cd "$DIR"

echo "=== INICIO: $MESH MPI$NPROC ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Nodo: $(hostname)"
echo "Descomposición: $PX x $PY x 1"
echo "Fecha: $(date)"

# Evitar sobrescribir resultados existentes.
if [ -e "$DEST/Turrialba.res.nc" ] || [ -e Turrialba.res.nc ]; then
    echo "ERROR: ya existe un resultado para esta ejecución."
    exit 1
fi

START=$(date +%s)

mpirun -np "$SLURM_NTASKS" \
    "$FALL3D" Fall3d Turrialba.inp "$PX" "$PY" 1

END=$(date +%s)
SECONDS_SOLVER=$((END - START))

test -s Turrialba.res.nc
test -s Turrialba.Fall3d.log

# Guardar resultados antes de permitir el siguiente trabajo.
mv Turrialba.res.nc "$DEST/"
mv Turrialba.Fall3d.log "$DEST/"

if [ -f Turrialba.Fall3d.json ]; then
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
