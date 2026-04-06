rm(list = ls())
if(!require(tidyverse)) install.packages("tidyverse")
if(!require(scales)) install.packages("scales")
library(tidyverse)
library(scales)

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
      df_temp <- read_csv(fpath, show_col_types = FALSE) %>%
        mutate(model_key = key, model_name = parts[1], architecture = ifelse(parts[2] == "v1", "Multi-Tool (v1)", "Multi-Agent (v2)")) %>%
        select(model_key, model_name, architecture, time_seconds, 
               cpu_allocated_public, cpu_allocated_private,
               cluster_cpu_capacity_public, cluster_cpu_capacity_private)
      df_list[[key]] <- df_temp
    }, error = function(e) warning(paste("Erro:", key)))
  }
}

df_all <- bind_rows(df_list)

df_all <- df_all %>% filter(!(model_key == "DeepSeek-v3.2_v2" & time_seconds > 1800))

stats_df <- df_all %>%
  mutate(
    total_capacity = cluster_cpu_capacity_public + cluster_cpu_capacity_private,

    total_used = cpu_allocated_public + cpu_allocated_private,

    saturation_pct = (total_used / total_capacity) * 100
  ) %>%
  group_by(model_name, architecture) %>%
  summarise(
    avg_efficiency_pct = mean(saturation_pct, na.rm = TRUE),

    avg_waste_pct = 100 - mean(saturation_pct, na.rm = TRUE),

    peak_load_pct = max(saturation_pct, na.rm = TRUE),

    load_volatility_sd = sd(saturation_pct, na.rm = TRUE),
    
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), \(x) round(x, 2)))

print(stats_df)
write_csv(stats_df, "variable_efficiency_table.csv")