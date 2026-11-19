#!/bin/bash
#SBATCH --job-name=turr-nz60-mpi32
#SBATCH --partition=kura
#SBATCH --account=ucr
#SBATCH --nodes=1
#SBATCH --ntasks=32
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=fall3d_%j.out
#SBATCH --error=fall3d_%j.err

set -euo pipefail

printf '\033[1;32m=== INICIO: FALL3D NZ60 MPI32 ===\033[0m\n'

BASE="$HOME/cc_investigation/fall3d"
DIR="/work/$USER/fall3d/experimentos-5h/sensibilidad-vertical/nz60"
FALL3D="$BASE/build-openmpi-correcto/bin/Fall3d.x"

export PATH="/opt/compilers/gcc-9.3.0/bin:/opt/tools/openmpi-4.0.5/bin:$PATH"
export LD_LIBRARY_PATH="/opt/libs/netcdf-fortran-4.5.3-mpich/lib:/opt/libs/netcdf-c-4.7.4/lib:/opt/libs/hdf5-1.12.0-parallel/lib:/opt/tools/openmpi-4.0.5/lib:/opt/compilers/gcc-9.3.0/lib64:${LD_LIBRARY_PATH:-}"

cd "$DIR"

echo "Fecha de inicio: $(date)"
echo "Nodo: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "Procesos MPI: $SLURM_NTASKS"
echo "Descomposición: 8 x 4 x 1"

START=$(date +%s)

mpirun -np "$SLURM_NTASKS" \
    "$FALL3D" Fall3d Turrialba.inp 8 4 1

END=$(date +%s)

echo
echo "=== RESULTADOS ==="
echo "Tiempo de ejecución: $((END - START)) segundos"

ls -lh Turrialba.res.nc Turrialba.Fall3d.log

printf '\033[1;32m=== FIN: FALL3D NZ60 MPI32 ===\033[0m\n'
