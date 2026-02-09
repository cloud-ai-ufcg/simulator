library(dplyr)
library(readr)

# --- 1. CONFIGURAÇÕES ---
FIXED_CAPACITY_PRIVATE <- 8000 
FIXED_CAPACITY_PUBLIC  <- 8000 

# Limite de Pods Pendentes (Violado se estourar 40%)
PENDING_THRESHOLD <- 40

# --- 2. SETUP DE ARQUIVO (Padrão) ---
args <- commandArgs(trailingOnly = TRUE)
run_id <- Sys.getenv("RUN_ID")
run_dir <- Sys.getenv("RUN_DIR")
explicit_csv <- NULL

expand_run_dir <- function(path_candidate) {
  if (dir.exists(path_candidate)) return(path_candidate)
  frag <- sub("^/", "", path_candidate)
  candidate <- file.path("output", frag)
  if (dir.exists(candidate)) return(candidate)
  candidate_alt <- file.path("output", path_candidate)
  if (dir.exists(candidate_alt)) return(candidate_alt)
  return(path_candidate)
}

if (length(args) >= 1) {
  if (dir.exists(args[1])) run_dir <- args[1] else run_id <- args[1]
}
if (length(args) >= 2) explicit_csv <- args[2]

if (!is.null(explicit_csv)) {
  csv_file <- explicit_csv
} else if (nzchar(run_dir)) {
  run_dir <- expand_run_dir(run_dir)
  csv_file <- file.path(run_dir, "processed_data", "processed_data.csv")
} else if (nzchar(run_id)) {
  csv_file <- file.path("output", run_id, "processed_data", "processed_data.csv")
} else {
  stop("Need RUN_DIR, RUN_ID, or explicit CSV path")
}

if (!file.exists(csv_file)) stop(paste("CSV not found:", csv_file))

cat("Reading CSV file:", csv_file, "\n")
df <- read_csv(csv_file, show_col_types = FALSE)

# DataFrame para acumular os resultados
final_results <- data.frame(
  Metric = character(),
  Count_Violations = integer(),
  Total_Samples = integer(),
  Percentage_Time_Violated = numeric(),
  Time_Violated_Minutes = numeric(),
  stringsAsFactors = FALSE
)

interval_seconds <- 30
total_measurements <- nrow(df)

# ANÁLISE 1: CPU LOAD NORMALIZADA (Load / Capacity * 100 > 80%)
cat("\n=== 1. Análise de CPU (Violação > 80% da Capacidade) ===\n")

get_capacity <- function(df, col_name, fixed_val) {
  if (col_name %in% colnames(df)) return(df[[col_name]])
  return(rep(fixed_val, nrow(df)))
}

col_load_priv <- "cluster_cpu_load_private"
col_load_pub  <- "cluster_cpu_load_public"

if (col_load_priv %in% colnames(df) && col_load_pub %in% colnames(df)) {
  cap_priv <- get_capacity(df, "cluster_cpu_capacity_private", FIXED_CAPACITY_PRIVATE)
  cap_pub  <- get_capacity(df, "cluster_cpu_capacity_public",  FIXED_CAPACITY_PUBLIC)
  
  # Calcula %
  pct_priv <- (df[[col_load_priv]] / cap_priv) * 100
  pct_pub  <- (df[[col_load_pub]]  / cap_pub)  * 100
  
  cpu_violation <- (pct_priv > 80 & !is.na(pct_priv)) | (pct_pub > 80 & !is.na(pct_pub))
  count_cpu <- sum(cpu_violation)
  time_cpu  <- count_cpu * interval_seconds
  
  final_results <- rbind(final_results, data.frame(
    Metric = "CPU_CAPACITY_VIOLATION (>80%)",
    Count_Violations = count_cpu,
    Total_Samples = total_measurements,
    Percentage_Time_Violated = round((count_cpu / total_measurements) * 100, 2),
    Time_Violated_Minutes = round(time_cpu / 60, 2)
  ))
  
  cat(sprintf("CPU Violated Timestamps: %d (%.2f min)\n", count_cpu, time_cpu/60))
} else {
  cat("Skipping CPU: Columns not found.\n")
}

# ANÁLISE 2: PENDING PODS (> 40%)
cat("\n=== 2. Análise de Pods Pendentes (Violação > 40%) ===\n")

col_pending <- "total_percent_pending"

if (col_pending %in% colnames(df)) {
  pending_vals <- df[[col_pending]]
  
  cat(sprintf("Min Pending: %.2f%% | Max Pending: %.2f%%\n", min(pending_vals, na.rm=T), max(pending_vals, na.rm=T)))
  
  # CONTA VIOLAÇÃO: Se for MAIOR que 40
  pending_violation <- (pending_vals > PENDING_THRESHOLD & !is.na(pending_vals))
  
  count_pending <- sum(pending_violation)
  time_pending  <- count_pending * interval_seconds
  
  final_results <- rbind(final_results, data.frame(
    Metric = "PENDING_PODS_VIOLATION (>40%)",
    Count_Violations = count_pending,
    Total_Samples = total_measurements,
    Percentage_Time_Violated = round((count_pending / total_measurements) * 100, 2),
    Time_Violated_Minutes = round(time_pending / 60, 2)
  ))
  
  cat(sprintf("Pending Pods Violated Timestamps: %d (%.2f min)\n", count_pending, time_pending/60))
  
} else {
  cat("Skipping Pending Pods: Column 'total_percent_pending' not found.\n")
}

cat("\n=== RESUMO GERAL DAS VIOLAÇÕES ===\n")
print(final_results, row.names = FALSE)
