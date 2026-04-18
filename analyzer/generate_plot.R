library(ggplot2)
library(dplyr)
library(readr)
library(tidyr)

# Load processed data
df <- read_csv(file = "./analyzer_input/processed_data.csv", show_col_types = FALSE)

# Fix the 30-second offset in time_seconds
df <- df %>% mutate(time_seconds = time_seconds + 30)

# Add points at time 0 so the lines start from zero
df_start <- df %>% 
  filter(time_seconds == min(time_seconds)) %>%
  mutate(time_seconds = 0)

df <- bind_rows(df_start, df) %>%
  arrange(time_seconds)

# Prepare data for plotting - Public CPU
df_public <- df %>%
  select(time_seconds, cpu_allocated_public, cluster_cpu_capacity_public) %>%
  rename(
    `CPU Allocated` = cpu_allocated_public,
    `CPU Capacity` = cluster_cpu_capacity_public
  ) %>%
  pivot_longer(
    cols = c(`CPU Allocated`, `CPU Capacity`),
    names_to = "metric",
    values_to = "value"
  ) %>%
  mutate(panel = "CPU cores allocated over time - Member 2")

# Prepare data for plotting - Private CPU
df_private <- df %>%
  select(time_seconds, cpu_allocated_private, cluster_cpu_capacity_private) %>%
  rename(
    `CPU Allocated` = cpu_allocated_private,
    `CPU Capacity` = cluster_cpu_capacity_private
  ) %>%
  pivot_longer(
    cols = c(`CPU Allocated`, `CPU Capacity`),
    names_to = "metric",
    values_to = "value"
  ) %>%
  mutate(panel = "CPU cores allocated over time - Member 1")

# Combine public and private data
df_plot <- bind_rows(df_public, df_private)

# Extend lines to 200 seconds keeping the last value
df_extension <- df_plot %>%
  group_by(panel, metric) %>%
  filter(time_seconds == max(time_seconds)) %>%
  mutate(time_seconds = 200) %>%
  ungroup()

df_plot <- bind_rows(df_plot, df_extension) %>%
  arrange(panel, metric, time_seconds)

# Create plot with two panels (facets)
p <- ggplot(df_plot, aes(time_seconds, value, colour = metric)) + 
  geom_step(linewidth = 1.2, alpha = 0.6) + 
  geom_vline(xintercept = 70, linetype = "dashed", color = "gray30", linewidth = 0.8) +
  geom_vline(xintercept = 130, linetype = "dashed", color = "gray30", linewidth = 0.8) +
  facet_wrap(panel ~ ., nrow = 2, scales = "free_y") + 
  theme_bw(base_size = 16) +
  scale_color_manual(
    "Metric",
    values = c("CPU Allocated" = "#F8766D", "CPU Capacity" = "#00BFC4")
  ) +
  xlab("Time (seconds)") + 
  ylab("CPU (cores)") +
  expand_limits(y = 0) +
  scale_x_continuous(
    breaks = c(0, 30, 60, 70, 90, 120, 130, 150, 180),
    labels = c("0", "30", "60", "T1", "90", "120", "T2", "150", "180")
  ) +
  coord_cartesian(xlim = c(0, 200)) +
  theme(
    axis.text.x = element_text(size = 16),
    axis.text.y = element_text(size = 16),
    legend.position = "right",
    strip.background = element_rect(fill = "gray90"),
    strip.text = element_text(face = "bold")
  )

# Output directories already created by Python script

# Save the plot
output_plot_path <- "plots/cpu_allocation_plot.png"
dir.create(dirname(output_plot_path), recursive = TRUE, showWarnings = FALSE)

ggsave(output_plot_path, p, width = 12, height = 8, dpi = 300)

cat(sprintf("Plot generated successfully at: %s\n", output_plot_path))

# Show summary statistics
cat("\n=== Public CPU Statistics ===\n")
df %>% 
  summarize(
    max_allocated = max(cpu_allocated_public, na.rm = TRUE),
    mean_allocated = mean(cpu_allocated_public, na.rm = TRUE),
    capacity = first(cluster_cpu_capacity_public)
  ) %>%
  print()

cat("\n=== Private CPU Statistics ===\n")
df %>% 
  summarize(
    max_allocated = max(cpu_allocated_private, na.rm = TRUE),
    mean_allocated = mean(cpu_allocated_private, na.rm = TRUE),
    capacity = first(cluster_cpu_capacity_private)
  ) %>%
  print()
