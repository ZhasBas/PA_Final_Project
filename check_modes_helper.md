# `tests/check_modes.sh` Guide

This Bash script runs a small correctness check in each available execution mode. It passes `--verify` so the C++ executable compares the result with its serial reference.

## Script, line by line

### `#!/usr/bin/env bash`

The shebang tells Linux to run the file with Bash, found through the current `PATH`.

### `set -euo pipefail`

Strict shell behavior: `-e` exits if a command fails; `-u` treats an unset variable as an error; `pipefail` makes a pipeline fail if any command in it fails. This prevents later checks from hiding an earlier failure.

### `exe="${1:-./build/traffic_sim}"`

Uses the first script argument as the executable path. `${1:-...}` means use the default path if the first argument is missing or empty.

### Serial and OpenMP runs

The next three commands run serial mode, then OpenMP with one and four threads. They all use the same road length, steps, density, and seed. `OMP_NUM_THREADS=N command` sets that environment variable only for that command. If any run fails or verification mismatches, `set -e` stops the script.

### Optional MPI and hybrid runs

`[[ ... ]] && ...` conditionally executes the block only when the MPI executable is executable (`-x`) and `mpirun` is available in `PATH` (`command -v`). It runs MPI with three ranks and hybrid with three ranks × two threads. These commands use `build/traffic_sim_mpi` directly; the `exe` variable is only used for serial/OpenMP checks.

### Final message

`echo` prints that available checks passed. Because of `set -e`, reaching this line means every attempted check exited successfully. MPI checks may have been skipped if MPI prerequisites were absent.

## How it fits the project

Run `make check` to build the default executable and invoke this script. For the full MPI-enabled test matrix, configure CMake with MPI enabled and run CTest; the MPI tests listed in `CMakeLists.txt` are separate from this shell script.
