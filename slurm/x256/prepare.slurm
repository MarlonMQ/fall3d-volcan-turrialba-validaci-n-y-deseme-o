#!/bin/bash
#SBATCH --job-name=turr-x256-nz40-prepare
#SBATCH --partition=kura
#SBATCH --account=ucr
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=prepare_%j.out
#SBATCH --error=prepare_%j.err

set -euo pipefail

printf '\033[1;32m=== INICIO: PREPARACIÓN NZ40 ===\033[0m\n'

BASE="$HOME/cc_investigation/fall3d"
DIR="/work/$USER/fall3d/experimentos-5h/escalabilidad-nz40/x256"
FALL3D="$BASE/build-openmpi-correcto/bin/Fall3d.x"

export PATH="/opt/compilers/gcc-9.3.0/bin:/opt/tools/openmpi-4.0.5/bin:$PATH"
export LD_LIBRARY_PATH="/opt/libs/netcdf-fortran-4.5.3-mpich/lib:/opt/libs/netcdf-c-4.7.4/lib:/opt/libs/hdf5-1.12.0-parallel/lib:/opt/tools/openmpi-4.0.5/lib:/opt/compilers/gcc-9.3.0/lib64:${LD_LIBRARY_PATH:-}"

cd "$DIR"

echo "=== EJECUTANDO SETTGSD ==="
mpirun -np 1 "$FALL3D" SetTgsd Turrialba.inp
test -s Turrialba.tgsd.tephra

echo
echo "=== EJECUTANDO SETSRC ==="
mpirun -np 1 "$FALL3D" SetSrc Turrialba.inp
test -s Turrialba.src
test -s Turrialba.grn

echo
echo "=== ARCHIVOS GENERADOS ==="
ls -lh Turrialba.tgsd.tephra Turrialba.src Turrialba.grn

printf '\033[1;32m=== FIN: PREPARACIÓN NZ40 ===\033[0m\n'
