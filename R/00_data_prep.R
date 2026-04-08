cat("=== 00_data_prep.R ===\n")

library(readxl)
library(dplyr)
library(tidyr)

INPUT_FILE <- "data/input/qwen_dataset.xlsx"
OUTPUT_RDS <- "data/output/stan_data.rds"
VOCAB_RDS  <- "data/output/vocab.rds"

dir.create("data/output", recursive = TRUE, showWarnings = FALSE)

cat("Loading data...\n")
scopus_processed <- read_excel(INPUT_FILE) |>
  filter(Year >= 2010, Year <= 2025)
cat("Rows loaded:", nrow(scopus_processed), "\n")

df_clean <- scopus_processed |>
  distinct(abstract_id, Year, level_2_mid, level_3_fine)

cat("Rows after dedup:", nrow(df_clean), "\n")

l2_levels   <- sort(unique(df_clean$level_2_mid))
year_levels <- sort(unique(df_clean$Year))
N_groups    <- length(l2_levels)
N_years     <- length(year_levels)

cat("L2 groups:", N_groups, "\n")
cat("Years:    ", N_years, "(", min(year_levels), "-", max(year_levels), ")\n")

l3_vocab <- df_clean |>
  distinct(level_2_mid, level_3_fine) |>
  arrange(level_2_mid, level_3_fine) |>
  group_by(level_2_mid) |>
  mutate(k_local = row_number(), K_g = n()) |>
  ungroup() |>
  mutate(g = match(level_2_mid, l2_levels))

K_g   <- l3_vocab |> group_by(g) |> summarise(K = first(K_g)) |> pull(K)
K_max <- max(K_g)

cat("K_max (largest L2 group):", K_max, "\n")
cat("Total L3 methods:        ", nrow(l3_vocab |> distinct(level_3_fine)), "\n")

df_indexed <- df_clean |>
  mutate(
    g = match(level_2_mid, l2_levels),
    t = match(Year, year_levels)
  ) |>
  left_join(
    l3_vocab |> select(level_2_mid, level_3_fine, k_local),
    by = c("level_2_mid", "level_3_fine")
  )

counts_long  <- df_indexed |> count(g, t, k_local, name = "n_papers")
counts_array <- array(0L, dim = c(N_groups, N_years, K_max))
for (i in seq_len(nrow(counts_long))) {
  counts_array[counts_long$g[i], counts_long$t[i], counts_long$k_local[i]] <-
    counts_long$n_papers[i]
}

years_vec <- 2010:2025
year_std  <- as.numeric(scale(year_levels))

# Two-slope temporal predictors:
#   year_std  = standardised linear trend (full 2010-2025)
#   post_llm  = indicator for >= 2023 (post-ChatGPT academic adoption)
post_llm <- as.integer(years_vec >= 2023)

cat("post_llm vector (2010-2025):", post_llm, "\n")

stan_data <- list(
  N_groups  = N_groups,
  N_years   = N_years,
  K_max     = K_max,
  K_g       = K_g,
  counts    = counts_array,
  phi     = 10.0,
  year_std  = year_std,
  post_llm  = post_llm,
  years_vec = years_vec
)

vocab <- list(
  l2_levels   = l2_levels,
  year_levels = year_levels,
  l3_vocab    = l3_vocab,
  K_g         = K_g
)

saveRDS(stan_data, OUTPUT_RDS)
saveRDS(vocab,     VOCAB_RDS)

cat("Saved stan_data to:", OUTPUT_RDS, "\n")
cat("Saved vocab to:    ", VOCAB_RDS,  "\n")
cat("=== 00_data_prep.R DONE ===\n")
