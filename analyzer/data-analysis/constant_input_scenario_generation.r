# --- 1. SETUP & LIBRARIES ---
rm(list = ls()) 
if(!require(tidyverse)) install.packages("tidyverse")
library(tidyverse)

# --- 2. FILE PATHS ---
paths <- list(
  # --- V1 (Multi-Tool) ---
  "GPT-5_v1"         = "~/projetos/simulator/analyzer/output/openai-gpt-5_input_const_v1_0.1/processed_data/processed_data.csv",
  "DeepSeek-v3.2_v1" = "~/projetos/simulator/analyzer/output/deepseek-deepseek-v3.2_input_const_v1_0.1/20260211_022724/processed_data/processed_data.csv",
  "Gemini-2.5_v1"    = "~/projetos/simulator/analyzer/output/google-gemini-2.5-pro_input_const_v1_0.1/20251218_081553/processed_data/processed_data.csv",
  "Claude-4.5_v1"    = "~/projetos/simulator/analyzer/output/anthropic-claude-sonnet-4.5_input_const_v1_0.1/processed_data/processed_data.csv",
  
  # --- V2 (Multi-Agent) ---
  "GPT-5_v2"         = "~/projetos/simulator/analyzer/output/openai-gpt-5_input_const_v2_0.1/processed_data/processed_data.csv",
  "DeepSeek-v3.2_v2" = "~/projetos/simulator/analyzer/output/deepseek-deepseek-v3.2_input_const_v2_0.1/20260211_030733/processed_data/processed_data.csv",
  "Gemini-2.5_v2"    = "~/projetos/simulator/analyzer/output/google-gemini-2.5-pro_input_const_v2_0.1/processed_data/processed_data.csv",
  "Claude-4.5_v2"    = "~/projetos/simulator/analyzer/output/anthropic-claude-sonnet-4.5_input_const_v2_0.1/processed_data/processed_data.csv"
)

# --- 3. DATA LOADING & PREPARATION ---
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
        select(model_key, model_name, architecture, time_seconds, 
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
  filter(!(model_key == "DeepSeek-v3.2_v2" & time_seconds > 1800))

# --- 4. PODS DATA ---
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

# --- 5. ORDENAÇÃO DE FATORES ---
apply_factors <- function(df) {
  df$model_name <- factor(df$model_name, levels = c("GPT-5", "DeepSeek-v3.2", "Gemini-2.5", "Claude-4.5"))
  df$architecture <- factor(df$architecture, levels = c("Multi-Tool (v1)", "Multi-Agent (v2)"))
  return(df)
}

df_all <- apply_factors(df_all)
df_pods_long <- apply_factors(df_pods_long)

# --- 6. CALCULATE LIMITS ---
max_time <- max(df_all$time_seconds, na.rm = TRUE)
max_pods <- max(df_pods_long$pending_count, na.rm = TRUE)
max_cpu  <- max(c(df_all$cluster_cpu_capacity_public, df_all$cluster_cpu_capacity_private), na.rm = TRUE)

# --- 7. THEME---
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

# --- 8. PLOTS ---

# === PLOT 1: Pending Pods ===
p_pods <- ggplot(df_pods_long, aes(x = time_seconds, y = pending_count, color = pending_type)) +
  geom_step(linewidth = 0.8) +
  facet_grid(architecture ~ model_name, scales = "free") +
  expand_limits(x = max_time, y = max_pods) +
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

# === PLOT 2: CPU Allocation + 80% THRESHOLD ===
p_cpu <- ggplot(df_all, aes(x = time_seconds)) +
  
  # 1. Capacidade Total (100%) - Cinza tracejado
  geom_step(aes(y = cluster_cpu_capacity_private, color = "Private Capacity (100%)"), linetype = "dashed", linewidth = 0.5, alpha = 0.5) +
  geom_step(aes(y = cluster_cpu_capacity_public, color = "Public Capacity (100%)"), linetype = "dashed", linewidth = 0.5, alpha = 0.5) +
  
  # 2. LIMITE DO PROMPT (80%) - Pontilhado colorido
  geom_step(aes(y = cluster_cpu_capacity_private * 0.8, color = "Private Limit (80%)"), linetype = "dotted", linewidth = 0.7) +
  geom_step(aes(y = cluster_cpu_capacity_public * 0.8, color = "Public Limit (80%)"), linetype = "dotted", linewidth = 0.7) +
  
  # 3. Alocação Real - Linha solida
  geom_step(aes(y = cpu_allocated_private, color = "Private Allocated"), linewidth = 0.8) +
  geom_step(aes(y = cpu_allocated_public, color = "Public Allocated"), linewidth = 0.8) +
  
  facet_grid(architecture ~ model_name, scales = "free") +
  expand_limits(x = max_time, y = max_cpu) +
  
  scale_color_manual(
    values = c(
      "Private Allocated" = "#3498db",
      "Public Allocated"  = "#e74c3c",
      
      "Private Limit (80%)" = "#000080",
      "Public Limit (80%)"  = "#8B0000",
      
      "Private Capacity (100%)" = "#95a5a6",
      "Public Capacity (100%)"  = "#7f8c8d"
    ),
    name = "Metric:"
  ) +
  custom_theme +
  labs(
    title = "CPU Allocation vs 80% Threshold",
    subtitle = "Solid lines = Actual Usage. Dotted lines = 80% Prompt Limit. Dashed (Grey) = 100% Capacity.",
    y = "CPU (Cores/Millicores)",
    x = "Time (seconds)"
  )

# --- 9. SAVING OUTPUTS ---
ggsave("comparativo_v1_v2_pods_split_v2.png", p_pods, width = 18, height = 10)
ggsave("comparativo_v1_v2_cpu_threshold_v2.png", p_cpu, width = 18, height = 10)