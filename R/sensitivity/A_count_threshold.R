# A_count_threshold.R
# Sensitivity variant of R/archive/06_step3_llm_comparison.R.
# Restricts to L3 methods with >= MIN_COUNT papers in 2023-2025
# (from the raw count data) before running the Bayesian NB regression.

suppressPackageStartupMessages({
  library(here)
  library(cmdstanr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggdist)
  library(ggrepel)
})

MIN_COUNT <- 50

# ── 1. Paths ───────────────────────────────────────────────────────────────────

gamma_csv_primary  <- here("data/output/gamma_results.csv")
gamma_csv_fallback <- here("data/output/phi_free/gamma_results.csv")
GAMMA_CSV      <- if (file.exists(gamma_csv_primary)) gamma_csv_primary else gamma_csv_fallback
VOCAB_PATH     <- here("data/output/vocab.rds")
STAN_DATA_PATH <- here("data/output/stan_data.rds")
STAN_FILE      <- here("stan/archive/poisson_gamma_regression.stan")
EXPERIMENT_CSV <- here("experiment/analysis/experiment_results_QWEN.csv")

dir.create(here("data/output/sensitivity"), recursive = TRUE, showWarnings = FALSE)
dir.create(here("data/output/figures/sensitivity"), recursive = TRUE, showWarnings = FALSE)

OUT_BETA_OVERALL <- here("data/output/figures/sensitivity/plot_beta_posterior_overall.png")
OUT_BETA_PROFILE <- here("data/output/figures/sensitivity/plot_beta_posterior_by_profile.png")
OUT_SCATTER      <- here("data/output/figures/sensitivity/plot_gamma_vs_recommendations.png")
OUT_DIRECTION    <- here("data/output/figures/sensitivity/plot_top_recommended_direction.png")
OUT_TABLE        <- here("data/output/sensitivity/step3_joined_table.csv")
OUT_BETA_SUMMARY <- here("data/output/sensitivity/step3_beta_summary.csv")

# ── 2. Check for experiment CSV (graceful exit if absent) ──────────────────────

if (!file.exists(EXPERIMENT_CSV)) {
  message(
    "\nExperiment results not yet available.\n",
    "Expected at: ", EXPERIMENT_CSV, "\n",
    "Run the prompting experiment and place results there before re-running this script.\n"
  )
  quit(save = "no", status = 0)
}

# ── 3. Load gamma_results, vocab, and stan_data ───────────────────────────────

cat("Loading gamma_results from:", GAMMA_CSV, "\n")
if (!file.exists(GAMMA_CSV))
  stop("gamma_results.csv not found at:\n  ", gamma_csv_primary,
       "\n  ", gamma_csv_fallback)

gamma_df <- read.csv(GAMMA_CSV, stringsAsFactors = FALSE)
cat("gamma_df rows:", nrow(gamma_df), "\n")

cat("Loading vocab...\n")
vocab    <- readRDS(VOCAB_PATH)
l3_vocab <- vocab$l3_vocab

cat("Loading stan_data for paper counts...\n")
stan_data   <- readRDS(STAN_DATA_PATH)
year_levels <- vocab$year_levels

cat("L3 methods in vocab:", nrow(l3_vocab), "\n")

# ── 3b. Compute total papers per L3 method in 2023-2025 ──────────────────────
# Paper counts come from the raw count array in stan_data.rds, not from
# gamma_results.csv (which only has posterior summaries).

year_idx <- which(year_levels %in% 2023:2025)
cat("Year indices for 2023-2025:", paste(year_idx, collapse = ", "), "\n")

paper_counts <- do.call(rbind, lapply(seq_len(stan_data$N_groups), function(g) {
  K <- stan_data$K_g[g]
  data.frame(
    g = g,
    k = seq_len(K),
    n_papers_2023_25 = vapply(seq_len(K), function(k) {
      sum(stan_data$counts[g, year_idx, k])
    }, numeric(1))
  )
}))

gamma_with_counts <- gamma_df |>
  left_join(paper_counts, by = c("g", "k"))

methods_surviving <- gamma_with_counts |>
  filter(n_papers_2023_25 >= MIN_COUNT)

cat(sprintf(
  "\nCount threshold filter: %d / %d L3 methods have >= %d papers in 2023-2025\n",
  nrow(methods_surviving), nrow(gamma_with_counts), MIN_COUNT
))

surviving_l3 <- methods_surviving$l3

# ── 4. Load and process experiment results ─────────────────────────────────────

cat("Loading experiment results...\n")
experiment_raw <- read.csv(EXPERIMENT_CSV, stringsAsFactors = FALSE)
cat("Experiment rows (raw):", nrow(experiment_raw), "\n")

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

n_by_question <- exp_consistent |>
  count(question, l3 = l3_mapping, name = "n") |>
  pivot_wider(
    names_from  = question,
    values_from = n,
    names_prefix = "n_q",
    values_fill  = 0L
  )

cat("Unique L3 methods recommended (consistent):",
    length(unique(exp_consistent$l3_mapping)), "\n")

# ── 5. Join and apply count threshold ─────────────────────────────────────────

all_l3 <- l3_vocab |> select(l3) |> distinct()

stopifnot(!anyDuplicated(all_l3$l3))
stopifnot(!anyDuplicated(gamma_df$l3))

joined <- all_l3 |>
  left_join(n_overall,    by = "l3") |>
  left_join(n_by_profile, by = "l3") |>
  mutate(across(starts_with("n_recommended"), ~ replace_na(.x, 0L))) |>
  left_join(
    gamma_df |> select(l3, mean_gamma, sd_gamma, sig90, lo90, hi90),
    by = "l3"
  ) |>
  filter(l3 %in% surviving_l3)

cat(sprintf(
  "Joined table after count threshold: %d methods (from %d total)\n",
  nrow(joined), nrow(all_l3)
))
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

overall_df <- data.frame(beta = beta_overall)
p_label    <- sprintf("P(beta > 0) = %.3f", p_pos(beta_overall))

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
    x        = "beta: log-link coefficient on mean gamma (signed)",
    y        = NULL,
    title    = sprintf("Posterior of LLM trend-chasing coefficient (>= %d papers)", MIN_COUNT),
    subtitle = "Bayesian NB: n_recommended ~ mean_gamma; positive beta = LLMs favour methods gaining post-2023"
  ) +
  theme_minimal(base_size = 12) +
  theme(axis.text.y = element_blank(), axis.ticks.y = element_blank())

ggsave(OUT_BETA_OVERALL, pA, width = 7, height = 5, units = "in", dpi = 150)
cat("Saved:", OUT_BETA_OVERALL, "\n")

profile_df <- bind_rows(
  data.frame(beta = beta_novice, profile = "novice"),
  data.frame(beta = beta_inter,  profile = "intermediate"),
  data.frame(beta = beta_expert, profile = "expert")
) |>
  mutate(profile = factor(profile, levels = c("novice", "intermediate", "expert")))

p_labels_prof <- profile_df |>
  group_by(profile) |>
  summarise(label = sprintf("P(beta > 0) = %.3f", mean(beta > 0)), .groups = "drop")

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
    x        = "beta: log-link coefficient on mean gamma (signed)",
    y        = NULL,
    title    = sprintf("Posterior trend-chasing coefficient by profile (>= %d papers)", MIN_COUNT),
    subtitle = "Does expertise level modulate alignment with LLM recommendations?"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.y  = element_blank(),
    axis.ticks.y = element_blank(),
    strip.text   = element_text(face = "bold")
  )

ggsave(OUT_BETA_PROFILE, pB, width = 7, height = 8, units = "in", dpi = 150)
cat("Saved:", OUT_BETA_PROFILE, "\n")

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
    x        = "Posterior mean gamma (signed; right = gaining post-2023, left = declining)",
    y        = "LLM recommendation count (n consistent mappings)",
    title    = sprintf("LLM recommendations vs post-2023 shift (>= %d papers)", MIN_COUNT),
    subtitle = "Each point is one L3 method. Red = credible post-2023 shift (90% CI)."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(OUT_SCATTER, pC, width = 8, height = 6, units = "in", dpi = 150)
cat("Saved:", OUT_SCATTER, "\n")

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
    l3_label  = factor(l3,
                       levels = rev(l3[order(n_recommended_total)]))
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
    title    = sprintf("Top 20 most-recommended L3 methods (>= %d papers)", MIN_COUNT),
    subtitle = "Red = gaining share post-2023, blue = declining, grey = uncertain (90% CI)"
  ) +
  theme_minimal(base_size = 10) +
  theme(axis.text.y = element_text(size = 8), legend.position = "bottom")

ggsave(OUT_DIRECTION, pD, width = 8, height = 7, units = "in", dpi = 150)
cat("Saved:", OUT_DIRECTION, "\n")

# ── 8. Save beta draws ────────────────────────────────────────────────────────

OUT_BETA_DRAWS  <- here("data/output/sensitivity/step3_beta_draws.csv")
OUT_CONVERGENCE <- here("data/output/sensitivity/step3_convergence.csv")
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

# ── 9. Save joined table ──────────────────────────────────────────────────────

out_table <- joined |>
  select(
    l3,
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

# ── 10. Console summary ──────────────────────────────────────────────────────

beta_summary <- data.frame(
  profile   = c("overall", "novice", "intermediate", "expert"),
  beta_mean = c(mean(beta_overall), mean(beta_novice),
                mean(beta_inter),   mean(beta_expert)),
  p_pos     = c(p_pos(beta_overall), p_pos(beta_novice),
                p_pos(beta_inter),   p_pos(beta_expert)),
  run_date  = Sys.Date()
)
write.csv(beta_summary, OUT_BETA_SUMMARY, row.names = FALSE)
cat("Saved:", OUT_BETA_SUMMARY, "\n")

cat("\n=== Step 3 count-threshold sensitivity (MIN_COUNT =", MIN_COUNT, ") ===\n")
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
        select(l3, mean_gamma, sig90, n_recommended_total))

cat("\nA_count_threshold.R complete.\n")
