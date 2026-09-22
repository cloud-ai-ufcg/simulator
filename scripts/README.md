# Automating batch runs

This document describes the generic mechanism used in this repository to run **many
simulator executions unattended**, varying configuration parameters between them,
collecting each one's metrics, and aggregating/plotting the results at the end.


## 1. The three layers

```
1 run                →  make setup-and-start-auto | setup-and-start-baseline | ...
N runs (matrix)      →  ./run_simulations.sh (repo root)
aggregation + plots  →  scripts/aggregate_scenario_metrics.py, list_scenario_runs.py, plots_comparation.r
```

- A single run is just a `make` target (see `make help` at the root). On its own, it
  already produces a complete output directory with metrics and plots.
- `run_simulations.sh` runs that target multiple times, each time editing
  `config.yaml`/`input.json` for a different combination of parameters, and renames each
  run's output to a name that encodes the parameters used.
- The scripts in `scripts/` scan a directory full of runs named this way and produce
  aggregated CSVs and comparison plots.

Any of the three layers can be used on its own — you don't need the whole matrix to run
a single execution, nor the aggregation step to inspect a single run.

## 2. Required environment

In addition to the hardware/software requirements already described in
[`../README.md`, section 4](../README.md#4-basic-information):

- **`yq`** (v4+) on `PATH` — this is how `run_simulations.sh` edits `config.yaml`
  between runs, without depending on a template per combination.
- **Python 3 + venv** — created automatically by `scripts/setup_venv.sh` (called by
  `scripts/main.sh`); used by `analyzer/` to generate each run's plots and by the
  aggregation scripts (`pandas`).
- **R (≥ 4.3)** with `ggplot2`, `dplyr`, `readr` — only for the final comparison plot
  (`plots_comparation.r`); `tidyr` is used by the analyzer's legacy pipeline
  (`create_plot_for_input.R`).
- **`sudo` without a blocking prompt** — the `make` targets that provision
  infrastructure run via `sudo`; `run_simulations.sh` asks for the password once at the
  start and keeps the session alive while the matrix runs.
- Any secrets/credentials a single run needs (e.g. `OPENROUTER_API_KEY` in
  `ai-engine/.env`) remain the responsibility of whoever configures that run — the
  matrix runner knows nothing about them, it just calls `make`.

## 3. Defining a run matrix

The starting point is always a single `make` command that already works on its own
(e.g. `make setup-and-start-auto`). Automating N runs of it means:

1. **Choosing the axes that vary.** In `run_simulations.sh`, the axes available today
   are declared at the top of the file:

   ```bash
   MODELS_DEFAULT=("openai/gpt-5" "google/gemini-2.5-pro" "anthropic/claude-sonnet-4.5")
   INPUTS_DEFAULT=("input_const.json" "input_varia.json")
   TEMPERATURES_DEFAULT=(0 0.1 0.5 1)
   GRAPH_VERSIONS_DEFAULT=("v1" "v2")
   ```

2. **Choosing the `make` target(s).** The script decides which `make <target>` to call
   via `--scenario` (today: `ai` → `setup-and-start-auto`, `baseline` →
   `setup-and-start-baseline`). A scenario with no configuration axis (like baseline)
   simply doesn't enter the `yq` loops — it's treated as a single combination.

3. **Choosing the output naming convention.** Each combination becomes an output
   directory named after the values used
   (`{model}_{input}_{graph}_{temperature}_{timestamp}` for the `ai` scenario,
   `baseline_{input}_{timestamp}` for `baseline`).

## 4. Running

### 4.1 Provision the infrastructure once

```bash
cd simulator   # root of this simulation repository
make setup
```

### 4.2 Run a matrix (or a subset of it)

Everything from the repository root (`simulator/`):

```bash
./run_simulations.sh                                     # all default axes, "ai" scenario
./run_simulations.sh const v1                             # filter to input=const, graph=v1
./run_simulations.sh --model openai/gpt-5 --repeat 5      # single model, 5 repetitions in a row
./run_simulations.sh --scenario baseline --repeat 5       # another scenario (no model/temperature axes)
./run_simulations.sh --scenario baseline --repeat 5 const # same, filtered to input=const
```

`--help` lists all options.
For each combination (or repetition), the script:

1. restores `config.yaml` from a backup taken at the start of the script's execution;
2. applies the current iteration's combination via `yq`;
3. syncs the chosen workload file to the name the broker actually reads
   (`input.json`);
4. runs `sudo make <target>` — each call already rebuilds the infrastructure from
   scratch, so repetitions end up just as clean as distinct combinations, with no
   manual cleanup step needed between them;
5. locates the freshly created output directory (the most recent one in
   `simulator/data/output/`), renames it to the combination's descriptive name, and
   copies the `config.yaml`/`input.json` actually used into it (`config_used.yaml`,
   `input_used.json`);
6. once everything is done, restores the original `config.yaml` and prints a summary
   (success/failure per combination, with each one's description).

A failure in one combination does **not** stop the others — the script keeps going and
reports each one's status in the final summary.

## 5. Output of each run

Every individual run (whether from the matrix or a direct `make` call) produces, under
`simulator/data/output/<name>/`:

```
metrics.json            # raw time series (cluster_info, workloads), collected at fixed intervals
logs/                    # logs from the components involved (broker, monitor, ai-engine, actuator, kubectl, ...)
plots/                   # PNGs generated automatically by the analyzer for THAT run
processed_data/processed_data.csv
summary/summary_metrics_<timestamp>.csv   # 1 row per metric × {mean, min, max, std, median}
```

More fields may appear depending on the scenario (e.g. `unschedulable_bindings.jsonl`
only exists in baseline runs, where there's no actuator to infer migrations from). The
metrics summarized in `summary_metrics_*.csv` are generated by
`analyzer/metrics_summarizer.py`; today they are `cost`, `cpu_usage`, `mem_usage`,
`pending_pods`, `time_with_pending`, `wokloads_with_pending_pods`,
`number_of_migrations`.

## 6. Aggregating multiple runs

After running one or more combinations, the runs sit loose under
`simulator/data/output/<name>/`. The two scripts below scan
`<root>/*/summary/summary_metrics_*.csv` and reconstruct each run's parameters from the
**directory name**, using a central regex in `aggregate_scenario_metrics.py`
(`extract_scenario`, shared by both scripts):

```bash
cd scripts
python3 aggregate_scenario_metrics.py \
  --root ../simulator/data/output/<folder_with_the_runs> \
  --output scenario_summary.csv

python3 list_scenario_runs.py \
  --root ../simulator/data/output/<folder_with_the_runs> \
  --output scenario_runs.csv
```

- `--root` should point to a folder whose direct children are the run directories
  (folders with one extra level of nesting are deliberately skipped, so as not to mix
  different campaigns).
- `--load const|varia` filters by load — this filter is specific to the current regex.
- `aggregate_scenario_metrics.py --selftest` validates directory-name parsing without
  needing real data.

**`aggregate_scenario_metrics.py`** → 1 row per `(parameter combination, metric)`, with
statistics **across repetitions** (`mean_across_runs` = mean of each run's mean,
`std_across_runs` = standard deviation of the per-run means, `n_runs` = how many
repetitions were found). This is the CSV meant for comparison plots across
combinations.

**`list_scenario_runs.py`** → no aggregation: stacks the rows of every
`summary_metrics_*.csv` found, one per `(parameters, run_dir, metric)`. Useful for
inspecting individual runs or spotting outliers before aggregating.

If your naming regex doesn't recognize a directory, both scripts warn on stderr
("unidentifiable scenario from ...") and simply skip that directory — they never abort
the whole run because of one directory that's out of pattern.

## 7. Plotting

`plots_comparation.r` is an example (not a generic script) of how to consume the
aggregated CSV: it reads a `scenario_summary_*.csv`, groups by parameter combination and
metric, and plots the mean with min/max bars, one color per chosen axis:

```bash
cd scripts
Rscript plots_comparation.r
```

Adjust the `read_csv(...)` at the top of the script to your aggregated CSV's name, and
the columns used in `aes(...)` to your campaign's axes. There is no single generic
script for every possible chart — treat this file as a starting point to copy/adapt per
campaign, not as a fixed command-line tool.

## 8. Reproducibility notes

- **Decision-maker non-determinism** — if the run involves an LLM or any other
  stochastic component, the same configuration can produce different results between
  runs; always run with repetitions (`--repeat`) and treat `std_across_runs`/`n_runs`
  as part of the result, not as noise to ignore.
- **Real-time jitter** — even deterministically decided scenarios show run-to-run
  variance because of the monitor's scrape granularity (30s by default) vs. the actual
  bind/reconciliation latency of the underlying infrastructure; compare distributions
  across repetitions, not values from a single run.
- Between consecutive runs that reuse the same infrastructure (outside the automatic
  flow of `run_simulations.sh`, which already reprovisions from scratch on every call),
  run `make clean-workloads` so you don't collide with workload names the broker
  recreates.
