# `CMakeLists.txt` Guide

CMake is a build-system generator. This file describes how to compile the C++ program and which correctness checks CTest should run. CMake itself does not implement the simulation.

## Project and executable

- `cmake_minimum_required(VERSION 3.16)` states the oldest supported CMake version.
- `project(traffic_flow_simulation LANGUAGES CXX)` names the project and enables the C++ language.
- `option(...)` creates user-selectable build settings. MPI defaults off; OpenMP defaults on but is used only if found.
- `add_executable(traffic_sim src/traffic_sim.cpp)` creates an executable target named `traffic_sim` from the C++ source.
- `target_compile_features(... cxx_std_17)` requires C++17 for that target.
- `if(MSVC) ... else() ... endif()` selects compiler flags: `/W4` for Microsoft Visual C++, or warnings plus optimization for other compilers.

## Optional OpenMP setup

`if(TRAFFIC_ENABLE_OPENMP)` runs the enclosed commands only if the option is on. `find_package(OpenMP)` searches for OpenMP. If `OpenMP_CXX_FOUND` is true, `target_link_libraries` connects its compiler and linker settings to `traffic_sim`. When it is absent, serial mode can still build.

## Optional MPI setup

`if(TRAFFIC_ENABLE_MPI)` searches for the MPI C++ toolchain and requires it (`REQUIRED`). Linking `MPI::MPI_CXX` provides the needed MPI compile/link settings. `target_compile_definitions` sets macros used by the source to include MPI code. The `OMPI_SKIP_MPICXX` and `MPICH_SKIP_MPICXX` macros disable old vendor C++ bindings; this program uses the C-style MPI API.

## CTest checks

- `enable_testing()` enables CTest registration.
- `add_test(NAME ... COMMAND ...)` adds a named command to the test list.
- The serial test always exists and runs `traffic_sim` with `--verify`.
- The `if(OpenMP_CXX_FOUND)` block adds OpenMP checks with one and two threads. `set_tests_properties(... ENVIRONMENT ...)` provides environment variables to that test process.
- The `if(TRAFFIC_ENABLE_MPI)` block loops over rank counts 2 and 3, registering MPI verification commands through `${MPIEXEC_EXECUTABLE}` and `${MPIEXEC_NUMPROC_FLAG}` (CMake-provided launcher and process-count flag).
- A second loop registers hybrid tests with two MPI ranks and one or two OpenMP threads. `PROCESSORS` tells CTest how many processing slots the test uses. The Open MPI environment setting allows runs on hosts that advertise fewer slots than requested.

Generator expressions such as `$<TARGET_FILE:traffic_sim>` expand to the actual executable path for the active build directory. `${NAME}` inserts the value of a CMake variable. Indentation is for readability; the `if`, `foreach`, and `endif` commands define the blocks.

## Build flow

Configure with `cmake -S . -B build-linux-mpi ...`; this reads the file and generates build files in the selected directory. `cmake --build build-linux-mpi` compiles the target. `ctest --test-dir build-linux-mpi` runs the registered tests.
