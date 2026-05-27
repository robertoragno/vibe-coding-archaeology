# 06b_step3_llm_comparison_gemma.R
# Step 3 replication with Gemma: negative-binomial regression of
# recommendation frequency on signed gamma.
# Mirrors 06_step3_llm_comparison.R exactly, swapping Qwen for Gemma.

suppressPackageStartupMessages({
  library(here)
  library(cmdstanr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggdist)
  library(ggrepel)
})

# ── 1. Paths ───────────────────────────────────────────────────────────────────

gamma_csv_primary  <- here("data/output/gamma_results.csv")
gamma_csv_fallback <- here("data/output/phi_free/gamma_results.csv")
GAMMA_CSV      <- if (file.exists(gamma_csv_primary)) gamma_csv_primary else gamma_csv_fallback
VOCAB_PATH     <- here("data/output/vocab.rds")
STAN_FILE      <- here("stan/poisson_gamma_regression.stan")
EXPERIMENT_CSV <- here("experiment/analysis/experiment_results_GEMMA.csv")

dir.create(here("data/output/figures/step3_gemma"), recursive = TRUE, showWarnings = FALSE)

OUT_BETA_OVERALL <- here("data/output/figures/step3_gemma/plot_beta_posterior_overall.png")
OUT_BETA_PROFILE <- here("data/output/figures/step3_gemma/plot_beta_posterior_by_profile.png")
OUT_SCATTER      <- here("data/output/figures/step3_gemma/plot_gamma_vs_recommendations.png")
OUT_DIRECTION    <- here("data/output/figures/step3_gemma/plot_top_recommended_direction.png")
OUT_TABLE        <- here("data/output/step3_gemma_joined_table.csv")
OUT_BETA_SUMMARY <- here("data/output/step3_gemma_beta_summary.csv")
OUT_BETA_DRAWS   <- here("data/output/step3_gemma_beta_draws.csv")
OUT_CONVERGENCE  <- here("data/output/step3_gemma_convergence.csv")

# ── 2. Check for experiment CSV ──────────────────────────────────────────────

if (!file.exists(EXPERIMENT_CSV)) {
  message("Gemma experiment results not found at: ", EXPERIMENT_CSV)
  quit(save = "no", status = 0)
}

# ── 3. Load gamma_results and vocab ────────────────────────────────────────────

cat("Loading gamma_results from:", GAMMA_CSV, "\n")
gamma_df <- read.csv(GAMMA_CSV, stringsAsFactors = FALSE)
vocab    <- readRDS(VOCAB_PATH)
l3_vocab <- vocab$l3_vocab

cat("L3 methods in vocab:", nrow(l3_vocab), "\n")

# ── 4. Load and process Gemma experiment results ─────────────────────────────

cat("Loading Gemma experiment results...\n")
experiment_raw <- read.csv(EXPERIMENT_CSV, stringsAsFactors = FALSE)
cat("Gemma rows (raw):", nrow(experiment_raw), "\n")

exp_consistent <- experiment_raw |>
  filter(toupper(as.character(l3_mapping_consistent)) == "TRUE")
cat("Consistent mappings:", nrow(exp_consistent), "\n")

n_overall <- exp_consistent |>
  count(l3 = l3_mapping, name = "n_recommended_total")

n_by_profile <- exp_consistent |>
  count(profile, l3 = l3_mapping) |>
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

cat("Unique L3 methods recommended (consistent):",
    length(unique(exp_consistent$l3_mapping)), "\n")

# ── 5. Join recommendation counts to gamma estimates ───────────────────────────

all_l3 <- l3_vocab |> select(l3) |> distinct()

joined <- all_l3 |>
  left_join(n_overall,    by = "l3") |>
  left_join(n_by_profile, by = "l3") |>
  mutate(across(starts_with("n_recommended"), ~ replace_na(.x, 0L))) |>
  left_join(
    gamma_df |> select(l3, mean_gamma, sd_gamma, sig90, lo90, hi90),
    by = "l3"
  )

cat("Joined table rows:", nrow(joined), "\n")
cat("Methods with n_recommended_total > 0:",
    sum(joined$n_recommended_total > 0, na.rm = TRUE), "\n")

# ── 6. Bayesian negative-binomial regression ──────────────────────────────────

mod <- cmdstan_model(STAN_FILE)

run_bayesian_nb <- function(mod, gamma_signed, n_rec, label = "") {
  cat("\nFitting Bayesian NB model", if (nchar(label) > 0) paste0("(", label, ")"), "...\n")
  stan_data <- list(
    M            = length(n_rec),
    gamma_signed = gamma_signed,
    n_rec        = as.integer(n_rec)
  )
  fit <- mod$sample(
    data            = stan_data,
    chains          = 4,
    iter_sampling   = 1000,
    iter_warmup     = 1000,
    parallel_chains = 4,
    seed            = 42,
    adapt_delta     = 0.95,
    refresh         = 200
  )
  s <- fit$summary(variables = c("alpha", "beta", "phi"))
  rhat_max <- round(max(s$rhat, na.rm = TRUE), 4)
  neff_min <- round(min(s$ess_bulk, na.rm = TRUE), 0)
  cat(sprintf("  max Rhat = %.4f | min n_eff = %d\n", rhat_max, neff_min))

  draws <- fit$draws(format = "draws_matrix")
  list(
    draws    = as.numeric(draws[, "beta"]),
    rhat_max = rhat_max,
    neff_min = neff_min
  )
}

gamma_signed <- joined$mean_gamma

fit_overall <- run_bayesian_nb(mod, gamma_signed, joined$n_recommended_total,        "overall")
fit_novice  <- run_bayesian_nb(mod, gamma_signed, joined$n_recommended_novice,       "novice")
fit_inter   <- run_bayesian_nb(mod, gamma_signed, joined$n_recommended_intermediate, "intermediate")
fit_expert  <- run_bayesian_nb(mod, gamma_signed, joined$n_recommended_expert,       "expert")

beta_overall <- fit_overall$draws
beta_novice  <- fit_novice$draws
beta_inter   <- fit_inter$draws
beta_expert  <- fit_expert$draws

# ── 7. Plots ───────────────────────────────────────────────────────────────────

p_pos <- function(betas) round(mean(betas > 0, na.rm = TRUE), 3)

# Plot A: overall beta posterior
overall_df <- data.frame(beta = beta_overall)
p_label    <- sprintf("P(β > 0) = %.3f", p_pos(beta_overall))

pA <- ggplot(overall_df, aes(x = beta, y = 0)) +
  stat_halfeye(
    .width         = c(0.90, 0.95),
    point_interval = "mean_qi",
    fill           = "#CC79A7",
    colour         = "#874c6e",
    alpha          = 0.7
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "firebrick", linewidth = 0.5) +
  annotate("text", x = Inf, y = 0.4, label = p_label,
           hjust = 1.1, size = 4, colour = "#874c6e") +
  labs(
    x        = "β: log-link coefficient on mean γ (signed)",
    y        = NULL,
    title    = "Gemma: Posterior distribution of LLM trend-chasing coefficient (overall)",
    subtitle = "Bayesian NB: n_recommended ~ mean_gamma; positive β = LLMs favour methods gaining post-2023"
  ) +
  theme_minimal(base_size = 12) +
  theme(axis.text.y = element_blank(), axis.ticks.y = element_blank())

ggsave(OUT_BETA_OVERALL, pA, width = 7, height = 5, units = "in", dpi = 150)
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
    fill           = "#CC79A7",
    colour         = "#874c6e",
    alpha          = 0.7
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "firebrick", linewidth = 0.5) +
  geom_text(
    data  = p_labels_prof,
    aes(x = Inf, y = 0.4, label = label),
    hjust = 1.1, size = 3.5, colour = "#874c6e", inherit.aes = FALSE
  ) +
  facet_wrap(~ profile, ncol = 1) +
  labs(
    x        = "β: log-link coefficient on mean γ (signed)",
    y        = NULL,
    title    = "Gemma: Posterior trend-chasing coefficient by expertise profile",
    subtitle = "Does expertise level modulate alignment with Gemma recommendations?"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.y  = element_blank(),
    axis.ticks.y = element_blank(),
    strip.text   = element_text(face = "bold")
  )

ggsave(OUT_BETA_PROFILE, pB, width = 7, height = 8, units = "in", dpi = 150)
cat("Saved:", OUT_BETA_PROFILE, "\n")

# Plot C: scatter
top_rec_labels <- joined |>
  filter(n_recommended_total > 0) |>
  arrange(desc(n_recommended_total)) |>
  slice_head(n = 20)

pC <- ggplot(joined, aes(x = mean_gamma, y = n_recommended_total)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  geom_point(aes(colour = sig90), alpha = 0.6, size = 1.8) +
  geom_text_repel(
    data        = top_rec_labels,
    aes(label   = l3),
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
    x        = "Posterior mean γ (signed; right = gaining, left = declining)",
    y        = "Gemma recommendation count",
    title    = "Gemma: Do LLMs recommend methods gaining post-2023?",
    subtitle = "Each point is one L3 method. Red = credible post-2023 shift (90% CI)."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(OUT_SCATTER, pC, width = 8, height = 6, units = "in", dpi = 150)
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
    l3_label  = factor(l3, levels = rev(l3[order(n_recommended_total)]))
  )

pD <- ggplot(top20_rec, aes(x = n_recommended_total, y = l3_label, fill = direction)) +
  geom_col(width = 0.7) +
  scale_fill_manual(
    values = c("Growing" = "firebrick", "Declining" = "steelblue", "Uncertain" = "grey70"),
    name   = "Post-2023 direction (90% CI)"
  ) +
  labs(
    x        = "Total Gemma recommendation count",
    y        = NULL,
    title    = "Gemma: Top 20 most-recommended L3 methods and their post-2023 trajectory",
    subtitle = "Red = gaining, blue = declining, grey = uncertain (90% CI)"
  ) +
  theme_minimal(base_size = 10) +
  theme(axis.text.y = element_text(size = 8), legend.position = "bottom")

ggsave(OUT_DIRECTION, pD, width = 8, height = 7, units = "in", dpi = 150)
cat("Saved:", OUT_DIRECTION, "\n")

# ── 8. Save outputs ──────────────────────────────────────────────────────────

draws_df <- data.frame(
  beta_overall = beta_overall,
  beta_novice  = beta_novice,
  beta_inter   = beta_inter,
  beta_expert  = beta_expert
)
write.csv(draws_df, OUT_BETA_DRAWS, row.names = FALSE)
cat("Saved:", OUT_BETA_DRAWS, "\n")

convergence_df <- data.frame(
  profile  = c("overall", "novice", "intermediate", "expert"),
  rhat_max = c(fit_overall$rhat_max, fit_novice$rhat_max,
               fit_inter$rhat_max,   fit_expert$rhat_max),
  neff_min = c(fit_overall$neff_min, fit_novice$neff_min,
               fit_inter$neff_min,   fit_expert$neff_min),
  run_date = Sys.Date()
)
write.csv(convergence_df, OUT_CONVERGENCE, row.names = FALSE)
cat("Saved:", OUT_CONVERGENCE, "\n")

out_table <- joined |>
  select(l3, mean_gamma, sd_gamma, sig90,
         n_recommended_total, n_recommended_novice,
         n_recommended_intermediate, n_recommended_expert)
write.csv(out_table, OUT_TABLE, row.names = FALSE)
cat("Saved:", OUT_TABLE, "\n")

beta_summary <- data.frame(
  profile   = c("overall", "novice", "intermediate", "expert"),
  beta_mean = c(mean(beta_overall), mean(beta_novice),
                mean(beta_inter),   mean(beta_expert)),
  beta_lo90 = c(quantile(beta_overall, 0.05), quantile(beta_novice, 0.05),
                quantile(beta_inter, 0.05),   quantile(beta_expert, 0.05)),
  beta_hi90 = c(quantile(beta_overall, 0.95), quantile(beta_novice, 0.95),
                quantile(beta_inter, 0.95),   quantile(beta_expert, 0.95)),
  p_pos     = c(p_pos(beta_overall), p_pos(beta_novice),
                p_pos(beta_inter),   p_pos(beta_expert)),
  run_date  = Sys.Date()
)
write.csv(beta_summary, OUT_BETA_SUMMARY, row.names = FALSE)
cat("Saved:", OUT_BETA_SUMMARY, "\n")

cat("\n=== Gemma Step 3 summary ===\n")
cat(sprintf("Overall   beta: mean = %.3f, 90%% CI = [%.3f, %.3f], P(beta>0) = %.3f\n",
            mean(beta_overall), quantile(beta_overall, 0.05), quantile(beta_overall, 0.95), p_pos(beta_overall)))
cat(sprintf("Novice    beta: mean = %.3f, 90%% CI = [%.3f, %.3f], P(beta>0) = %.3f\n",
            mean(beta_novice), quantile(beta_novice, 0.05), quantile(beta_novice, 0.95), p_pos(beta_novice)))
cat(sprintf("Intermed. beta: mean = %.3f, 90%% CI = [%.3f, %.3f], P(beta>0) = %.3f\n",
            mean(beta_inter), quantile(beta_inter, 0.05), quantile(beta_inter, 0.95), p_pos(beta_inter)))
cat(sprintf("Expert    beta: mean = %.3f, 90%% CI = [%.3f, %.3f], P(beta>0) = %.3f\n",
            mean(beta_expert), quantile(beta_expert, 0.05), quantile(beta_expert, 0.95), p_pos(beta_expert)))

cat("\n06b_step3_llm_comparison_gemma.R complete.\n")
