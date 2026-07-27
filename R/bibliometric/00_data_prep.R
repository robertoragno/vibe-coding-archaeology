
library(readxl)
library(dplyr)
library(tidyr)

SCOPUS_FILE   <- "data/input/taxonomy_v3/df_cleaned.xlsx"
TAXONOMY_FILE <- "data/input/taxonomy_v3/taxonomy_abstract_join.csv"
OUTPUT_RDS    <- "data/output/stan_data.rds"
VOCAB_RDS     <- "data/output/vocab.rds"

dir.create("data/output", recursive = TRUE, showWarnings = FALSE)

scopus_raw <- read_excel(SCOPUS_FILE) |>
  select(eid, Year = year)

taxonomy <- read.csv(TAXONOMY_FILE) |>
  select(eid, l2, l3)

scopus_processed <- scopus_raw |>
  inner_join(taxonomy, by = "eid") |>
  filter(Year >= 2010, Year <= 2025)  # 2026 dropped: partial year (mid-2026 + indexing lag)
cat("Rows loaded:", nrow(scopus_processed), "\n")

df_clean <- scopus_processed |>
  distinct(eid, Year, l2, l3)

cat("Rows after dedup:", nrow(df_clean), "\n")

l2_levels   <- sort(unique(df_clean$l2))
year_levels <- sort(unique(df_clean$Year))
N_groups    <- length(l2_levels)
N_years     <- length(year_levels)

cat("L2 groups:", N_groups, "\n")
cat("Years:    ", N_years, "(", min(year_levels), "-", max(year_levels), ")\n")

l3_vocab_all <- df_clean |>
  distinct(l2, l3) |>
  arrange(l2, l3) |>
  group_by(l2) |>
  mutate(k_local = row_number(), K_g = n()) |>
  ungroup()

# Drop L2 groups with only one L3 method (gamma unidentifiable: share always = 1)
singleton_groups <- l3_vocab_all |> filter(K_g == 1) |> pull(l2)
cat("Dropping", length(singleton_groups), "singleton L2 groups (K_g=1):\n")
cat(paste(" ", singleton_groups), sep = "\n")

df_clean <- df_clean |> filter(!l2 %in% singleton_groups)
l2_levels   <- sort(unique(df_clean$l2))
N_groups    <- length(l2_levels)
cat("L2 groups after filtering:", N_groups, "\n")

l3_vocab <- l3_vocab_all |>
  filter(!l2 %in% singleton_groups) |>
  group_by(l2) |>
  mutate(k_local = row_number(), K_g = n()) |>
  ungroup() |>
  mutate(g = match(l2, l2_levels))

K_g   <- l3_vocab |> group_by(g) |> summarise(K = first(K_g)) |> pull(K)
K_max <- max(K_g)

cat("K_max (largest L2 group):", K_max, "\n")
cat("Total L3 methods:        ", nrow(l3_vocab |> distinct(l3)), "\n")

df_indexed <- df_clean |>
  mutate(
    g = match(l2, l2_levels),
    t = match(Year, year_levels)
  ) |>
  left_join(
    l3_vocab |> select(l2, l3, k_local),
    by = c("l2", "l3")
  )

counts_long  <- df_indexed |> count(g, t, k_local, name = "n_papers")
counts_array <- array(0L, dim = c(N_groups, N_years, K_max))
for (i in seq_len(nrow(counts_long))) {
  counts_array[counts_long$g[i], counts_long$t[i], counts_long$k_local[i]] <-
    counts_long$n_papers[i]
}

year_std <- as.numeric(scale(year_levels))

# Two-slope temporal predictors, built from the observed year index so they
# stay aligned with the data even if a year is ever missing from the corpus:
#   year_std  = standardised linear trend
#   post_llm  = indicator for >= 2023 (post-ChatGPT academic adoption)
post_llm  <- as.integer(year_levels >= 2023)

cat("post_llm (1 = year >= 2023):", post_llm, "\n")

stan_data <- list(
  N_groups  = N_groups,
  N_years   = N_years,
  K_max     = K_max,
  K_g       = K_g,
  counts    = counts_array,
  year_std  = year_std,
  post_llm  = post_llm,
  years_vec = year_levels
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
