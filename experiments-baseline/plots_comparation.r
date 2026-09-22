library(dplyr)
library(ggplot2)
library(readr)

dff <- read_csv("scenario_summary_median.csv") %>% 
  mutate(modelo = ifelse(modelo == "karmada-nativo", "karmada", modelo),
         modelo = ifelse(modelo == "openai-gpt5", "gpt", modelo),
         modelo = ifelse(modelo == "google-gemini-2.5-pro", "gemini", modelo),
         modelo = ifelse(modelo == "anthropic-claude-sonnet-4.5", "claude", modelo))

ggplot(dff, aes(modelo, media_entre_execucoes, color=temperatura, group=temperatura)) + 
  geom_pointrange(stat="identity", position = position_dodge(width = 0.5), 
                  aes(ymin = min_entre_execucoes, 
                      ymax= max_entre_execucoes)) +
  facet_wrap(carga~metrica, scale="free_x", nrow=2) +
  theme_bw() + 
  theme(legend.position="top") + 
  coord_flip()