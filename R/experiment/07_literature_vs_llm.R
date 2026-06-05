# 07_literature_vs_llm.R
# Two-predictor NB2: n_rec ~ log1p(n_pre) + gamma, separating corpus
# prevalence from post-2023 trajectory. 8 fits: 2 models x 4 profiles.

suppressPackageStartupMessages({
  library(here)
  library(cmdstanr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggdist)
})

source(here("R/helpers.R"))  # build_rec_vectors

# ── Paths ────────────────────────────────────────────────────────────────────

gamma_csv_primary  <- here("data/output/gamma_results.csv")
gamma_csv_fallback <- here("data/output/phi_free/gamma_results.csv")
GAMMA_CSV  <- if (file.exists(gamma_csv_primary)) gamma_csv_primary else gamma_csv_fallback
VOCAB_RDS  <- here("data/output/vocab.rds")
STAN_DATA  <- here("data/output/stan_data.rds")
STAN_FILE  <- here("stan/experiment_prevalence_nb.stan")
QWEN_CSV   <- here("experiment/analysis/experiment_results_QWEN.csv")
GEMMA_CSV  <- here("experiment/analysis/experiment_results_GEMMA.csv")

OUT_DIR <- here("data/output/figures/prevalence_gamma")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

OUT_SUMMARY <- here("data/output/prevalence_gamma_summary.csv")
OUT_DRAWS   <- here("data/output/prevalence_gamma_draws.csv")
OUT_PLOT_A  <- file.path(OUT_DIR, "plot_bpre_bgamma_posteriors.png")
OUT_PLOT_B  <- file.path(OUT_DIR, "plot_bpre_bgamma_by_profile.png")

# ── Load data ────────────────────────────────────────────────────────────────

gamma_df  <- read.csv(GAMMA_CSV, stringsAsFactors = FALSE)
vocab     <- readRDS(VOCAB_RDS)
stan_data <- readRDS(STAN_DATA)
l3_vocab  <- vocab$l3_vocab |> arrange(g, k_local)

K <- nrow(l3_vocab)
year_levels <- vocab$year_levels
pre_idx <- which(year_levels < 2023)

# Pre-2023 literature counts per L3 method
n_pre_vec <- numeric(K)
row_idx   <- 0
for (g in seq_len(stan_data$N_groups)) {
  for (k in seq_len(stan_data$K_g[g])) {
    row_idx <- row_idx + 1
    n_pre_vec[row_idx] <- sum(stan_data$counts[g, pre_idx, k])
  }
}
names(n_pre_vec) <- l3_vocab$l3

# Signed gamma per L3
gamma_vec <- setNames(gamma_df$mean_gamma, gamma_df$l3)

# ── Build recommendation count vectors ───────────────────────────────────────

qwen_rec  <- build_rec_vectors(QWEN_CSV, l3_vocab$l3)
gemma_rec <- build_rec_vectors(GEMMA_CSV, l3_vocab$l3)

# ── Compile Stan model ───────────────────────────────────────────────────────

cat("Compiling Stan model...\n")
mod <- cmdstan_model(STAN_FILE)

# ── Fit function ─────────────────────────────────────────────────────────────

fit_nb2 <- function(mod, n_rec, x_pre, gamma_signed, label = "") {
  cat(sprintf("\nFitting: %s (M = %d, sum(n_rec) = %d)\n", label, length(n_rec), sum(n_rec)))
  sdata <- list(
    M            = length(n_rec),
    x_pre        = x_pre,
    gamma_signed = gamma_signed,
    n_rec        = as.integer(n_rec)
  )
  fit <- mod$sample(
    data            = sdata,
    chains          = 4,
    iter_sampling   = 1000,
    iter_warmup     = 1000,
    parallel_chains = 4,
    seed            = 42,
    adapt_delta     = 0.95,
    refresh         = 200
  )
  s <- fit$summary(variables = c("alpha", "b_pre", "b_gamma", "phi"))
  rhat_max <- round(max(s$rhat, na.rm = TRUE), 4)
  neff_min <- round(min(s$ess_bulk, na.rm = TRUE), 0)
  cat(sprintf("  max Rhat = %.4f | min n_eff = %d\n", rhat_max, neff_min))

  draws <- fit$draws(format = "draws_matrix")
  list(
    b_pre    = as.numeric(draws[, "b_pre"]),
    b_gamma  = as.numeric(draws[, "b_gamma"]),
    alpha    = as.numeric(draws[, "alpha"]),
    rhat_max = rhat_max,
    neff_min = neff_min
  )
}

# ── Prepare predictors (same for all fits) ───────────────────────────────────

x_pre <- log1p(n_pre_vec[l3_vocab$l3])
gamma_signed <- gamma_vec[l3_vocab$l3]

# ── Run all 8 fits ───────────────────────────────────────────────────────────

profiles <- c("overall", "novice", "intermediate", "expert")
results <- list()

for (model_name in c("Qwen3", "Gemma")) {
  rec_list <- if (model_name == "Qwen3") qwen_rec else gemma_rec
  for (prof in profiles) {
    label <- paste(model_name, prof, sep = " — ")
    results[[label]] <- fit_nb2(mod, rec_list[[prof]], x_pre, gamma_signed, label)
  }
}

# ── Summary table ────────────────────────────────────────────────────────────

p_pos <- function(x) round(mean(x > 0, na.rm = TRUE), 3)

summary_rows <- lapply(names(results), function(nm) {
  r <- results[[nm]]
  parts <- strsplit(nm, " — ")[[1]]
  data.frame(
    model    = parts[1],
    profile  = parts[2],
    b_pre_mean  = round(mean(r$b_pre), 3),
    b_pre_lo50  = round(quantile(r$b_pre, 0.25), 3),
    b_pre_hi50  = round(quantile(r$b_pre, 0.75), 3),
    b_pre_lo90  = round(quantile(r$b_pre, 0.05), 3),
    b_pre_hi90  = round(quantile(r$b_pre, 0.95), 3),
    b_pre_ppos  = p_pos(r$b_pre),
    b_gamma_mean = round(mean(r$b_gamma), 3),
    b_gamma_lo50 = round(quantile(r$b_gamma, 0.25), 3),
    b_gamma_hi50 = round(quantile(r$b_gamma, 0.75), 3),
    b_gamma_lo90 = round(quantile(r$b_gamma, 0.05), 3),
    b_gamma_hi90 = round(quantile(r$b_gamma, 0.95), 3),
    b_gamma_ppos = p_pos(r$b_gamma),
    rhat_max     = r$rhat_max,
    neff_min     = r$neff_min,
    stringsAsFactors = FALSE
  )
})
summary_df <- bind_rows(summary_rows)

cat("\n=== Two-predictor NB2 results ===\n")
print(summary_df, row.names = FALSE, right = FALSE)

write.csv(summary_df, OUT_SUMMARY, row.names = FALSE)
cat("\nSummary saved:", OUT_SUMMARY, "\n")

# ── Save draws (wide format, overall only for compactness) ───────────────────

draws_df <- data.frame(
  qwen_b_pre    = results[["Qwen3 — overall"]]$b_pre,
  qwen_b_gamma  = results[["Qwen3 — overall"]]$b_gamma,
  gemma_b_pre   = results[["Gemma — overall"]]$b_pre,
  gemma_b_gamma = results[["Gemma — overall"]]$b_gamma
)
write.csv(draws_df, OUT_DRAWS, row.names = FALSE)
cat("Draws saved:", OUT_DRAWS, "\n")

# ── Plot A: b_pre vs b_gamma posteriors (overall, both models) ───────────────

plot_df_a <- bind_rows(
  data.frame(value = results[["Qwen3 — overall"]]$b_pre,
             parameter = "b_pre (corpus prevalence)", model = "Qwen3"),
  data.frame(value = results[["Qwen3 — overall"]]$b_gamma,
             parameter = "b_gamma (post-2023 excess)", model = "Qwen3"),
  data.frame(value = results[["Gemma — overall"]]$b_pre,
             parameter = "b_pre (corpus prevalence)", model = "Gemma"),
  data.frame(value = results[["Gemma — overall"]]$b_gamma,
             parameter = "b_gamma (post-2023 excess)", model = "Gemma")
)

pA <- ggplot(plot_df_a, aes(x = value, y = model, fill = model)) +
  stat_halfeye(
    .width         = c(0.90, 0.95),
    point_interval = "mean_qi",
    alpha          = 0.7
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
  facet_wrap(~ parameter, scales = "free_x", ncol = 1) +
  scale_fill_manual(values = c("Qwen3" = "#0072B2", "Gemma" = "#CC79A7")) +
  labs(
    x     = "Posterior coefficient",
    y     = NULL,
    title = "Training-corpus prevalence vs. post-2023 trajectory",
    subtitle = "Two-predictor NB2: n_rec ~ log1p(n_pre) + gamma. Overall (all profiles pooled)."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none",
        strip.text = element_text(face = "bold"))

ggsave(OUT_PLOT_A, pA, width = 8, height = 5, dpi = 200, bg = "white")
cat("Plot A saved:", OUT_PLOT_A, "\n")

# ── Plot B: by-profile comparison (b_gamma only, key parameter) ──────────────

profile_rows <- lapply(names(results), function(nm) {
  r <- results[[nm]]
  parts <- strsplit(nm, " — ")[[1]]
  data.frame(
    value   = r$b_gamma,
    model   = parts[1],
    profile = parts[2]
  )
})
plot_df_b <- bind_rows(profile_rows) |>
  mutate(profile = factor(profile, levels = c("overall", "novice", "intermediate", "expert")))

pB <- ggplot(plot_df_b, aes(x = value, y = model, fill = model)) +
  stat_halfeye(
    .width         = c(0.90, 0.95),
    point_interval = "mean_qi",
    alpha          = 0.7
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
  facet_wrap(~ profile, ncol = 1) +
  scale_fill_manual(values = c("Qwen3" = "#0072B2", "Gemma" = "#CC79A7")) +
  labs(
    x     = "b_gamma (post-2023 excess coefficient)",
    y     = NULL,
    title = "Post-2023 trajectory coefficient by profile and model",
    subtitle = "After controlling for pre-2023 corpus prevalence. Positive = LLM favours post-2023 gainers."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        strip.text = element_text(face = "bold"))

ggsave(OUT_PLOT_B, pB, width = 8, height = 7, dpi = 200, bg = "white")
cat("Plot B saved:", OUT_PLOT_B, "\n")

# ── Print key findings ───────────────────────────────────────────────────────

cat("\n=== Key findings ===\n")
for (model_name in c("Qwen3", "Gemma")) {
  r <- results[[paste(model_name, "overall", sep = " — ")]]
  cat(sprintf("\n%s (overall):\n", model_name))
  cat(sprintf("  b_pre:   mean = %+.3f, 90%% CI [%+.3f, %+.3f], P(>0) = %.3f\n",
              mean(r$b_pre), quantile(r$b_pre, 0.05), quantile(r$b_pre, 0.95), mean(r$b_pre > 0)))
  cat(sprintf("  b_gamma: mean = %+.3f, 90%% CI [%+.3f, %+.3f], P(>0) = %.3f\n",
              mean(r$b_gamma), quantile(r$b_gamma, 0.05), quantile(r$b_gamma, 0.95), mean(r$b_gamma > 0)))
}

cat("\n08_literature_vs_llm.R complete.\n")
