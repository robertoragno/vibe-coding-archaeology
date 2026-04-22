# 05_robustness_2022.R
# Robustness check: re-run primary analysis with post_llm break at 2022
# (ChatGPT public release) instead of 2023 (widespread academic adoption).
# Stable gamma estimates across both break-points strengthen temporal inference.
#
# NOTE: gamma_results.csv (2023 break) is read from data/output/phi_free/
# if data/output/gamma_results.csv does not exist there.
# gamma_results_2022.csv is saved to data/output/gamma_results_2022.csv.

suppressPackageStartupMessages({
  library(here)
  library(rstan)
  library(dplyr)
  library(ggplot2)
  library(ggrepel)
})

options(mc.cores = parallel::detectCores())
rstan_options(auto_write = TRUE)

# ── 1. Paths ───────────────────────────────────────────────────────────────────

STAN_FILE   <- here("stan/diversity_model_phi_free.stan")
SD_PATH     <- here("data/output/stan_data.rds")
VOCAB_PATH  <- here("data/output/vocab.rds")
FIT_2022    <- here("data/output/fit_phi_free_2022.rds")
DONE_FLAG   <- here("data/output/fit_phi_free_2022.done")
OUT_CSV     <- here("data/output/gamma_results_2022.csv")
OUT_PLOT    <- here("data/output/plot_robustness_2022.pdf")

gamma_csv_primary <- here("data/output/gamma_results.csv")
gamma_csv_fallback <- here("data/output/phi_free/gamma_results.csv")
GAMMA_2023_CSV <- if (file.exists(gamma_csv_primary)) gamma_csv_primary else gamma_csv_fallback

if (!file.exists(GAMMA_2023_CSV))
  stop("gamma_results.csv (2023 break) not found at:\n  ", gamma_csv_primary,
       "\n  ", gamma_csv_fallback)

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

# Sanity check: years 2022-2025 should be post_llm = 1 (4 years)
stopifnot(sum(stan_data_2022$post_llm) == 4L)
cat("post_llm sum = 4 (2022, 2023, 2024, 2025) — OK\n")

# ── 3. Re-fit (guarded by DONE_FLAG) ──────────────────────────────────────────

if (!file.exists(DONE_FLAG)) {
  cat("\nCompiling and sampling (break=2022)...\n")
  cat("Settings: chains=4, iter=4000, warmup=2000, adapt_delta=0.95, max_treedepth=14\n")
  t_start <- proc.time()

  fit_2022 <- suppressWarnings(stan(
    file    = STAN_FILE,
    data    = stan_data_2022,
    chains  = 4,
    iter    = 4000,
    warmup  = 2000,
    cores   = 4,
    seed    = 42,
    control = list(
      adapt_delta   = 0.95,
      max_treedepth = 14
    ),
    refresh = 200
  ))

  elapsed_min <- round((proc.time() - t_start)["elapsed"] / 60, 1)
  cat("Sampling done. Elapsed:", elapsed_min, "minutes\n")

  saveRDS(fit_2022, FIT_2022)
  writeLines(as.character(Sys.time()), DONE_FLAG)
  cat("Fit saved to:", FIT_2022, "\n")
} else {
  cat("Fit already complete; loading from", FIT_2022, "\n")
  fit_2022 <- readRDS(FIT_2022)
}

# ── 4. HMC diagnostics ─────────────────────────────────────────────────────────

cat("\n--- HMC diagnostics (2022 break) ---\n")
check_hmc_diagnostics(fit_2022)
cat("\n--- sigma_beta ---\n"); print(summary(fit_2022, pars = "sigma_beta")$summary)
cat("\n--- sigma_gamma ---\n"); print(summary(fit_2022, pars = "sigma_gamma")$summary)
cat("\n--- phi ---\n");         print(summary(fit_2022, pars = "phi")$summary)

# ── 5. Extract gamma_method posteriors ─────────────────────────────────────────

cat("\nExtracting gamma_method draws...\n")
vocab     <- readRDS(VOCAB_PATH)
l2_levels <- vocab$l2_levels
K_g_vec   <- vocab$K_g
N_groups  <- length(l2_levels)

gamma_arr <- rstan::extract(fit_2022, pars = "gamma_method")$gamma_method
S         <- dim(gamma_arr)[1]
cat("Draws S =", S, ", N_groups =", N_groups, "\n")

gamma_list <- vector("list", N_groups)
for (grp in seq_len(N_groups)) {
  K    <- K_g_vec[grp]
  gm_g <- matrix(gamma_arr[, grp, 1:K], nrow = S, ncol = K)

  method_labels <- vocab$l3_vocab |>
    filter(g == grp) |>
    arrange(k_local) |>
    pull(level_3_fine)

  gamma_list[[grp]] <- data.frame(
    g            = grp,
    level_2_mid  = l2_levels[grp],
    k            = seq_len(K),
    level_3_fine = method_labels,
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
    group_label = sub("^L2-\\d+: ", "", level_2_mid),
    method_id   = paste0(group_label, ": ", level_3_fine)
  )

cat("Methods with 90% CI excluding zero (2022 break):",
    sum(gamma_2022$sig90, na.rm = TRUE), "\n")

# ── 6. Save gamma_results_2022.csv ─────────────────────────────────────────────

write.csv(gamma_2022, OUT_CSV, row.names = FALSE)
cat("Saved:", OUT_CSV, "\n")

# ── 7. Comparison plot ─────────────────────────────────────────────────────────

cat("\nBuilding comparison plot...\n")
gamma_2023 <- read.csv(GAMMA_2023_CSV, stringsAsFactors = FALSE)

# Join on level_3_fine; check uniqueness first
stopifnot(!anyDuplicated(gamma_2022$level_3_fine))
stopifnot(!anyDuplicated(gamma_2023$level_3_fine))

comp <- inner_join(
  gamma_2023 |> select(level_3_fine, mean_gamma, sig90),
  gamma_2022 |> select(level_3_fine, mean_gamma, sig90),
  by     = "level_3_fine",
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
    aes(label    = level_3_fine),
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
