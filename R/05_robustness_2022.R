# 05_robustness_2022.R
# Robustness check: re-run primary analysis with post_llm break at 2022
# (ChatGPT public release) instead of 2023 (widespread academic adoption).
# Stable gamma estimates across both break-points strengthen temporal inference.
#
# NOTE: gamma_results.csv (2023 break) is read from data/output/phi_free/.
# gamma_results_2022.csv is saved to data/output/gamma_results_2022.csv.

suppressPackageStartupMessages({
  library(here)
  library(cmdstanr)
  library(dplyr)
  library(ggplot2)
  library(ggrepel)
})

options(mc.cores = parallel::detectCores())

# ── 1. Paths ───────────────────────────────────────────────────────────────────

STAN_FILE   <- here("stan/diversity_model_phi_free.stan")
SD_PATH     <- here("data/output/stan_data.rds")
VOCAB_PATH  <- here("data/output/vocab.rds")
FIT_2022    <- here("data/output/fit_phi_free_2022.rds")
DONE_FLAG   <- here("data/output/fit_phi_free_2022.done")
OUT_CSV     <- here("data/output/gamma_results_2022.csv")
OUT_PLOT    <- here("data/output/figures/robustness/plot_robustness_2022.png")

GAMMA_2023_CSV <- here("data/output/phi_free/gamma_results.csv")

dir.create(here("data/output/figures/robustness"), recursive = TRUE, showWarnings = FALSE)

if (!file.exists(GAMMA_2023_CSV))
  stop("gamma_results.csv (2023 break) not found at:\n  ", GAMMA_2023_CSV)

# ── 2. Load stan_data and modify post_llm ──────────────────────────────────────

cat("Loading stan_data...\n")
stan_data <- readRDS(SD_PATH)

years_vec <- stan_data$years_vec
cat("years_vec:", years_vec, "\n")
cat("Original post_llm:", stan_data$post_llm, "\n")

# Set post_llm = 1 from 2022 onwards (index where year >= 2022)
stan_data_2022 <- stan_data
stan_data_2022$post_llm <- as.integer(years_vec >= 2022)
cat("Modified post_llm:", stan_data_2022$post_llm, "\n")

# Sanity check: years 2022-2026 should be post_llm = 1 (5 years)
stopifnot(sum(stan_data_2022$post_llm) == 5L)
cat("post_llm sum = 5 (2022, 2023, 2024, 2025, 2026) — OK\n")

# ── 3. Re-fit (guarded by DONE_FLAG) ──────────────────────────────────────────

# phi is estimated (not data) in phi_free model; remove if present
stan_data_2022$phi <- NULL

if (!file.exists(DONE_FLAG)) {
  cat("\nCompiling and sampling (break=2022)...\n")
  cat("Settings: chains=4, iter_sampling=2000, iter_warmup=2000, adapt_delta=0.95, max_treedepth=14\n")
  t_start <- proc.time()

  mod <- cmdstan_model(STAN_FILE)
  fit_2022 <- mod$sample(
    data            = stan_data_2022,
    chains          = 4,
    iter_sampling   = 2000,
    iter_warmup     = 2000,
    parallel_chains = 4,
    seed            = 42,
    adapt_delta     = 0.95,
    max_treedepth   = 14,
    refresh         = 200
  )

  elapsed_min <- round((proc.time() - t_start)["elapsed"] / 60, 1)
  cat("Sampling done. Elapsed:", elapsed_min, "minutes\n")

  fit_2022$save_object(FIT_2022)
  writeLines(as.character(Sys.time()), DONE_FLAG)
  cat("Fit saved to:", FIT_2022, "\n")
} else {
  cat("Fit already complete; loading from", FIT_2022, "\n")
  fit_2022 <- readRDS(FIT_2022)
}

# ── 4. HMC diagnostics ─────────────────────────────────────────────────────────

cat("\n--- HMC diagnostics (2022 break) ---\n")
diag <- fit_2022$diagnostic_summary()
cat("Divergences:", sum(diag$num_divergent), "\n")
cat("Max treedepth:", sum(diag$num_max_treedepth), "\n")
cat("\n--- sigma_beta ---\n"); print(fit_2022$summary(variables = "sigma_beta"))
cat("\n--- sigma_gamma ---\n"); print(fit_2022$summary(variables = "sigma_gamma"))
cat("\n--- phi ---\n");         print(fit_2022$summary(variables = "phi"))

# ── 5. Extract gamma_method posteriors ─────────────────────────────────────────

cat("\nExtracting gamma_method draws...\n")
vocab     <- readRDS(VOCAB_PATH)
l2_levels <- vocab$l2_levels
K_g_vec   <- vocab$K_g
N_groups  <- length(l2_levels)

draws <- fit_2022$draws(format = "draws_matrix")
S     <- nrow(draws)
cat("Draws S =", S, ", N_groups =", N_groups, "\n")

gamma_list <- vector("list", N_groups)
for (grp in seq_len(N_groups)) {
  K    <- K_g_vec[grp]
  gm_g <- matrix(NA_real_, nrow = S, ncol = K)
  for (k in seq_len(K)) {
    gm_g[, k] <- draws[, sprintf("gamma_method[%d,%d]", grp, k)]
  }

  method_labels <- vocab$l3_vocab |>
    filter(g == grp) |>
    arrange(k_local) |>
    pull(l3)

  gamma_list[[grp]] <- data.frame(
    g            = grp,
    l2  = l2_levels[grp],
    k            = seq_len(K),
    l3 = method_labels,
    mean_gamma   = colMeans(gm_g),
    sd_gamma     = apply(gm_g, 2, sd),
    lo90         = apply(gm_g, 2, quantile, 0.05),
    hi90         = apply(gm_g, 2, quantile, 0.95),
    lo95         = apply(gm_g, 2, quantile, 0.025),
    hi95         = apply(gm_g, 2, quantile, 0.975),
    stringsAsFactors = FALSE
  )
}

gamma_2022 <- bind_rows(gamma_list) |>
  mutate(
    sig90       = (lo90 > 0 | hi90 < 0),
    sig95       = (lo95 > 0 | hi95 < 0),
    group_label = sub("^L2-\\d+: ", "", l2),
    method_id   = paste0(group_label, ": ", l3)
  )

cat("Methods with 90% CI excluding zero (2022 break):",
    sum(gamma_2022$sig90, na.rm = TRUE), "\n")

# ── 6. Save gamma_results_2022.csv ─────────────────────────────────────────────

write.csv(gamma_2022, OUT_CSV, row.names = FALSE)
cat("Saved:", OUT_CSV, "\n")

# ── 7. Comparison plot ─────────────────────────────────────────────────────────

cat("\nBuilding comparison plot...\n")
gamma_2023 <- read.csv(GAMMA_2023_CSV, stringsAsFactors = FALSE)

# Join on l3; check uniqueness first
stopifnot(!anyDuplicated(gamma_2022$l3))
stopifnot(!anyDuplicated(gamma_2023$l3))

comp <- inner_join(
  gamma_2023 |> select(l3, mean_gamma, sig90),
  gamma_2022 |> select(l3, mean_gamma, sig90),
  by     = "l3",
  suffix = c("_2023", "_2022")
)

cat("Methods matched:", nrow(comp), "\n")

# Significance status: sig90 in either model
comp <- comp |>
  mutate(
    sig_status = case_when(
      sig90_2023 & sig90_2022 ~ "Both significant",
      sig90_2023              ~ "2023-break only",
      sig90_2022              ~ "2022-break only",
      TRUE                    ~ "Neither"
    ),
    sig_status = factor(sig_status,
                        levels = c("Both significant", "2023-break only",
                                   "2022-break only", "Neither")),
    divergence = abs(mean_gamma_2023 - mean_gamma_2022)
  )

# Label the 10 most divergent methods
top_labels <- comp |>
  arrange(desc(divergence)) |>
  slice_head(n = 10)

p <- ggplot(comp, aes(x = mean_gamma_2023, y = mean_gamma_2022, colour = sig_status)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey40", linewidth = 0.5) +
  geom_point(alpha = 0.7, size = 1.5) +
  geom_text_repel(
    data         = top_labels,
    aes(label    = l3),
    size         = 2.2,
    max.overlaps = 20,
    show.legend  = FALSE
  ) +
  scale_colour_manual(
    values = c(
      "Both significant" = "darkred",
      "2023-break only"  = "firebrick",
      "2022-break only"  = "steelblue",
      "Neither"          = "grey60"
    ),
    name = "90% CI significance"
  ) +
  labs(
    x        = "Posterior mean gamma (break at 2023)",
    y        = "Posterior mean gamma (break at 2022)",
    title    = "Robustness check: gamma estimates under 2023 vs 2022 post-LLM break",
    subtitle = paste0(
      "Dashed line = 45° (perfect agreement). ",
      nrow(comp), " L3 methods. Labels = 10 most divergent."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(OUT_PLOT, p, width = 8, height = 7, units = "in")
cat("Saved:", OUT_PLOT, "\n")

# ── 8. Summary statistics ──────────────────────────────────────────────────────

cat("\n=== Robustness summary ===\n")

r <- cor(comp$mean_gamma_2023, comp$mean_gamma_2022)
cat(sprintf("Correlation between gamma_2023 and gamma_2022: %.4f\n", r))

sign_change <- sum(sign(comp$mean_gamma_2023) != sign(comp$mean_gamma_2022))
cat("Methods that change sign between break-points:", sign_change, "\n")

gain_sig <- sum(!comp$sig90_2023 & comp$sig90_2022)
lose_sig <- sum(comp$sig90_2023  & !comp$sig90_2022)
cat("Methods gaining  sig90 under 2022 break:", gain_sig, "\n")
cat("Methods losing   sig90 under 2022 break:", lose_sig, "\n")

cat("\nSignificance breakdown:\n")
print(table(comp$sig_status))

cat("\n05_robustness_2022.R complete.\n")
