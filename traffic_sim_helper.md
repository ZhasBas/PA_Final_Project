# `src/traffic_sim.cpp` Function Guide

This document explains the functions and shared data structures in the simulator. The program stores cars in vehicle-ID order; each vehicle has a road position and a speed. The same functions are used by the serial, OpenMP, MPI, and hybrid modes where possible.

## Shared data structures

### `Config`

`Config` is a `struct`, a named bundle of related values. It stores the user-selected road length, time steps, maximum speed, car density, random slowdown probability, seed, execution mode, optional CSV filename, and whether correctness verification is requested. The `= ...` values are defaults used when the user does not supply a command-line option.

### `State`

`State` has two `vector<int>` arrays: `positions` and `speeds`. A vector is a dynamically sized array. Index `i` refers to vehicle ID `i` in both vectors, so `positions[i]` and `speeds[i]` always belong to the same car.

### `Metrics`

`Metrics` holds one measurement row: the simulation step number, mean vehicle speed, and traffic flow. `measure` creates these values and `write_csv` saves them.

## Randomness and input

### `uint64_t mix64(uint64_t x)`

Takes an unsigned 64-bit integer and scrambles its bits using shifts, XORs, and multiplication. This is a small integer hash, not a stored random-number generator. Similar input numbers produce well-mixed outputs. The `ULL` suffix means an integer constant is unsigned and at least 64 bits wide.

### `double uniform01(uint64_t seed, uint64_t vehicle, uint64_t step)`

Returns a repeatable floating-point value in `[0, 1)`. It combines the seed, global vehicle ID, and step number, hashes the result with `mix64`, then scales high bits into a fraction.

This function is *stateless*: it does not advance a shared random sequence. Therefore any thread or MPI rank can compute the same car's random value independently. Serial and parallel runs make identical slowdown decisions when given the same seed and inputs.

### `Config parse_args(int argc, char** argv)`

Reads command-line arguments and returns a filled `Config`.

1. `argc` is the number of command-line pieces; `argv` is an array of C-style strings. The loop starts at index 1 because index 0 is the executable name.
2. Each recognized option reads its following value. For example, `--length 5000` calls `stoi` to convert the text `5000` to an integer; `stod` converts decimal values; `stoull` converts the seed to an unsigned integer.
3. `--verify` is a flag and needs no following value. `--help` prints usage and exits.
4. The function checks ranges and confirms the requested mode exists in this build. `#ifndef _OPENMP` and `#ifndef TRAFFIC_USE_MPI` are compile-time checks: the enclosed error is included when that feature was not compiled in.
5. Invalid input throws `invalid_argument`; `main` catches and reports it.

## Initial state and one-car rules

### `State make_initial_state(const Config& cfg)`

Builds and returns the initial global road state.

- It scans every road cell from 0 to `length - 1`.
- A car is placed in a cell when its deterministic draw is less than the requested density.
- Cars are appended in cell order, giving them stable IDs. Their starting speeds are also selected deterministically between zero and `vmax`.
- If no cell gets a car, it adds one stationary car so the simulation always has a vehicle to process.

`const Config&` means the function receives a read-only reference to the configuration, rather than copying it. `State` is returned by value to the caller.

### `int gap_to_next(const vector<int>& positions, size_t i, int next_position, int length)`

Computes the forward distance from vehicle `i` to the next vehicle. If the next car is at a lower cell index, adding `length` wraps the distance around the ring. `const vector<int>&` avoids copying the array while preventing this function from changing it. The returned gap includes the current car's cell; braking later uses `gap - 1` as the largest safe speed.

### `int updated_speed(int old_speed, int gap, int vmax, double slowdown, uint64_t seed, size_t vehicle, int step)`

Computes one car's new speed in NaSch order:

1. `min(old_speed + 1, vmax)` accelerates, but caps the result at the speed limit.
2. `min(v, gap - 1)` brakes to keep at least one cell from the next car.
3. If speed remains positive and the deterministic draw is below `slowdown`, it subtracts one.

It returns the new speed; it does not modify any arrays. Movement is handled by the step functions after speed is known.

## Serial and shared-memory work

### `void advance_serial(State& state, const Config& cfg, int step, bool parallel)`

Advances every vehicle by exactly one time step. `State&` is a mutable reference, so the function replaces the caller's state. `parallel` selects the OpenMP loop when OpenMP support was compiled in; otherwise the serial loop is used.

1. It allocates `new_positions` and `new_speeds`, initially sized to the car count. Their indices correspond to old vehicle IDs.
2. For each vehicle, it finds the next vehicle (the final ID wraps to ID 0), obtains the gap, computes a new speed, and calculates `(old_position + new_speed) % length` to wrap movement around the ring.
3. In the OpenMP branch, `#pragma omp parallel for schedule(static)` asks OpenMP to split loop iterations into roughly even chunks among threads. Each iteration reads old arrays and writes only its own new-array index. The implicit barrier at the end makes all threads finish before the arrays are swapped.
4. `state.positions.swap(new_positions)` and the speed equivalent replace the old state with the completed new state efficiently.

The `n == 1` special case sets the gap to the whole road length: a lone car has no other car to brake for.

## MPI distribution and hybrid work

Everything in this section is inside `#ifdef TRAFFIC_USE_MPI`, so it only exists in MPI-enabled builds.

### `void make_partition(int n, int size, vector<int>& counts, vector<int>& displs)`

Divides `n` global vehicle IDs among `size` MPI ranks. For every rank `r`, `counts[r]` is how many vehicles it owns and `displs[r]` is the first global vehicle ID in its block. Integer division creates contiguous, nearly equal ranges. The output vectors are passed by non-const reference so the function can fill them.

### `State mpi_initialize(const Config& cfg, int rank, int size, vector<int>& counts, vector<int>& displs)`

Creates the initial MPI state and returns each process's local slice.

1. Rank 0 creates the full initial state and counts the cars; other ranks start with `n = 0`.
2. `MPI_Bcast` broadcasts the car count from rank 0 to all ranks. A broadcast is a collective call: every rank in the communicator must participate.
3. Every rank calculates the same partition with `make_partition` and allocates arrays for its own count.
4. Two `MPI_Scatterv` calls distribute positions and speeds. The `v` means each rank may receive a different count. Rank 0 supplies the full arrays; each rank receives only its assigned slice.
5. The returned `State` contains only this rank's owned cars.

### `void advance_mpi(State& local, ..., bool parallel)`

Advances one time step for the vehicles owned by one rank. In MPI mode its local loop is serial; in hybrid mode `parallel` is true and OpenMP shares that loop among threads.

1. It allocates new local output arrays.
2. A rank with no cars skips communication and computation. An active rank searches `counts` backward and forward around the circular rank order for the nearest nonempty owners.
3. `MPI_Sendrecv` sends this rank's first position to the previous active owner while receiving the next active owner's first position. This received position is the *halo*: one remote value needed to find the gap for the last locally owned car. Combining send and receive avoids separate blocking-send ordering problems.
4. For each local car, the next position comes from the local array except at the final local index, where the halo is used. The global ID is `displs[rank] + j`, ensuring random slowdowns match serial vehicle IDs.
5. `#pragma omp parallel for ... if(parallel)` uses OpenMP only when `parallel` is true. MPI communication happens before this loop, so worker threads do not call MPI.
6. The local old and new arrays are swapped, completing the synchronous step.

The parameters `counts` and `displs` describe global ownership; `rank` selects the current process; `size` is total process count; `total_cars` handles the one-car gap case.

### `State mpi_gather(const State& local, ..., int rank)`

Collects distributed state onto rank 0 and returns the full `State` there. It allocates full arrays on rank 0, then uses `MPI_Gatherv` twice to put each rank's slice at its displacement. Other ranks return an empty `State`. This is used for CSV measurements and final reporting/verification.

## Output and measurement

### `Metrics measure(const State& state, const Config& cfg, int step)`

Adds vehicle speeds to calculate mean speed. It calculates flow as `car_count * mean_speed / road_length`, then returns a `Metrics` row. The empty-state check prevents division by zero, though initialization normally ensures at least one car.

### `bool same_state(const State& a, const State& b)`

Returns `true` only if both position arrays and speed arrays compare equal. Vector equality checks same length and same value at every index, so this is an exact final-state comparison in vehicle-ID order.

### `void write_csv(const string& path, const vector<Metrics>& rows)`

Opens `path`, writes a header, then writes one comma-separated row per metric. If the file cannot be opened, it throws `runtime_error`. `setprecision(10)` controls how many significant digits are written for the floating-point columns.

## `main`: how one run is coordinated

`int main(int argc, char** argv)` is the program entry point. The operating system calls it when `traffic_sim` starts; its integer return value becomes the process exit status (zero means success).

1. In an MPI build, `MPI_Init_thread` starts MPI and requests `MPI_THREAD_FUNNELED`, meaning MPI calls are restricted to the main thread. `MPI_Comm_rank` gives this process its rank ID; `MPI_Comm_size` gives the number of ranks. Non-MPI builds use rank 0 and size 1.
2. A `try` block parses options. Exceptions from invalid options or file output are handled by the `catch` near the end.
3. Serial/OpenMP modes initialize the full state on rank 0. MPI/hybrid modes call `mpi_initialize`, which distributes the cars.
4. It stores the total car count and allocates `trace` for optional per-step CSV rows.
5. MPI ranks synchronize with `MPI_Barrier`, then record a `steady_clock` start time. A steady clock is monotonic, so system clock adjustments do not distort durations.
6. The step loop calls `advance_mpi` for distributed modes or `advance_serial` otherwise. If CSV output was requested, it also measures each step; distributed runs gather the state each step for that calculation.
7. MPI ranks synchronize at the end. Each computes elapsed time, and `MPI_Reduce` with `MPI_MAX` gives rank 0 the slowest rank time. The final state is gathered for output.
8. Rank 0 writes optional CSV, prints configuration, timing, throughput, mean speed, and flow. If `--verify` was set, it rebuilds the same initial state, runs the serial algorithm, and uses `same_state` to check the result.
9. MPI broadcasts the verification status so every rank exits consistently, then `MPI_Finalize` closes MPI. Errors are printed by rank 0; an MPI build uses `MPI_Abort` so all ranks stop together.

`#ifdef` / `#endif` sections are compile-time conditional code. They allow one source file to build with or without MPI and OpenMP. `const` marks values that a function should not change; `&` in a parameter means a reference to an existing object rather than a copy; `return` sends a value back to the caller; `void` means a function has no return value.
