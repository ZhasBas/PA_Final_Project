# Code Explanation: Traffic Flow Simulation

This note follows the project from build to simulation, correctness checking, benchmarking, and graph generation. The main simulation is C++; the shell and Python scripts automate building/checking and analyzing runs.

## 1. Build and test files

### `CMakeLists.txt`

1. Declares a C++17 executable named `traffic_sim`, built from `src/traffic_sim.cpp`.
2. If enabled, finds and links OpenMP. If MPI is enabled, finds MPI and defines `TRAFFIC_USE_MPI`, which compiles in MPI support.
3. Registers CTest cases: a serial check; OpenMP checks with one and two threads; MPI checks with two and three ranks; and hybrid checks with two ranks and one or two threads per rank. The tests pass `--verify`, so each parallel result is compared with serial.

The CMake options `TRAFFIC_ENABLE_OPENMP` and `TRAFFIC_ENABLE_MPI` control which features are built. MPI is off by default; see the exact Linux configuration in `README.md`.

### `Makefile`

- `make` (or `make all`) compiles a non-MPI executable to `build/traffic_sim`, using `g++` and OpenMP flags by default.
- `make mpi` builds a separate MPI-enabled executable at `build/traffic_sim_mpi`, using `mpicxx`.
- `make check` builds the default executable and runs `tests/check_modes.sh`.
- `make clean` deletes the local `build/` directory.

The Makefile is a lightweight alternative to CMake. The README's CMake instructions are the tested path for running CTest and all MPI/hybrid modes together.

### `tests/check_modes.sh`

1. Uses strict Bash settings (`set -euo pipefail`), so errors, unset variables, or failed commands stop the check.
2. Runs serial verification, then OpenMP verification with one and four threads, all with identical length, step count, density, and seed.
3. If `build/traffic_sim_mpi` exists and `mpirun` is installed, also checks MPI with three ranks and hybrid with three ranks and two threads per rank.
4. Prints a success message if all available checks finish successfully.

This script complements CTest. Its MPI checks are conditional; CTest from an MPI-enabled CMake build defines its own MPI test matrix.

## 2. Simulation program: `src/traffic_sim.cpp`

### Step A: Parse the run configuration

`Config` holds road length, number of steps, maximum speed, density, random slowdown probability, seed, selected mode, and optional CSV/verification settings. `parse_args` reads command-line flags such as `--mode`, `--length`, `--steps`, `--density`, and `--seed`, validates the values, and rejects modes unavailable in the current build. `--help` prints the supported options.

### Step B: Make the initial road state

`State` contains two parallel arrays: `positions[i]` and `speeds[i]` describe vehicle ID `i`. `make_initial_state` visits each road cell and uses a deterministic hash of the seed and cell to decide whether a car starts there. It assigns a deterministic initial speed as well. If the density draw produces no cars, it inserts one stationary car so later calculations have a nonempty state.

The stateless `uniform01(seed, vehicle, step)` function supplies repeatable random slowdown decisions. Its result depends only on those inputs, not on which thread or rank happens to process the car.

### Step C: Update one time step using the NaSch rules

`updated_speed` applies the rules for a vehicle in order: accelerate by one up to `vmax`; brake so it cannot reach the next car; then, if its speed is positive, apply the random slowdown. `gap_to_next` calculates the forward circular distance to the next vehicle.

`advance_serial` creates new position and speed arrays and computes every vehicle from the unchanged old arrays. In OpenMP mode, the loop iterations write different output indices; after the loop's implicit barrier, the old and new arrays are swapped. This two-state approach makes updates synchronous and prevents a thread from seeing a neighbor's new, partially computed state.

### Step D: Distribute the work for MPI

When MPI is compiled in, `main` calls `MPI_Init_thread` asking for `MPI_THREAD_FUNNELED`: MPI calls happen on the main thread, while OpenMP worker threads only do the local update loop.

`mpi_initialize` has rank 0 create the initial global state. `make_partition` divides the ordered vehicle-ID range into contiguous, almost equal blocks. `MPI_Scatterv` gives each rank the positions and speeds for its exclusive block. Some ranks can own zero cars if there are more ranks than vehicles.

### Step E: Exchange the boundary and update each block

At every time step, `advance_mpi` finds the nearest nonempty previous and next owners. Each active rank uses `MPI_Sendrecv` to provide its first position to the previous owner and receive the next owner's first position. That received position is the halo value needed to calculate the gap for the last local car. Empty ranks are skipped.

Each rank computes only its own block. In `mpi` mode, the local loop is serial. In `hybrid` mode, OpenMP distributes those local loop iterations among threads; all MPI communication has already completed on the main thread. At the end of the loop, each rank swaps in its new local arrays and proceeds to the next step.

### Step F: Measure, report, and check the result

`main` starts the timer after initialization. Distributed runs synchronize before the timed loop and after it, then reduce elapsed times using `MPI_MAX`; the reported time represents the slowest rank. Final reduction and gathering are outside that interval. If per-step CSV output is enabled, gathering metrics each step is part of the timed loop, so CSV mode should not be used for kernel performance comparisons.

`mpi_gather` assembles the final distributed arrays on rank 0. `measure` calculates average speed and flow. If `--verify` was requested, rank 0 re-runs the same input through `advance_serial` and compares final positions and speeds exactly. A mismatch prints `verification=FAIL` and returns a failing status; a match prints `verification=PASS`.

## 3. Benchmark runner: `tools/benchmark.py`

1. Parses the executable path, workload, modes, rank/thread counts, repeat count, warmup count, MPI launcher options, and OpenMP wait policy.
2. Builds a configuration list: one serial baseline, one OpenMP configuration per thread count, one MPI configuration per rank count, and each requested rank/thread combination for hybrid.
3. For each run, sets `OMP_NUM_THREADS`, disables dynamic OpenMP team sizing, and sets the wait policy. MPI/hybrid commands are prefixed with `mpirun -np RANKS`; `--oversubscribe` is added when requested.
4. Executes one or more unrecorded warmups for each configuration. It then shuffles configuration order for each measured repeat to reduce ordering bias.
5. Reads `elapsed_seconds=...` from the C++ program's output and stores every measured sample in a raw CSV.
6. Computes the median time for each configuration, then calculates speedup as serial median divided by that configuration's median. Efficiency is speedup divided by `ranks × threads`.
7. Writes the median summary CSV and prints its output paths.

The runner does not enable `--verify` or CSV collection, keeping benchmark runs focused on the timed simulation. The `--seed` option still makes all modes use the same deterministic input and slowdown sequence.

## 4. Graph generator: `tools/plot_results.py`

1. Opens the summary CSV made by `benchmark.py` (or the supplied CSV path).
2. Loads Matplotlib and creates two panels: speedup and parallel efficiency.
3. Plots each execution mode against its requested worker count. Hybrid data is separated into curves by MPI rank count, so configurations with the same total worker count remain distinguishable.
4. Adds ideal reference lines, labels, grid, and a title using the workload details in the CSV.
5. Saves the figure to the requested output path (default `performance.png`).

The raw CSV preserves individual timings; the summary CSV drives the graphs. Both help make the analysis traceable rather than relying on a single run.

## 5. Typical end-to-end sequence

The files form this practical chain. Each step has a specific job:

1. **`CMakeLists.txt` builds the C++ program.** You run CMake to choose whether OpenMP and MPI are enabled. CMake compiles `src/traffic_sim.cpp` and produces the executable `build-linux-mpi/traffic_sim`. That executable is the actual traffic simulation; the other tools prepare, check, or analyze it.

2. **`tests/check_modes.sh` and CTest check that the simulation is correct.** They launch the executable with fixed inputs and `--verify`. The executable calculates the result for the selected mode, runs the serial version as a reference, and reports whether the final car positions and speeds match. CTest gets its test list from `CMakeLists.txt`; the shell script is a separate, shorter way to run available mode checks.

3. **`tools/benchmark.py` measures how long the executable takes.** It repeatedly launches that same executable with the requested mode, road size, step count, rank count, and thread count. MPI runs are launched through `mpirun`; OpenMP thread counts are passed through environment variables. The program prints its elapsed time, and the Python script collects it. It writes:
   - a **raw CSV**, with one row per measured run;
   - a **summary CSV**, with the median time, speedup, and efficiency for each configuration.

4. **`tools/plot_results.py` draws the graphs from the summary CSV.** It does not run the simulation or calculate new timings. It reads the summary produced by `benchmark.py` and saves an image with speedup and efficiency plots.

5. **`results/` holds the saved outputs.** Its CSV files are the benchmark data (`*_raw.csv` are individual runs; the other CSVs are summaries). Its PNG files are the graphs generated from those summaries. These are evidence and analysis outputs, not inputs required to run the simulation.

In short: **CMake builds the simulator → tests ask the simulator to check correctness → the benchmark script runs it many times and saves timing CSVs → the plot script turns the summary CSV into graphs.** The C++ program does the traffic calculation throughout; Python automates runs and presents measurements. For exact commands and existing results, see `README.md`; for basic terminology, see `PROJECT_GUIDE.md`.
