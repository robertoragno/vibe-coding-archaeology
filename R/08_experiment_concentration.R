# 08_experiment_concentration.R
# Conjugate Dirichlet posterior on inv_simpson for each model x profile.
# Reads: experiment CSVs, vocab.rds. Writes: concentration summary/draws CSVs, plot.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggdist)
})

set.seed(42)
N_DRAWS <- 4000

# ── Paths ────────────────────────────────────────────────────────────────────

QWEN_CSV  <- here("experiment/analysis/experiment_results_QWEN.csv")
GEMMA_CSV <- here("experiment/analysis/experiment_results_GEMMA.csv")
VOCAB_RDS <- here("data/output/vocab.rds")
STAN_DATA <- here("data/output/stan_data.rds")

OUT_DIR <- here("data/output/figures/concentration")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

OUT_DRAWS   <- here("data/output/concentration_inv_simpson_draws.csv")
OUT_SUMMARY <- here("data/output/concentration_inv_simpson_summary.csv")
OUT_PLOT    <- file.path(OUT_DIR, "plot_concentration_posteriors.png")

# ── Load vocab and literature counts ─────────────────────────────────────────

vocab     <- readRDS(VOCAB_RDS)
stan_data <- readRDS(STAN_DATA)
l3_vocab  <- vocab$l3_vocab |> arrange(g, k_local)

K <- nrow(l3_vocab)
cat("L3 methods in vocabulary:", K, "\n")

# Pre-2023 and post-2023 literature count vectors (summed across L2 groups)
year_levels <- vocab$year_levels
pre_idx  <- which(year_levels < 2023)
post_idx <- which(year_levels >= 2023)

lit_pre  <- numeric(K)
lit_post <- numeric(K)
row_idx  <- 0
for (g in seq_len(stan_data$N_groups)) {
  for (k in seq_len(stan_data$K_g[g])) {
    row_idx <- row_idx + 1
    lit_pre[row_idx]  <- sum(stan_data$counts[g, pre_idx, k])
    lit_post[row_idx] <- sum(stan_data$counts[g, post_idx, k])
  }
}

# ── Build count vectors for each model x profile ────────────────────────────

build_count_vector <- function(csv_path, l3_levels) {
  exp_raw <- read.csv(csv_path, stringsAsFactors = FALSE)
  exp_con <- exp_raw |> filter(toupper(as.character(l3_mapping_consistent)) == "TRUE")

  profiles <- c("novice", "intermediate", "expert")
  result   <- list()

  for (prof in profiles) {
    counts_df <- exp_con |>
      filter(profile == prof) |>
      count(l3 = l3_mapping, name = "n")
    vec <- setNames(rep(0L, length(l3_levels)), l3_levels)
    matched <- counts_df$l3[counts_df$l3 %in% l3_levels]
    vec[matched] <- counts_df$n[match(matched, counts_df$l3)]
    result[[prof]] <- vec
  }

  # overall = sum of profiles
  result[["overall"]] <- result[["novice"]] + result[["intermediate"]] + result[["expert"]]
  result
}

l3_levels <- l3_vocab$l3
qwen_counts  <- build_count_vector(QWEN_CSV, l3_levels)
gemma_counts <- build_count_vector(GEMMA_CSV, l3_levels)

# ── Conjugate Dirichlet posterior draws ──────────────────────────────────────
# MCMCpack::rdirichlet or manual gamma-based sampling

inv_simpson <- function(p) 1 / sum(p^2)

dirichlet_inv_simpson <- function(counts, n_draws = N_DRAWS) {
  # Dirichlet(alpha) where alpha = 1 + counts (conjugate posterior)
  alpha <- 1 + counts
  # Sample via gamma distribution: p_k = g_k / sum(g)
  draws <- matrix(NA_real_, nrow = n_draws, ncol = length(alpha))
  for (k in seq_along(alpha)) {
    draws[, k] <- rgamma(n_draws, shape = alpha[k], rate = 1)
  }
  # normalise each row to get Dirichlet draws
  row_sums <- rowSums(draws)
  draws <- draws / row_sums
  # inverse Simpson for each draw
  apply(draws, 1, inv_simpson)
}

# ── Compute posteriors ───────────────────────────────────────────────────────

cat("\nDrawing from Dirichlet posteriors...\n")

sources <- list(
  "Pre-2023 literature"  = lit_pre,
  "Post-2023 literature" = lit_post,
  "Qwen3 — overall"      = qwen_counts$overall,
  "Qwen3 — novice"       = qwen_counts$novice,
  "Qwen3 — intermediate" = qwen_counts$intermediate,
  "Qwen3 — expert"       = qwen_counts$expert,
  "Gemma — overall"      = gemma_counts$overall,
  "Gemma — novice"       = gemma_counts$novice,
  "Gemma — intermediate" = gemma_counts$intermediate,
  "Gemma — expert"       = gemma_counts$expert
)

draws_list <- lapply(names(sources), function(nm) {
  d <- dirichlet_inv_simpson(sources[[nm]])
  cat(sprintf("  %-25s  median = %5.1f  90%% CI [%5.1f, %5.1f]\n",
              nm, median(d), quantile(d, 0.05), quantile(d, 0.95)))
  data.frame(source = nm, draw = seq_along(d), inv_simpson = d)
})

all_draws <- bind_rows(draws_list)

# ── Summary table ────────────────────────────────────────────────────────────

summary_df <- all_draws |>
  group_by(source) |>
  summarise(
    median  = median(inv_simpson),
    lo90    = quantile(inv_simpson, 0.05),
    hi90    = quantile(inv_simpson, 0.95),
    lo95    = quantile(inv_simpson, 0.025),
    hi95    = quantile(inv_simpson, 0.975),
    .groups = "drop"
  )

cat("\n=== Concentration summary ===\n")
print(summary_df, n = 20)

# ── Posterior contrast: Qwen vs Gemma (overall) ─────────────────────────────
# Same draw index → paired comparison
qwen_ov <- all_draws |> filter(source == "Qwen3 — overall") |> pull(inv_simpson)
gemma_ov <- all_draws |> filter(source == "Gemma — overall") |> pull(inv_simpson)
delta_ov <- qwen_ov - gemma_ov
cat(sprintf("\nQwen3 - Gemma (overall): median = %.1f, 90%% CI [%.1f, %.1f], P(Qwen > Gemma) = %.3f\n",
            median(delta_ov), quantile(delta_ov, 0.05), quantile(delta_ov, 0.95),
            mean(delta_ov > 0)))

# Novice contrast
qwen_nov <- all_draws |> filter(source == "Qwen3 — novice") |> pull(inv_simpson)
gemma_nov <- all_draws |> filter(source == "Gemma — novice") |> pull(inv_simpson)
delta_nov <- qwen_nov - gemma_nov
cat(sprintf("Qwen3 - Gemma (novice):  median = %.1f, 90%% CI [%.1f, %.1f], P(Qwen > Gemma) = %.3f\n",
            median(delta_nov), quantile(delta_nov, 0.05), quantile(delta_nov, 0.95),
            mean(delta_nov > 0)))

# LLM vs literature contrasts
lit_post_draws <- all_draws |> filter(source == "Post-2023 literature") |> pull(inv_simpson)
delta_lit_qwen <- lit_post_draws - qwen_ov
delta_lit_gemma <- lit_post_draws - gemma_ov
cat(sprintf("\nPost-2023 lit - Qwen3:   median = %.1f, P(lit > Qwen) = %.3f\n",
            median(delta_lit_qwen), mean(delta_lit_qwen > 0)))
cat(sprintf("Post-2023 lit - Gemma:   median = %.1f, P(lit > Gemma) = %.3f\n",
            median(delta_lit_gemma), mean(delta_lit_gemma > 0)))

# ── Plot ─────────────────────────────────────────────────────────────────────

# Order from most to least concentrated
source_order <- summary_df |> arrange(median) |> pull(source)
all_draws$source <- factor(all_draws$source, levels = source_order)

p <- ggplot(all_draws, aes(x = inv_simpson, y = source)) +
  stat_halfeye(
    .width         = c(0.90, 0.95),
    point_interval = "median_qi",
    fill           = "#0072B2",
    colour         = "#004466",
    alpha          = 0.6
  ) +
  labs(
    x     = "Effective number of methods (Inverse Simpson)",
    y     = NULL,
    title = "Recommendation concentration: posterior distributions",
    subtitle = "Dirichlet conjugate posterior. Higher = more diverse. Literature vs. two LLMs across profiles."
  ) +
  theme_minimal(base_size = 11) +
  theme(axis.text.y = element_text(size = 9))

ggsave(OUT_PLOT, p, width = 9, height = 6, dpi = 200, bg = "white")
cat("\nPlot saved:", OUT_PLOT, "\n")

# ── Save outputs ─────────────────────────────────────────────────────────────

write.csv(summary_df, OUT_SUMMARY, row.names = FALSE)
cat("Summary saved:", OUT_SUMMARY, "\n")

# Save draws in wide format for downstream use
draws_wide <- all_draws |>
  select(-draw) |>
  group_by(source) |>
  mutate(draw_id = row_number()) |>
  pivot_wider(names_from = source, values_from = inv_simpson) |>
  select(-draw_id)

write.csv(draws_wide, OUT_DRAWS, row.names = FALSE)
cat("Draws saved:", OUT_DRAWS, "\n")

cat("\n08_experiment_concentration.R complete.\n")
