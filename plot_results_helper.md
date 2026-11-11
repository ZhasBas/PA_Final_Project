# `tools/plot_results.py` Function Guide

This script reads the summary CSV from `benchmark.py` and draws a PNG containing speedup and efficiency graphs. It does not launch simulations or measure time.

## Imports

- `argparse` reads the input CSV and output image options.
- `csv` reads rows from the benchmark summary.

Matplotlib is imported inside `main()` because it is needed only when actually generating a graph. `MaxNLocator` controls integer tick marks on worker-count axes.

## `main()`

### 1. Read input and output names

The parser accepts an optional positional CSV filename (default `benchmarks.csv`) and `--output` filename (default `performance.png`). An optional positional argument is a value written without a flag name.

### 2. Load plotting libraries and CSV data

The `try/except ImportError` gives a clear install instruction if Matplotlib is unavailable. `csv.DictReader` treats the first CSV row as column names and returns each later row as a dictionary, so values such as `row["mode"]` can be used by name. An empty file is rejected because there is nothing to plot.

### 3. Create the two plots

`plt.subplots(1, 2, ...)` creates a figure with one row and two axes: speedup on the left and efficiency on the right. Color and marker dictionaries choose a visual style per mode.

The loop over `serial`, `openmp`, `mpi`, and `hybrid`:

1. Filters CSV rows to the current mode.
2. For hybrid rows, groups them by rank count. This keeps, for example, 1 rank × 2 threads visibly separate from 2 ranks × 1 thread even though both use two workers.
3. Sorts each group by worker count and thread count.
4. Converts CSV strings to integers/floats, then plots workers against speedup and efficiency.

The ideal speedup reference is a diagonal line from 1 worker/1× speedup to the largest worker count. The ideal efficiency reference is horizontal at 1.0. Labels, titles, grids, legends, and integer x-axis ticks explain the graph.

### 4. Save the image

The title gets length, steps, and density from the first CSV row. `fig.tight_layout()` reduces overlap; `fig.savefig(..., dpi=160)` writes the PNG; `print` reports its path.

## Script entry point

The `if __name__ == "__main__":` guard calls `main()` only when this file is run directly, not when imported as a Python module.

## Data flow

`benchmark summary CSV` → `csv.DictReader` → grouped rows and calculated columns → Matplotlib figure → output PNG.
