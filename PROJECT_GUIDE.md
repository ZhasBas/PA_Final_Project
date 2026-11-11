# Project Guide: How the Traffic Simulation Fits Together

This project simulates cars moving around a one-lane circular road using the Nagel–Schreckenberg (NaSch) model. The road is a row of cells; each car has a position and speed. At each step cars accelerate, brake to keep a safe gap, may slow down randomly, and then move. The same seed gives every mode the same random slowdowns, making their results directly comparable.

## The four execution modes

- **Serial (`serial`)** runs the full update loop on one CPU thread. It is the reference implementation used for correctness checks and speedup comparisons.
- **OpenMP (`openmp`)** uses multiple threads on one shared-memory computer. Threads read the old state and each writes a separate car's new state. A loop barrier completes the step before the arrays are swapped.
- **MPI (`mpi`)** runs multiple processes, often across machines. Each MPI rank owns a contiguous block of car IDs. At each step, ranks exchange the next block's first car position, which supplies the boundary gap needed by the last car in each block. The final state is gathered for reporting or verification.
- **Hybrid (`hybrid`)** combines both approaches: MPI distributes blocks between ranks, then OpenMP threads update the cars owned by each rank. MPI communication stays on the main thread.

All modes update from the previous step's state, so cars do not observe partly updated values. `--verify` runs a serial copy with the same input and compares final positions and speeds exactly.

## Files and tools

- `src/traffic_sim.cpp` contains the model, command-line options, serial/OpenMP loops, MPI distribution and boundary exchange, timing, CSV output, and verification.
- `CMakeLists.txt` configures optional OpenMP/MPI support and defines the CTest correctness checks. `Makefile` provides a simpler build entry point.
- `tools/benchmark.py` runs repeated configurations with the same input, saves every timed sample to a raw CSV, and writes median time, speedup, and efficiency to a summary CSV.
- `tools/plot_results.py` reads that summary and creates speedup and efficiency graphs. Python runs these helper scripts; it is not part of the simulation kernel. Matplotlib is needed for graphs.
- `results/` contains the benchmark CSV files and graphs already produced for this project.

## Build and run (Linux or WSL)

Install CMake, a C++ compiler, Open MPI, and (for graphs) Matplotlib, then build all modes:

```sh
sudo apt install build-essential cmake libopenmpi-dev openmpi-bin python3-matplotlib
cmake -S . -B build-linux-mpi -DCMAKE_CXX_COMPILER=mpicxx \
  -DTRAFFIC_ENABLE_MPI=ON -DTRAFFIC_ENABLE_OPENMP=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-linux-mpi -j2
ctest --test-dir build-linux-mpi --output-on-failure
```

Examples (the launcher controls the number of MPI ranks; `OMP_NUM_THREADS` controls threads per process):

```sh
./build-linux-mpi/traffic_sim --mode serial --length 100000 --steps 1000 --density 0.2 --verify
OMP_NUM_THREADS=2 ./build-linux-mpi/traffic_sim --mode openmp --length 100000 --steps 1000 --density 0.2 --verify
mpirun --oversubscribe -np 4 ./build-linux-mpi/traffic_sim --mode mpi --length 100000 --steps 1000 --density 0.2 --verify
OMP_NUM_THREADS=2 mpirun --oversubscribe -np 4 ./build-linux-mpi/traffic_sim --mode hybrid --length 100000 --steps 1000 --density 0.2 --verify
```

Use `--help` to see the available model options. Add `--csv FILE` to write per-step mean speed and traffic flow. CSV collection performs extra work and communication, so leave it off when comparing kernel timings. The README documents the verified configurations, benchmark method, saved results, and hardware limitations.
