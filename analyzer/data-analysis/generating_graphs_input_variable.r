# --- 1. SETUP & LIBRARIES ---
rm(list = ls()) 
if(!require(tidyverse)) install.packages("tidyverse")
library(tidyverse)

paths <- list(
  "GPT-5_v1"         = "~/projetos/simulator/analyzer/output/openai-gpt-5_input_varia_v1_0.1/processed_data/processed_data.csv",
  "DeepSeek-v3.2_v1" = "~/projetos/simulator/analyzer/output/deepseek-deepseek-v3.2_input_varia_v1_0.1/20260211_034721/processed_data/processed_data.csv",
  "Gemini-2.5_v1"    = "~/projetos/simulator/analyzer/output/google-gemini-2.5-pro_input_varia_v1_0.1/processed_data/processed_data.csv",
  "Claude-4.5_v1"    = "~/projetos/simulator/analyzer/output/anthropic-claude-sonnet-4.5_input_varia_v1_0.1/processed_data/processed_data.csv",
  
  "GPT-5_v2"         = "~/projetos/simulator/analyzer/output/openai-gpt-5_input_varia_v2_0.1/processed_data/processed_data.csv",
  "DeepSeek-v3.2_v2" = "~/projetos/simulator/analyzer/output/deepseek-deepseek-v3.2_input_varia_v2_0.1/20260211_042702/processed_data/processed_data.csv",
  "Gemini-2.5_v2"    = "~/projetos/simulator/analyzer/output/google-gemini-2.5-pro_input_varia_v2_0.1/processed_data/processed_data.csv",
  "Claude-4.5_v2"    = "~/projetos/simulator/analyzer/output/anthropic-claude-sonnet-4.5_input_varia_v2_0.1/processed_data/processed_data.csv"
)

df_list <- list()

for(key in names(paths)) {
  fpath <- paths[[key]]
  
  if(file.exists(fpath)) {
    tryCatch({
      parts <- str_split(key, "_", simplify = TRUE)
      model_real <- parts[1]
      version    <- parts[2]
      
      arch_label <- ifelse(version == "v1", "Multi-Tool (v1)", "Multi-Agent (v2)")
      
      df_temp <- read_csv(fpath, show_col_types = FALSE) %>%
        mutate(
          model_key = key,
          model_name = model_real,
          architecture = arch_label
        ) %>%
        select(model_name, architecture, time_seconds,
               number_pending_public_x, number_pending_private_x,
               cpu_allocated_public, cpu_allocated_private,
               cluster_cpu_capacity_public, cluster_cpu_capacity_private)
      
      df_list[[key]] <- df_temp
    }, error = function(e) {
      warning(paste("Error reading:", key))
    })
  } else {
    warning(paste("File not found:", fpath))
  }
}

df_all <- bind_rows(df_list)

if(nrow(df_all) == 0) stop("No data loaded.")

df_all <- df_all %>%
  filter(time_seconds <= 1800)

df_pods_long <- df_all %>%
  pivot_longer(
    cols = c(number_pending_public_x, number_pending_private_x),
    names_to = "pending_type",
    values_to = "pending_count"
  ) %>%
  mutate(
    pending_type = recode(pending_type, 
                          "number_pending_private_x" = "Private Pending",
                          "number_pending_public_x"  = "Public Pending")
  )

apply_factors <- function(df) {
  df$architecture <- factor(df$architecture, levels = c("Multi-Tool (v1)", "Multi-Agent (v2)"))
  df$model_name <- factor(df$model_name, levels = c("GPT-5", "DeepSeek-v3.2", "Gemini-2.5", "Claude-4.5"))
  return(df)
}

df_all <- apply_factors(df_all)
df_pods_long <- apply_factors(df_pods_long)

max_time_limit <- 1800 
max_pods <- max(df_pods_long$pending_count, na.rm = TRUE)
max_cpu  <- max(c(df_all$cluster_cpu_capacity_public, df_all$cluster_cpu_capacity_private), na.rm = TRUE)

custom_theme <- theme_light(base_size = 20) +
  theme(
    legend.position = "bottom",
    strip.text = element_text(face = "bold", size = rel(1.0), color = "white"),
    strip.background = element_rect(fill = "#2c3e50"),
    panel.grid.minor = element_blank(),
    
    plot.title = element_text(face = "bold", hjust = 0.5, size = rel(1.2)),
    plot.subtitle = element_text(hjust = 0.5, color = "gray40", size = rel(0.9)),
    axis.text = element_text(color = "black"),
    legend.text = element_text(size = rel(0.9)),
    legend.title = element_text(face = "bold", size = rel(1.0))
  )


p_pods <- ggplot(df_pods_long, aes(x = time_seconds, y = pending_count, color = pending_type)) +
  geom_step(linewidth = 0.8) +
  facet_grid(architecture ~ model_name, scales = "free") +
  coord_cartesian(xlim = c(0, max_time_limit)) +
  scale_color_manual(
    values = c("Private Pending" = "#3498db", "Public Pending" = "#e74c3c"),
    name = "Cluster:"
  ) +
  custom_theme +
  labs(
    title = "Pending Pods Breakdown",
    subtitle = "Public vs Private Queue by Model and Architecture",
    y = "Count of Pending Pods",
    x = "Time (seconds)"
  )

p_cpu <- ggplot(df_all, aes(x = time_seconds)) +
  
  geom_step(aes(y = cluster_cpu_capacity_private, color = "Private Capacity (100%)"), linetype = "solid", linewidth = 0.8, alpha = 0.8) +
  geom_step(aes(y = cluster_cpu_capacity_public, color = "Public Capacity (100%)"), linetype = "solid", linewidth = 0.8, alpha = 0.8) +
  
  geom_step(aes(y = cpu_allocated_private, color = "Private Allocated"), linewidth = 0.8) +
  geom_step(aes(y = cpu_allocated_public, color = "Public Allocated"), linewidth = 0.8) +
  
  facet_grid(architecture ~ model_name, scales = "free") +
  coord_cartesian(xlim = c(0, max_time_limit)) +
  expand_limits(y = max_cpu) +
  
  scale_color_manual(
    values = c(
      "Private Allocated"       = "#3498db",
      "Private Limit (80%)"     = "#000033",
      "Private Capacity (100%)" = "#008000",
      
      "Public Allocated"        = "#e74c3c",
      "Public Limit (80%)"      = "#330000",
      "Public Capacity (100%)"  = "#800080"
    ),
    name = "Metric:",
    breaks = c(
      "Private Allocated", "Public Allocated",
      "Private Capacity (100%)", "Public Capacity (100%)"
    )
  ) +
  custom_theme +
  labs(
    title = "CPU Allocation vs 80% Threshold",
    subtitle = "Solid = Actual Usage | Long Dash = 80% Rule | Pale Solid = 100% Capacity (Separate per Cluster)",
    y = "CPU (Cores/Millicores)",
    x = "Time (seconds)"
  )

# --- 9. SAVING OUTPUTS ---
ggsave("~/comparativo_v1_v2_pods_split_varia_separated.png", p_pods, width = 18, height = 10)
ggsave("~/comparativo_v1_v2_cpu_threshold_varia_separated.png", p_cpu, width = 18, height = 10)
