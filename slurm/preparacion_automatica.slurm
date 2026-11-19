#!/usr/bin/env bash
#SBATCH --partition=kura
#SBATCH --account=ucr
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
# La memoria, el tiempo y los nombres de logs se indican desde preparar_entradas.sh.
set -euo pipefail

: "${WORK_ROOT:?Falta WORK_ROOT}"
: "${FALL3D_BIN:?Falta FALL3D_BIN}"
: "${MESH:?Falta MESH}"
: "${PREP_STAGE:?Falta PREP_STAGE (source/dbs)}"

DIR="$WORK_ROOT/$MESH"
export PATH="/opt/compilers/gcc-9.3.0/bin:/opt/tools/openmpi-4.0.5/bin:$PATH"
export LD_LIBRARY_PATH="/opt/libs/netcdf-fortran-4.5.3-mpich/lib:/opt/libs/netcdf-c-4.7.4/lib:/opt/libs/hdf5-1.12.0-parallel/lib:/opt/tools/openmpi-4.0.5/lib:/opt/compilers/gcc-9.3.0/lib64:${LD_LIBRARY_PATH:-}"

cd "$DIR"
[[ -s Turrialba.inp ]] || { echo 'ERROR: falta Turrialba.inp' >&2; exit 1; }
[[ -s Turrialba.era5.nc ]] || { echo 'ERROR: falta Turrialba.era5.nc' >&2; exit 1; }

printf 'INICIO malla=%s etapa=%s job=%s nodo=%s fecha=%s\n' \
    "$MESH" "$PREP_STAGE" "$SLURM_JOB_ID" "$(hostname)" "$(date -Is)"

case "$PREP_STAGE" in
    source)
        for FILE in Turrialba.tgsd.tephra Turrialba.src Turrialba.grn; do
            [[ ! -e "$FILE" ]] || { echo "ERROR: ya existe $FILE" >&2; exit 1; }
        done
        mpirun -np 1 "$FALL3D_BIN" SetTgsd Turrialba.inp
        test -s Turrialba.tgsd.tephra
        mpirun -np 1 "$FALL3D_BIN" SetSrc Turrialba.inp
        test -s Turrialba.src
        test -s Turrialba.grn
        ;;
    dbs)
        for FILE in Turrialba.dbs.nc Turrialba.dbs.pro; do
            [[ ! -e "$FILE" ]] || { echo "ERROR: ya existe $FILE" >&2; exit 1; }
        done
        test -s Turrialba.tgsd.tephra
        test -s Turrialba.src
        test -s Turrialba.grn
        mpirun -np 1 "$FALL3D_BIN" SetDbs Turrialba.inp
        test -s Turrialba.dbs.nc
        test -s Turrialba.dbs.pro
        ;;
    *)
        echo "ERROR: etapa desconocida: $PREP_STAGE" >&2
        exit 1
        ;;
esac

printf 'FIN malla=%s etapa=%s fecha=%s\n' "$MESH" "$PREP_STAGE" "$(date -Is)"
