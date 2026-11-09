#!/usr/bin/env bash
set -euo pipefail
exe="${1:-./build/traffic_sim}"
"$exe" --mode serial --length 2000 --steps 40 --density 0.22 --seed 17 --verify
OMP_NUM_THREADS=1 "$exe" --mode openmp --length 2000 --steps 40 --density 0.22 --seed 17 --verify
OMP_NUM_THREADS=4 "$exe" --mode openmp --length 2000 --steps 40 --density 0.22 --seed 17 --verify
if [[ -x ./build/traffic_sim_mpi ]] && command -v mpirun >/dev/null 2>&1; then
  mpirun -np 3 ./build/traffic_sim_mpi --mode mpi --length 2000 --steps 40 --density 0.22 --seed 17 --verify
  OMP_NUM_THREADS=2 mpirun -np 3 ./build/traffic_sim_mpi --mode hybrid --length 2000 --steps 40 --density 0.22 --seed 17 --verify
fi
echo "All available mode checks passed."
