library(ggplot2)
library(dplyr)
library(jsonlite)

# Function to create cumulative CPU requested plot
# Shows the cumulative CPU submission over time
create_workload_evolution_plot <- function(input_json_path, output_dir = NULL) {
  
  # Read input JSON
  input_data <- fromJSON(input_json_path)
  df <- as.data.frame(input_data$data)
  
  cat("✓ Input data loaded successfully\n")
  cat(sprintf("  Total workloads: %d\n", nrow(df)))
  cat(sprintf("  Time range: %d - %d seconds\n", min(df$timestamp), max(df$timestamp)))
  
  # Convert numeric columns
  df <- df %>%
    mutate(
      timestamp = as.numeric(timestamp),
      replicas = as.numeric(replicas),
      cpu = as.numeric(cpu),
      memory = as.numeric(memory)
    )
  
  # Calculate total resources per workload (replicas * resource)
  df <- df %>%
    mutate(
      total_cpu = replicas * cpu
    )
  
  # Sort by timestamp
  df <- df %>% arrange(timestamp)
  
  # Create cumulative sums
  df <- df %>%
    mutate(
      cumulative_cpu = cumsum(total_cpu)
    )
  
  # Create output directory if not specified
  if (is.null(output_dir)) {
    output_dir <- file.path(dirname(input_json_path), "..", "plots")
  }
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  cat("\nCreating cumulative CPU plot...\n")
  
  # Prepare data for step plot
  # Keep only actual submission events (not the 0 starting point for geom_point)
  df_cpu <- df %>%
    select(timestamp, cumulative_cpu)
  
  # For step plot: add starting point (0,0)
  df_cpu_step <- bind_rows(
    data.frame(timestamp = 0, cumulative_cpu = 0),
    df_cpu
  )
  
  # Create plot with step line only (no points), no facet title, with y-axis label
  p1 <- ggplot(df_cpu_step, aes(x = timestamp, y = cumulative_cpu)) + 
    geom_step(size = 1.2, color = "#d62728", alpha = 0.6) +
    theme_bw(base_size = 16) +
    theme(
      axis.text.x = element_text(size = 18),
      axis.text.y = element_text(size = 18)
    ) +
    xlab("Time (seconds)") + 
    ylab("CPU (cores)") +
    # Set custom x-axis breaks and labels with T0, T1, T2 and other timestamps
    scale_x_continuous(breaks = c(0, 35, 70, 100, 130, 165, 200),
                       labels = c("T0", "35", "T1", "100", "T2", "165", "200"))
  
  cpu_plot_path <- file.path(output_dir, "cumulative_cpu_requested.png")
  ggsave(cpu_plot_path, p1, width = 12, height = 5)
  cat(sprintf("  ✓ Saved: %s\n", cpu_plot_path))
  
  # ============================================================
  # Summary Statistics
  # ============================================================
  
  cat("\nSummary Statistics:\n")
  cat(sprintf("  Total workloads submitted: %d\n", nrow(df)))
  cat(sprintf("  Total CPU cores requested: %.1f\n", max(df$cumulative_cpu)))
  cat(sprintf("  Submission timestamps: %s\n", paste(unique(df$timestamp), collapse = ", ")))
  
  cat("\nCumulative CPU plot created successfully!\n")
  cat(sprintf("Plot saved to: %s\n", output_dir))
  
  return(list(
    cpu_plot = p1,
    plots_dir = output_dir,
    summary_data = df
  ))
}

# main execution

# Set the input JSON path
input_json <- "./analyzer_input/input.json"

cat("Starting cumulative CPU plot generation...\n")
cat(sprintf("Input file: %s\n", input_json))

# Check if file exists
if (!file.exists(input_json)) {
  stop(sprintf("Error: File not found: %s", input_json))
}

# Create the plots
tryCatch({
  result <- create_workload_evolution_plot(input_json)
  cat("\nDone!\n")
}, error = function(e) {
  cat(sprintf("\nError occurred: %s\n", e$message))
  stop(e)
})
