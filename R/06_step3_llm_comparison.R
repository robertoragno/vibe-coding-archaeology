# 06_step3_llm_comparison.R
# Step 3 of the analysis: correlate LLM recommendation frequency with
# posterior gamma (excess post-2023 method share above pre-existing trend).
#
# The comparison is made against gamma specifically — not raw prevalence —
# to distinguish LLM influence from mere reflection of pre-existing trends.
#
# Method: fully Bayesian Poisson regression (stan/poisson_gamma_regression.stan).
# gamma_true is treated as latent with a Normal prior from the main model's
# posterior summary — propagating predictor uncertainty into the posterior of
# beta without needing to load the full stanfit object.
#
# Input:
#   data/output/gamma_results.csv  (or phi_free/ fallback)
#   data/output/vocab.rds
#   stan/poisson_gamma_regression.stan
#   experiment/analysis/experiment_results.csv  (exits gracefully if missing)
#
# Output:
#   data/output/plot_beta_posterior_overall.pdf
#   data/output/plot_beta_posterior_by_profile.pdf
#   data/output/plot_gamma_vs_recommendations.pdf
#   data/output/plot_top_recommended_direction.pdf
#   data/output/step3_joined_table.csv

suppressPackageStartupMessages({
  library(here)
  library(rstan)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggdist)
  library(ggrepel)
})

options(mc.cores = parallel::detectCores())
rstan_options(auto_write = TRUE)

# ── 1. Paths ───────────────────────────────────────────────────────────────────

gamma_csv_primary  <- here("data/output/gamma_results.csv")
gamma_csv_fallback <- here("data/output/phi_free/gamma_results.csv")
GAMMA_CSV      <- if (file.exists(gamma_csv_primary)) gamma_csv_primary else gamma_csv_fallback
VOCAB_PATH     <- here("data/output/vocab.rds")
STAN_FILE      <- here("stan/poisson_gamma_regression.stan")
EXPERIMENT_CSV <- here("experiment/analysis/experiment_results.csv")

OUT_BETA_OVERALL <- here("data/output/plot_beta_posterior_overall.pdf")
OUT_BETA_PROFILE <- here("data/output/plot_beta_posterior_by_profile.pdf")
OUT_SCATTER      <- here("data/output/plot_gamma_vs_recommendations.pdf")
OUT_DIRECTION    <- here("data/output/plot_top_recommended_direction.pdf")
OUT_TABLE        <- here("data/output/step3_joined_table.csv")

# ── 2. Check for experiment CSV (graceful exit if absent) ──────────────────────

if (!file.exists(EXPERIMENT_CSV)) {
  message(
    "\nExperiment results not yet available.\n",
    "Expected at: ", EXPERIMENT_CSV, "\n",
    "Run the prompting experiment and place results there before re-running this script.\n"
  )
  quit(save = "no", status = 0)
}

# ── 3. Load gamma_results and vocab ────────────────────────────────────────────

cat("Loading gamma_results from:", GAMMA_CSV, "\n")
if (!file.exists(GAMMA_CSV))
  stop("gamma_results.csv not found at:\n  ", gamma_csv_primary,
       "\n  ", gamma_csv_fallback)

gamma_df <- read.csv(GAMMA_CSV, stringsAsFactors = FALSE)
cat("gamma_df rows:", nrow(gamma_df), "\n")

cat("Loading vocab...\n")
vocab    <- readRDS(VOCAB_PATH)
l3_vocab <- vocab$l3_vocab

cat("L3 methods in vocab:", nrow(l3_vocab), "\n")

# ── 4. Load and process experiment results ─────────────────────────────────────

cat("Loading experiment results...\n")
experiment_raw <- read.csv(EXPERIMENT_CSV, stringsAsFactors = FALSE)
cat("Experiment rows (raw):", nrow(experiment_raw), "\n")

exp_consistent <- experiment_raw |>
  filter(l3_mapping_consistent == TRUE)

cat("Consistent mappings:", nrow(exp_consistent), "\n")

# Count L3 occurrences overall
n_overall <- exp_consistent |>
  count(level_3_fine = l3_mapping, name = "n_recommended_total")

# Count by profile
n_by_profile <- exp_consistent |>
  count(profile, level_3_fine = l3_mapping) |>
  pivot_wider(
    names_from  = profile,
    values_from = n,
    names_prefix = "n_recommended_",
    values_fill  = 0L
  )

for (prof in c("novice", "intermediate", "expert")) {
  col <- paste0("n_recommended_", prof)
  if (!col %in% names(n_by_profile)) n_by_profile[[col]] <- 0L
}

# Count by question (for reference; not used in GLM)
n_by_question <- exp_consistent |>
  count(question, level_3_fine = l3_mapping, name = "n") |>
  pivot_wider(
    names_from  = question,
    values_from = n,
    names_prefix = "n_q",
    values_fill  = 0L
  )

cat("Unique L3 methods recommended (consistent):",
    length(unique(exp_consistent$l3_mapping)), "\n")

# ── 5. Join recommendation counts to gamma estimates ───────────────────────────

all_l3 <- l3_vocab |> select(level_3_fine) |> distinct()

stopifnot(!anyDuplicated(all_l3$level_3_fine))
stopifnot(!anyDuplicated(gamma_df$level_3_fine))

joined <- all_l3 |>
  left_join(n_overall,    by = "level_3_fine") |>
  left_join(n_by_profile, by = "level_3_fine") |>
  mutate(across(starts_with("n_recommended"), ~ replace_na(.x, 0L))) |>
  left_join(
    gamma_df |> select(level_3_fine, mean_gamma, sd_gamma, sig90, lo90, hi90),
    by = "level_3_fine"
  )

cat("Joined table rows:", nrow(joined), "\n")
cat("Methods with n_recommended_total > 0:",
    sum(joined$n_recommended_total > 0, na.rm = TRUE), "\n")

# ── 6. Bayesian Poisson regression ────────────────────────────────────────────
#
# Model: n_rec[i] ~ Poisson(exp(alpha + beta * |gamma_true[i]|))
#        gamma_true[i] ~ Normal(mean_gamma[i], sd_gamma[i])   [stage-1 posterior as prior]
#        alpha ~ Normal(0, 2),  beta ~ Normal(0, 1)
#
# This is sequential Bayesian updating: stage-1 gamma posterior ->
# stage-2 prior on gamma_true -> proper joint posterior over (alpha, beta).

run_bayesian_poisson <- function(gamma_mean, gamma_sd, n_rec, label = "") {
  cat("\nFitting Bayesian Poisson model", if (nchar(label) > 0) paste0("(", label, ")"), "...\n")
  stan_data <- list(
    M          = length(n_rec),
    gamma_mean = gamma_mean,
    gamma_sd   = gamma_sd,
    n_rec      = as.integer(n_rec)
  )
  fit <- suppressWarnings(stan(
    file    = STAN_FILE,
    data    = stan_data,
    chains  = 4,
    iter    = 2000,
    warmup  = 1000,
    cores   = 4,
    seed    = 42,
    control = list(adapt_delta = 0.90),
    refresh = 200
  ))
  cat("Rhat (beta):", round(summary(fit, pars = "beta")$summary[, "Rhat"], 4), "\n")
  rstan::extract(fit, pars = "beta")$beta
}

gamma_mean <- joined$mean_gamma
gamma_sd   <- joined$sd_gamma

beta_overall <- run_bayesian_poisson(gamma_mean, gamma_sd,
                                     joined$n_recommended_total,    "overall")
beta_novice  <- run_bayesian_poisson(gamma_mean, gamma_sd,
                                     joined$n_recommended_novice,   "novice")
beta_inter   <- run_bayesian_poisson(gamma_mean, gamma_sd,
                                     joined$n_recommended_intermediate, "intermediate")
beta_expert  <- run_bayesian_poisson(gamma_mean, gamma_sd,
                                     joined$n_recommended_expert,   "expert")

# ── 7. Plots ───────────────────────────────────────────────────────────────────

p_pos <- function(betas) round(mean(betas > 0, na.rm = TRUE), 3)

# Plot A: overall beta posterior
overall_df <- data.frame(beta = beta_overall)
p_label    <- sprintf("P(β > 0) = %.3f", p_pos(beta_overall))

pA <- ggplot(overall_df, aes(x = beta, y = 0)) +
  stat_halfeye(
    .width         = c(0.90, 0.95),
    point_interval = "mean_qi",
    fill           = "steelblue",
    colour         = "steelblue4",
    alpha          = 0.7
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "firebrick", linewidth = 0.5) +
  annotate("text", x = Inf, y = 0.4, label = p_label,
           hjust = 1.1, size = 4, colour = "steelblue4") +
  labs(
    x        = "β: Poisson log-link coefficient (|gamma|)",
    y        = NULL,
    title    = "Posterior distribution of LLM trend-chasing coefficient (overall)",
    subtitle = "Bayesian Poisson: n_recommended ~ |gamma_true|; gamma_true uncertainty propagated via Normal prior"
  ) +
  theme_minimal(base_size = 12) +
  theme(axis.text.y = element_blank(), axis.ticks.y = element_blank())

ggsave(OUT_BETA_OVERALL, pA, width = 7, height = 5, units = "in")
cat("Saved:", OUT_BETA_OVERALL, "\n")

# Plot B: beta posteriors by profile
profile_df <- bind_rows(
  data.frame(beta = beta_novice, profile = "novice"),
  data.frame(beta = beta_inter,  profile = "intermediate"),
  data.frame(beta = beta_expert, profile = "expert")
) |>
  mutate(profile = factor(profile, levels = c("novice", "intermediate", "expert")))

p_labels_prof <- profile_df |>
  group_by(profile) |>
  summarise(label = sprintf("P(β > 0) = %.3f", mean(beta > 0)), .groups = "drop")

pB <- ggplot(profile_df, aes(x = beta, y = 0)) +
  stat_halfeye(
    .width         = c(0.90, 0.95),
    point_interval = "mean_qi",
    fill           = "steelblue",
    colour         = "steelblue4",
    alpha          = 0.7
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "firebrick", linewidth = 0.5) +
  geom_text(
    data  = p_labels_prof,
    aes(x = Inf, y = 0.4, label = label),
    hjust = 1.1, size = 3.5, colour = "steelblue4", inherit.aes = FALSE
  ) +
  facet_wrap(~ profile, ncol = 1) +
  labs(
    x        = "β: Poisson log-link coefficient (|gamma|)",
    y        = NULL,
    title    = "Posterior trend-chasing coefficient by expertise profile",
    subtitle = "Does expertise level modulate alignment with LLM recommendations?"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.y  = element_blank(),
    axis.ticks.y = element_blank(),
    strip.text   = element_text(face = "bold")
  )

ggsave(OUT_BETA_PROFILE, pB, width = 7, height = 8, units = "in")
cat("Saved:", OUT_BETA_PROFILE, "\n")

# Plot C: scatter of posterior mean |gamma| vs recommendation count
scatter_df <- joined |>
  mutate(abs_mean_gamma = abs(mean_gamma))

top_rec_labels <- scatter_df |>
  filter(n_recommended_total > 0) |>
  arrange(desc(n_recommended_total)) |>
  slice_head(n = 20)

pC <- ggplot(scatter_df, aes(x = abs_mean_gamma, y = n_recommended_total)) +
  geom_point(aes(colour = sig90), alpha = 0.6, size = 1.8) +
  geom_smooth(
    method      = "glm",
    formula     = y ~ x,
    method.args = list(family = "poisson"),
    se          = TRUE,
    colour      = "darkorange3",
    fill        = "darkorange",
    alpha       = 0.2
  ) +
  geom_text_repel(
    data        = top_rec_labels,
    aes(label   = level_3_fine),
    size        = 2.0,
    max.overlaps = 20,
    show.legend = FALSE
  ) +
  scale_colour_manual(
    values = c("TRUE" = "firebrick", "FALSE" = "grey60"),
    labels = c("TRUE" = "Credible shift (90% CI)", "FALSE" = "Uncertain"),
    name   = NULL
  ) +
  labs(
    x        = "Posterior mean |gamma| (magnitude of post-LLM method change)",
    y        = "LLM recommendation count (n consistent mappings)",
    title    = "Do LLMs recommend methods that changed most post-2023?",
    subtitle = "Each point is one L3 method. Orange = Poisson smooth."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(OUT_SCATTER, pC, width = 8, height = 6, units = "in")
cat("Saved:", OUT_SCATTER, "\n")

# Plot D: top 20 recommended, coloured by gamma direction
top20_rec <- joined |>
  arrange(desc(n_recommended_total)) |>
  slice_head(n = 20) |>
  mutate(
    direction = case_when(
      lo90 > 0 ~ "Growing",
      hi90 < 0 ~ "Declining",
      TRUE     ~ "Uncertain"
    ),
    direction = factor(direction, levels = c("Growing", "Declining", "Uncertain")),
    l3_label  = factor(level_3_fine,
                       levels = rev(level_3_fine[order(n_recommended_total)]))
  )

pD <- ggplot(top20_rec, aes(x = n_recommended_total, y = l3_label, fill = direction)) +
  geom_col(width = 0.7) +
  scale_fill_manual(
    values = c("Growing" = "firebrick", "Declining" = "steelblue", "Uncertain" = "grey70"),
    name   = "Post-2023 direction (90% CI)"
  ) +
  labs(
    x        = "Total LLM recommendation count",
    y        = NULL,
    title    = "Top 20 most-recommended L3 methods and their post-2023 trajectory",
    subtitle = "Red = gaining share post-2023, blue = declining, grey = uncertain (90% CI)"
  ) +
  theme_minimal(base_size = 10) +
  theme(axis.text.y = element_text(size = 8), legend.position = "bottom")

ggsave(OUT_DIRECTION, pD, width = 8, height = 7, units = "in")
cat("Saved:", OUT_DIRECTION, "\n")

# ── 8. Save joined table ────────────────────────────────────────────────────────

out_table <- joined |>
  select(
    level_3_fine,
    mean_gamma,
    sd_gamma,
    sig90,
    n_recommended_total,
    n_recommended_novice,
    n_recommended_intermediate,
    n_recommended_expert
  )

write.csv(out_table, OUT_TABLE, row.names = FALSE)
cat("Saved:", OUT_TABLE, "\n")

# ── 9. Console summary ─────────────────────────────────────────────────────────

cat("\n=== Step 3 summary ===\n")
cat(sprintf("Overall   beta: mean = %.3f, P(beta>0) = %.3f\n",
            mean(beta_overall), p_pos(beta_overall)))
cat(sprintf("Novice    beta: mean = %.3f, P(beta>0) = %.3f\n",
            mean(beta_novice), p_pos(beta_novice)))
cat(sprintf("Intermed. beta: mean = %.3f, P(beta>0) = %.3f\n",
            mean(beta_inter), p_pos(beta_inter)))
cat(sprintf("Expert    beta: mean = %.3f, P(beta>0) = %.3f\n",
            mean(beta_expert), p_pos(beta_expert)))

cat("\nTop 5 most-recommended L3 methods:\n")
print(out_table |> arrange(desc(n_recommended_total)) |> slice_head(n = 5) |>
        select(level_3_fine, mean_gamma, sig90, n_recommended_total))

cat("\n06_step3_llm_comparison.R complete.\n")
