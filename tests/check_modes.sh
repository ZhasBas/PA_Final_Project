#!/usr/bin/env bash
# Run the available simulation modes and compare each result to serial.
set -euo pipefail
exe="${1:-./build/traffic_sim}"
# Every mode receives the same model inputs so --verify compares equivalent runs.
"$exe" --mode serial --length 2000 --steps 40 --density 0.22 --seed 17 --verify
OMP_NUM_THREADS=1 "$exe" --mode openmp --length 2000 --steps 40 --density 0.22 --seed 17 --verify
OMP_NUM_THREADS=4 "$exe" --mode openmp --length 2000 --steps 40 --density 0.22 --seed 17 --verify
if [[ -x ./build/traffic_sim_mpi ]] && command -v mpirun >/dev/null 2>&1; then
  # MPI checks run only when both the MPI executable and launcher are available.
  mpirun -np 3 ./build/traffic_sim_mpi --mode mpi --length 2000 --steps 40 --density 0.22 --seed 17 --verify
  OMP_NUM_THREADS=2 mpirun -np 3 ./build/traffic_sim_mpi --mode hybrid --length 2000 --steps 40 --density 0.22 --seed 17 --verify
fi
echo "All available mode checks passed."
