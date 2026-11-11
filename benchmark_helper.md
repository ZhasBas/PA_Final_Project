# `tools/benchmark.py` Function Guide

This script repeatedly launches the compiled C++ simulator. It records the simulator's reported elapsed time, then calculates median time, speedup, and efficiency. Python is orchestrating runs; the traffic update itself remains in `traffic_sim.cpp`.

## Imports

- `argparse` defines command-line options such as `--steps`.
- `csv` writes raw and summary comma-separated files.
- `os` copies and adjusts environment variables for child processes and splits output filenames.
- `random` shuffles run order reproducibly.
- `re` finds the elapsed-time text in program output.
- `statistics` calculates medians.
- `subprocess` launches the executable and `mpirun`.
- `sys` prints errors to standard error and sets failure exit status.

## Functions

### `integer_list(value)`

Converts text such as `"1,2,4"` into `[1, 2, 4]`. It strips whitespace around entries and rejects an empty list or any count below 1. Raising `argparse.ArgumentTypeError` tells `argparse` to show a useful command-line error. This function is used for `--threads` and `--ranks`.

### `run(command, env)`

Runs one command with the supplied environment dictionary.

- `subprocess.run(..., check=True)` raises an error if the child exits unsuccessfully.
- `text=True` decodes output as text; stdout and stderr are captured instead of printed immediately.
- `re.search` looks for `elapsed_seconds=` followed by a number in stdout.
- It returns that number as a Python `float`. If the expected output is missing, it raises `RuntimeError` with the captured stdout.

### `main()`

Controls the full benchmark process.

#### 1. Read options

An `ArgumentParser` defines executable path, output filenames, workload parameters, repeats/warmups, seed, thread/rank lists, modes, MPI launcher and oversubscription, and OpenMP wait policy. The parsed options are stored in `args`. `parser.error(...)` prints usage and stops when a configuration is invalid. Serial is required because speedup needs a baseline.

#### 2. Build the configuration list

`base` contains workload arguments shared by each run: executable, road length, steps, density, and seed. `configs` contains tuples `(mode, ranks, threads)`. Serial uses `(serial, 1, 1)`, OpenMP adds a case for each thread count, MPI for each rank count, and hybrid for every requested rank/thread combination.

#### 3. Make a command for each configuration

`command_for(ranks)` creates the MPI launcher prefix. If requested, it includes `--oversubscribe`, then `-np RANKS`.

The nested `execute(config)` function:

1. Copies the current environment using `os.environ.copy()` so the parent process is not changed.
2. Sets `OMP_NUM_THREADS`, `OMP_DYNAMIC=FALSE`, and `OMP_WAIT_POLICY` for the child.
3. Adds an Open MPI oversubscription environment setting when relevant.
4. Builds the executable command; MPI and hybrid modes are prefixed with `mpirun`.
5. Calls `run` and returns the elapsed seconds.

#### 4. Warm up and measure

The script creates `random.Random(args.seed)`, a repeatable shuffler. It shuffles configurations for warmups and runs each the requested number of times without saving those times. For each measured repeat, it shuffles again, runs every configuration, and appends a dictionary (a set of named fields) to `raw_rows`. `samples_by_config` separately groups times by configuration for summary calculations.

#### 5. Write results

For each configuration, `statistics.median` calculates its representative time. The summary row includes workload details, rank/thread counts, worker count, wait policy, repeat count, median, and the individual samples in a semicolon-separated field.

After finding the serial median:

- `speedup = serial median / configuration median`
- `efficiency = speedup / workers`, where workers are `ranks * threads`

`csv.DictWriter` writes named dictionary fields as CSV columns. Raw output defaults to the summary filename with `_raw` before the extension. The script prints both output paths.

### Script entry point and error handling

```python
if __name__ == "__main__":
```

Python sets `__name__` to `"__main__"` when this file is run directly. The guard lets the file be imported without automatically starting a benchmark. The `try/except` catches expected launch and parsing failures, prints a concise error to stderr, and exits with status 1.

## Data flow

`benchmark.py` → starts `traffic_sim` (and `mpirun` for distributed modes) → reads `elapsed_seconds` from the C++ output → writes raw and summary CSV files. `plot_results.py` later consumes the summary CSV.
