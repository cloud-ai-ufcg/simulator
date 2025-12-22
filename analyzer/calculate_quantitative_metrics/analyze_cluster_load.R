#!/usr/bin/env Rscript
# Analyze cluster load metrics - count how many times they exceed 80%

library(dplyr)
library(readr)

# Resolve run path from CLI/env.
# Priority: explicit CSV (2nd arg) > RUN_DIR/first arg (as dir or dir fragment) > RUN_ID/first arg (as id) -> output/<id>/processed_data/processed_data.csv
args <- commandArgs(trailingOnly = TRUE)
run_id <- Sys.getenv("RUN_ID")
run_dir <- Sys.getenv("RUN_DIR")
explicit_csv <- NULL

# Helper: expand run_dir fragments like "/google-.../2025..." to output/<fragment>
expand_run_dir <- function(path_candidate) {
  if (dir.exists(path_candidate)) {
    return(path_candidate)
  }
  # If it starts with '/', strip and prepend output/
  frag <- sub("^/", "", path_candidate)
  candidate <- file.path("output", frag)
  if (dir.exists(candidate)) {
    return(candidate)
  }
  candidate_alt <- file.path("output", path_candidate)
  if (dir.exists(candidate_alt)) {
    return(candidate_alt)
  }
  return(path_candidate)
}

if (length(args) >= 1) {
  if (dir.exists(args[1])) {
    run_dir <- args[1]
  } else {
    run_id <- args[1]
  }
}
if (length(args) >= 2) {
  explicit_csv <- args[2]
}

if (!is.null(explicit_csv)) {
  csv_file <- explicit_csv
} else if (nzchar(run_dir)) {
  run_dir <- expand_run_dir(run_dir)
  csv_file <- file.path(run_dir, "processed_data", "processed_data.csv")
} else if (nzchar(run_id)) {
  csv_file <- file.path("output", run_id, "processed_data", "processed_data.csv")
} else {
  stop("Please provide RUN_DIR (env or first arg if it is a path), RUN_ID (env or first arg), or an explicit CSV path as second arg")
}

if (!file.exists(csv_file)) {
  stop(paste("CSV not found:", csv_file))
}

cat("Reading CSV file:", csv_file, "\n")
df <- read_csv(csv_file, show_col_types = FALSE)

# Columns to analyze
load_columns <- c(
  "cluster_mem_load_public",
  "cluster_cpu_load_public",
  "cluster_mem_load_private",
  "cluster_cpu_load_private"
)

# Count occurrences > 80 for each column
# Each measurement is taken every 30 seconds
interval_seconds <- 30

cat("\n=== Cluster Load Analysis (> 80%) ===\n\n")

results <- data.frame(
  Metric = character(),
  Count_Above_80 = integer(),
  Total_Measurements = integer(),
  Percentage = numeric(),
  Time_Above_80_Seconds = numeric(),
  Time_Above_80_Minutes = numeric(),
  Time_Above_80_Hours = numeric(),
  stringsAsFactors = FALSE
)

for (col in load_columns) {
  if (col %in% colnames(df)) {
    # Count values > 80
    count_above_80 <- sum(df[[col]] > 80, na.rm = TRUE)
    total <- sum(!is.na(df[[col]]))
    percentage <- (count_above_80 / total) * 100
    
    # Calculate time above 80% threshold
    time_seconds <- count_above_80 * interval_seconds
    time_minutes <- time_seconds / 60
    time_hours <- time_minutes / 60
    
    results <- rbind(results, data.frame(
      Metric = col,
      Count_Above_80 = count_above_80,
      Total_Measurements = total,
      Percentage = round(percentage, 2),
      Time_Above_80_Seconds = time_seconds,
      Time_Above_80_Minutes = round(time_minutes, 2),
      Time_Above_80_Hours = round(time_hours, 2)
    ))
    
    cat(sprintf("%-30s: %4d timestamps (%.2f%%) =  %.2f minutes\n",
                col, count_above_80, percentage, time_minutes))
  } else {
    cat("Column not found:", col, "\n")
  }
}

cat("\n=== Summary Table ===\n")
print(results, row.names = FALSE)

# Save results to CSV
output_file <- sub("\\.csv$", "_load_analysis.csv", csv_file)
write_csv(results, output_file)
cat("\n✅ Results saved to:", output_file, "\n")

# Pending pods analysis: total_percent_pending < 40%
pending_col <- "total_percent_pending"
pending_threshold <- 40

cat("\n=== Pending Pods Analysis (< 40%) ===\n\n")
if (pending_col %in% colnames(df)) {
  count_below_40 <- sum(df[[pending_col]] < pending_threshold, na.rm = TRUE)
  total_pending <- sum(!is.na(df[[pending_col]]))
  percentage_below <- (count_below_40 / total_pending) * 100

  time_seconds <- count_below_40 * interval_seconds
  time_minutes <- time_seconds / 60
  time_hours <- time_minutes / 60

  cat(sprintf(
    "%-25s: %4d timestamps (%.2f%%) = %.2f minutes\n",
    pending_col, count_below_40, percentage_below, time_minutes
  ))

  pending_results <- data.frame(
    Metric = pending_col,
    Count_Below_40 = count_below_40,
    Total_Measurements = total_pending,
    Percentage = round(percentage_below, 2),
    Time_Below_40_Seconds = time_seconds,
    Time_Below_40_Minutes = round(time_minutes, 2),
    Time_Below_40_Hours = round(time_hours, 2),
    stringsAsFactors = FALSE
  )

  pending_output_file <- sub("\\.csv$", "_pending_analysis.csv", csv_file)
  write_csv(pending_results, pending_output_file)
  cat("\n✅ Pending results saved to:", pending_output_file, "\n")
} else {
  cat("Column not found:", pending_col, "\n")
}