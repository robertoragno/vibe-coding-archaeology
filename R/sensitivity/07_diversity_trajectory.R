# 07_diversity_trajectory.R
# Second-level model: regress posterior inv_simpson on year + post_llm
# with measurement-error likelihood. Estimates group-level gamma (post-LLM
# shift in diversity) and sigma_gamma (hierarchical SD of that shift).

suppressPackageStartupMessages({
  library(here)
  library(cmdstanr)
  library(posterior)
  library(dplyr)
  library(ggplot2)
})

FIT_RDS       <- here("data/output/fit_phi_free.rds")
VOCAB_RDS     <- here("data/output/vocab.rds")
STAN_DATA_RDS <- here("data/output/stan_data.rds")
STAN_FILE     <- here("stan/sensitivity/diversity_trajectory.stan")

OUT_FIT  <- here("data/output/fit_diversity_trajectory.rds")
OUT_PLOT <- here("R/sensitivity/diversity_gamma_by_group.png")

# ── 1. Load phi-free fit and extract inv_simpson posterior ────────────────────

cat("Loading fit_phi_free.rds...\n")
fit       <- readRDS(FIT_RDS)
vocab     <- readRDS(VOCAB_RDS)
stan_data <- readRDS(STAN_DATA_RDS)

l2_levels   <- vocab$l2_levels
year_levels <- vocab$year_levels
N_groups    <- length(l2_levels)
N_years     <- length(year_levels)

draws <- fit$draws(format = "draws_matrix")
S     <- nrow(draws)

draws_to_array <- function(draws, prefix, d1, d2) {
  arr <- array(NA_real_, dim = c(nrow(draws), d1, d2))
  for (i in seq_len(d1))
    for (j in seq_len(d2))
      arr[, i, j] <- draws[, sprintf("%s[%d,%d]", prefix, i, j)]
  arr
}

inv_simp_arr <- draws_to_array(draws, "inv_simpson", N_groups, N_years)
cat("inv_simpson draws shape:", paste(dim(inv_simp_arr), collapse = " x "), "\n")

# Posterior mean and SD per cell
obs_diversity <- matrix(0, N_groups, N_years)
meas_sd       <- matrix(0, N_groups, N_years)

# Identify zero-paper cells from raw counts
for (g in seq_len(N_groups)) {
  K <- stan_data$K_g[g]
  for (t in seq_len(N_years)) {
    total_papers <- sum(stan_data$counts[g, t, 1:K])
    if (total_papers > 0) {
      cell_draws <- inv_simp_arr[, g, t]
      obs_diversity[g, t] <- mean(cell_draws)
      meas_sd[g, t]       <- sd(cell_draws)
    }
  }
}

n_observed <- sum(obs_diversity > 0)
cat(sprintf("Non-zero cells: %d / %d (%.0f%%)\n",
            n_observed, N_groups * N_years,
            100 * n_observed / (N_groups * N_years)))

# ── 2. Fit diversity trajectory model ─────────────────────────────────────────

cat("\n** This model samples 4 chains x 2000 iterations. **\n")
cat("** Run in tmux if you are on a remote machine.     **\n\n")

mod <- cmdstan_model(STAN_FILE)

stan_input <- list(
  N_groups      = N_groups,
  N_years       = N_years,
  year_std      = stan_data$year_std,
  post_llm      = stan_data$post_llm,
  obs_diversity = obs_diversity,
  meas_sd       = meas_sd
)

fit_traj <- mod$sample(
  data            = stan_input,
  chains          = 4,
  iter_warmup     = 1000,
  iter_sampling   = 1000,
  adapt_delta     = 0.95,
  parallel_chains = 4,
  seed            = 42,
  refresh         = 200
)

# ── 3. Save fit ──────────────────────────────────────────────────────────────

fit_traj$save_object(OUT_FIT)
cat("Fit saved to:", OUT_FIT, "\n")

# ── 4. Posterior summaries ────────────────────────────────────────────────────

hyperparams <- fit_traj$summary(
  variables = c("sigma_gamma", "sigma_beta", "sigma_resid"),
  mean, ~ quantile(.x, probs = c(0.025, 0.975))
)
cat("\n=== Hyperparameter posteriors ===\n")
print(hyperparams)

gamma_vars <- paste0("gamma[", seq_len(N_groups), "]")
gamma_summary <- fit_traj$summary(
  variables = gamma_vars,
  mean, ~ quantile(.x, probs = c(0.025, 0.975))
)
gamma_summary$l2 <- l2_levels
gamma_summary$label <- sub("^L2-\\d+: ", "", l2_levels)

cat("\n=== gamma[g] posteriors (post-LLM diversity shift by L2 group) ===\n")
print(gamma_summary |> select(label, mean, `2.5%`, `97.5%`), n = N_groups)

# ── 5. Plot: gamma[g] with 95% CIs, ordered by mean ─────────────────────────

plot_df <- gamma_summary |>
  arrange(mean) |>
  mutate(label = factor(label, levels = label))

p <- ggplot(plot_df, aes(x = mean, y = label)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  geom_pointrange(aes(xmin = `2.5%`, xmax = `97.5%`),
                  size = 0.3, colour = "steelblue4") +
  labs(
    x     = "gamma (post-LLM diversity shift)",
    y     = NULL,
    title = "Post-LLM diversity shift by L2 group",
    subtitle = "Posterior mean with 95% credible intervals"
  ) +
  theme_minimal(base_size = 9) +
  theme(axis.text.y = element_text(size = 7))

ggsave(OUT_PLOT, p, width = 8, height = 10, units = "in", dpi = 150)
cat("Plot saved to:", OUT_PLOT, "\n")

cat("\n07_diversity_trajectory.R complete.\n")
