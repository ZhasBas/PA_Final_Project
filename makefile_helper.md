# `Makefile` Guide

`Makefile` is a set of named build recipes interpreted by the `make` command. It is a short alternative to the more configurable CMake setup.

## Variables

- `CXX ?= g++`: default C++ compiler, unless the user already supplied `CXX` in the environment or command line.
- `MPICXX ?= mpicxx`: default MPI compiler wrapper.
- `CXXFLAGS ?= ...`: default optimization level, C++17 language standard, and warning flags.
- `OPENMP ?= -fopenmp`: OpenMP compiler/linker flag, which can be overridden.
- `TARGET` and `SOURCE` name the ordinary executable path and C++ source file.

`?=` means “assign this value only if the variable is not already set.” `$()` reads a Make variable. `.PHONY` marks names such as `clean` as commands rather than files with those names.

## Targets (commands)

### `all`

The first target is Make's default, so running `make` is equivalent to `make all`. `all` depends on `$(TARGET)`, which tells Make to build the executable if it is missing or older than its source.

### `$(TARGET): $(SOURCE)`

This is a file target: build `build/traffic_sim` when `src/traffic_sim.cpp` changes or the executable does not exist. Its recipe creates `build/`, then runs the compiler with flags and writes the executable. A tab at the start identifies recipe lines to Make. The `$<` automatic variable means the first prerequisite, here the source file.

### `mpi`

Creates `build/` and calls `mpicxx` with C++ flags, OpenMP, and `-DTRAFFIC_USE_MPI=1`. The macro turns on MPI sections in the C++ source. The output is `build/traffic_sim_mpi`.

### `check`

Depends on the ordinary target, so that target is built first. Then it runs `tests/check_modes.sh`, passing the executable path as the script argument.

### `clean`

Runs `rm -rf build` to delete the build output directory. It does not delete source files or saved benchmark results.

## Recipe syntax

Lines beginning with `#` are comments. Compiler commands are ordinary shell commands executed by Make. `$@` would mean the target name (not used in this Makefile); `$<` means the first prerequisite. `\` in a shell command can continue it onto the next physical line.
