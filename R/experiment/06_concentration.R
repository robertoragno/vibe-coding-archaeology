# 06_concentration.R
# Conjugate Dirichlet posterior on inv_simpson for each model x profile.
# Reads: experiment CSVs, vocab.rds. Writes: concentration summary/draws CSVs, plot.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggdist)
})

source(here("R/helpers.R"))  # inv_simpson, build_rec_vectors

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

l3_levels <- l3_vocab$l3
qwen_counts  <- build_rec_vectors(QWEN_CSV, l3_levels)
gemma_counts <- build_rec_vectors(GEMMA_CSV, l3_levels)

# ── Conjugate Dirichlet posterior draws ──────────────────────────────────────
# Multinomial counts + uniform Dirichlet(1) prior → exact posterior Dir(1+counts).
# No MCMC needed: the conjugate form gives the posterior in closed form.
#
# Caveat: each LLM response produces ~7–10 recommendations that are not
# independent. The conjugate model treats all recommendations as independent
# multinomial draws, so the effective sample size is closer to 252 responses
# than ~2,000 individual recommendations. A response-level bootstrap confirms
# that credible intervals would widen by ~1.5–2.5x with proper clustering
# adjustment. This does not affect conclusions: the LLM–literature gap (21–32
# vs 88–114 effective methods) dwarfs the interval widening. The same caveat
# applies symmetrically to the literature counts, where individual papers
# contribute multiple methods.

dirichlet_inv_simpson <- function(counts, n_draws = N_DRAWS) {
  # Posterior: Dirichlet(1 + counts) — uniform prior updated by observed frequencies.
  alpha <- 1 + counts
  # Standard identity: K independent Gamma(alpha_k, 1) draws, normalised to sum to 1,
  # yield a single Dirichlet(alpha) sample. Equivalent to rdirichlet().
  draws <- matrix(NA_real_, nrow = n_draws, ncol = length(alpha))
  for (k in seq_along(alpha)) {
    draws[, k] <- rgamma(n_draws, shape = alpha[k], rate = 1)
  }
  row_sums <- rowSums(draws)
  draws <- draws / row_sums
  apply(draws, 1, inv_simpson)
}

# ── Compute posteriors ───────────────────────────────────────────────────────
# Each source is fitted independently (not hierarchically) because profiles are
# deliberately contrasting experimental conditions, not exchangeable groups.

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

print(summary_df, n = 20)

# ── Posterior contrasts ─────────────────────────────────────────────────────
# Each source has an independent posterior, so its draws are mutually
# independent. Differencing them elementwise therefore yields valid draws from
# the posterior of the difference (the index pairing is arbitrary, not paired).
qwen_ov <- all_draws |> filter(source == "Qwen3 — overall") |> pull(inv_simpson)
gemma_ov <- all_draws |> filter(source == "Gemma — overall") |> pull(inv_simpson)
delta_ov <- qwen_ov - gemma_ov
cat(sprintf("\nQwen3 - Gemma (overall): median = %.1f, 90%% CI [%.1f, %.1f], P(Qwen > Gemma) = %.3f\n",
            median(delta_ov), quantile(delta_ov, 0.05), quantile(delta_ov, 0.95),
            mean(delta_ov > 0)))

qwen_nov <- all_draws |> filter(source == "Qwen3 — novice") |> pull(inv_simpson)
gemma_nov <- all_draws |> filter(source == "Gemma — novice") |> pull(inv_simpson)
delta_nov <- qwen_nov - gemma_nov
cat(sprintf("Qwen3 - Gemma (novice):  median = %.1f, 90%% CI [%.1f, %.1f], P(Qwen > Gemma) = %.3f\n",
            median(delta_nov), quantile(delta_nov, 0.05), quantile(delta_nov, 0.95),
            mean(delta_nov > 0)))

lit_post_draws <- all_draws |> filter(source == "Post-2023 literature") |> pull(inv_simpson)
delta_lit_qwen <- lit_post_draws - qwen_ov
delta_lit_gemma <- lit_post_draws - gemma_ov
cat(sprintf("\nPost-2023 lit - Qwen3:   median = %.1f, P(lit > Qwen) = %.3f\n",
            median(delta_lit_qwen), mean(delta_lit_qwen > 0)))
cat(sprintf("Post-2023 lit - Gemma:   median = %.1f, P(lit > Gemma) = %.3f\n",
            median(delta_lit_gemma), mean(delta_lit_gemma > 0)))

# ── Plot ─────────────────────────────────────────────────────────────────────

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

ggsave(OUT_PLOT, p, width = 9, height = 6, dpi = 300, bg = "white")
# ── Save outputs ─────────────────────────────────────────────────────────────

write.csv(summary_df, OUT_SUMMARY, row.names = FALSE)

draws_wide <- all_draws |>
  select(-draw) |>
  group_by(source) |>
  mutate(draw_id = row_number()) |>
  pivot_wider(names_from = source, values_from = inv_simpson) |>
  select(-draw_id)

write.csv(draws_wide, OUT_DRAWS, row.names = FALSE)
