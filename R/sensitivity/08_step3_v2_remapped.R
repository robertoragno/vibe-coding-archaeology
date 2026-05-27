# 08_step3_v2_remapped.R
# Remap experiment results (classified under v2 taxonomy) to v3 L3 labels
# using fuzzy string matching, then re-run the Step 3 NB regression.
#
# The experiment responses were classified into v2 L3 labels. The v3 taxonomy
# has different L3 labels (242 vs 225). Only 53 match exactly. This script
# fuzzy-matches the remaining 155 v2 labels to their closest v3 counterpart,
# then repeats the negative-binomial regression from archive/06_step3_llm_comparison.R (archived).

suppressPackageStartupMessages({
  library(here)
  library(stringdist)
  library(cmdstanr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggdist)
  library(ggrepel)
})

# ── 1. Paths ─────────────────────────────────────────────────────────────────

gamma_csv_primary  <- here("data/output/gamma_results.csv")
gamma_csv_fallback <- here("data/output/phi_free/gamma_results.csv")
GAMMA_CSV      <- if (file.exists(gamma_csv_primary)) gamma_csv_primary else gamma_csv_fallback
VOCAB_PATH     <- here("data/output/vocab.rds")
STAN_FILE      <- here("stan/poisson_gamma_regression.stan")
EXPERIMENT_CSV <- here("experiment/analysis/experiment_results.csv")

OUT_DIR <- here("data/output/figures/step3_remapped")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

OUT_MAPPING      <- here("data/output/step3_v2_to_v3_mapping.csv")
OUT_TABLE        <- here("data/output/step3_remapped_joined.csv")
OUT_BETA_DRAWS   <- here("data/output/step3_remapped_beta_draws.csv")
OUT_BETA_SUMMARY <- here("data/output/step3_remapped_beta_summary.csv")
OUT_CONVERGENCE  <- here("data/output/step3_remapped_convergence.csv")
OUT_RESULTS_MD   <- here("docs/step3_remapped_results.md")

OUT_BETA_OVERALL <- file.path(OUT_DIR, "plot_beta_posterior_overall.png")
OUT_BETA_PROFILE <- file.path(OUT_DIR, "plot_beta_posterior_by_profile.png")
OUT_SCATTER      <- file.path(OUT_DIR, "plot_gamma_vs_recommendations.png")
OUT_DIRECTION    <- file.path(OUT_DIR, "plot_top_recommended_direction.png")

# ── 2. Load data ─────────────────────────────────────────────────────────────

cat("Loading gamma_results from:", GAMMA_CSV, "\n")
gamma_df <- read.csv(GAMMA_CSV, stringsAsFactors = FALSE)

vocab    <- readRDS(VOCAB_PATH)
l3_vocab <- vocab$l3_vocab
v3_labels <- sort(unique(l3_vocab$l3))

experiment_raw <- read.csv(EXPERIMENT_CSV, stringsAsFactors = FALSE)
exp_consistent <- experiment_raw |>
  filter(toupper(as.character(l3_mapping_consistent)) == "TRUE")

v2_labels <- sort(unique(exp_consistent$l3_mapping))

cat("v2 unique L3 labels:", length(v2_labels), "\n")
cat("v3 unique L3 labels:", length(v3_labels), "\n")

# ── 3. Build v2 → v3 mapping ────────────────────────────────────────────────

strip_prefix <- function(x) sub("^L3-\\d+:\\s*", "", x)
extract_prefix <- function(x) sub(":.*", "", x)

v2_names <- strip_prefix(v2_labels)
v3_names <- strip_prefix(v3_labels)

# Compute string distance matrix (Jaro-Winkler, good for similar names)
dist_mat <- stringdistmatrix(tolower(v2_names), tolower(v3_names), method = "jw")

mapping <- data.frame(
  v2_label     = v2_labels,
  v2_name      = v2_names,
  stringsAsFactors = FALSE
)

mapping$best_v3_idx  <- apply(dist_mat, 1, which.min)
mapping$best_v3_dist <- apply(dist_mat, 1, min)
mapping$v3_label     <- v3_labels[mapping$best_v3_idx]
mapping$v3_name      <- v3_names[mapping$best_v3_idx]
mapping$exact_match  <- mapping$v2_label == mapping$v3_label

# Also try matching by L3 numeric prefix (L3-009 → L3-009)
v2_prefix <- extract_prefix(v2_labels)
v3_prefix <- extract_prefix(v3_labels)
prefix_match_idx <- match(v2_prefix, v3_prefix)

mapping$prefix_match_v3 <- ifelse(
  !is.na(prefix_match_idx),
  v3_labels[prefix_match_idx],
  NA_character_
)

# Use prefix match when available (same L3 number = same concept, renamed)
# Fall back to fuzzy match otherwise
mapping$final_v3 <- ifelse(
  !is.na(mapping$prefix_match_v3),
  mapping$prefix_match_v3,
  mapping$v3_label
)

mapping$match_type <- case_when(
  mapping$exact_match ~ "exact",
  !is.na(mapping$prefix_match_v3) ~ "prefix",
  mapping$best_v3_dist < 0.15 ~ "fuzzy_close",
  TRUE ~ "fuzzy_distant"
)

cat("\n=== Mapping summary ===\n")
cat(table(mapping$match_type), "\n")
cat("Exact:", sum(mapping$match_type == "exact"), "\n")
cat("Prefix (same L3 number):", sum(mapping$match_type == "prefix"), "\n")
cat("Fuzzy close (<0.15):", sum(mapping$match_type == "fuzzy_close"), "\n")
cat("Fuzzy distant (>=0.15):", sum(mapping$match_type == "fuzzy_distant"), "\n")

# Show worst fuzzy matches for inspection
cat("\n=== Worst 10 fuzzy matches (highest distance) ===\n")
worst <- mapping |>
  filter(match_type %in% c("fuzzy_close", "fuzzy_distant")) |>
  arrange(desc(best_v3_dist)) |>
  head(10)
for (i in seq_len(nrow(worst))) {
  cat(sprintf("  %.3f: '%s' -> '%s'\n",
    worst$best_v3_dist[i], worst$v2_name[i], worst$v3_name[i]))
}

write.csv(mapping |> select(v2_label, final_v3, match_type, best_v3_dist),
          OUT_MAPPING, row.names = FALSE)
cat("\nMapping saved to:", OUT_MAPPING, "\n")

# ── 4. Remap experiment data ─────────────────────────────────────────────────

lookup <- setNames(mapping$final_v3, mapping$v2_label)
exp_remapped <- exp_consistent |>
  mutate(l3_v3 = lookup[l3_mapping])

# Drop any that didn't map (shouldn't happen, but safety)
n_before <- nrow(exp_remapped)
exp_remapped <- exp_remapped |> filter(!is.na(l3_v3))
cat("\nRemapped rows:", nrow(exp_remapped), "of", n_before, "\n")

# Count recommendations per v3 L3
n_overall <- exp_remapped |>
  count(l3 = l3_v3, name = "n_recommended_total")

n_by_profile <- exp_remapped |>
  count(profile, l3 = l3_v3) |>
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

cat("Unique v3 L3 methods with recommendations:", length(unique(exp_remapped$l3_v3)), "\n")

# ── 5. Join to gamma estimates ───────────────────────────────────────────────

all_l3 <- l3_vocab |> select(l3) |> distinct()

joined <- all_l3 |>
  left_join(n_overall,    by = "l3") |>
  left_join(n_by_profile, by = "l3") |>
  mutate(across(starts_with("n_recommended"), ~ replace_na(.x, 0L))) |>
  left_join(
    gamma_df |> select(l3, mean_gamma, sd_gamma, sig90, lo90, hi90),
    by = "l3"
  )

cat("Methods with recommendations:", sum(joined$n_recommended_total > 0), "of", nrow(joined), "\n")

write.csv(
  joined |> select(l3, mean_gamma, sd_gamma, sig90,
                   n_recommended_total, n_recommended_novice,
                   n_recommended_intermediate, n_recommended_expert),
  OUT_TABLE, row.names = FALSE
)

# ── 6. Bayesian NB regression ────────────────────────────────────────────────

mod <- cmdstan_model(STAN_FILE)

run_bayesian_nb <- function(mod, gamma_signed, n_rec, label = "") {
  cat("\nFitting NB model", if (nchar(label) > 0) paste0("(", label, ")"), "...\n")
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
  list(draws = as.numeric(draws[, "beta"]), rhat_max = rhat_max, neff_min = neff_min)
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

# ── 7. Plots ─────────────────────────────────────────────────────────────────

p_pos <- function(betas) round(mean(betas > 0, na.rm = TRUE), 3)

# Plot A: overall beta posterior
pA <- ggplot(data.frame(beta = beta_overall), aes(x = beta, y = 0)) +
  stat_halfeye(.width = c(0.90, 0.95), point_interval = "mean_qi",
               fill = "steelblue", colour = "steelblue4", alpha = 0.7) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "firebrick", linewidth = 0.5) +
  annotate("text", x = Inf, y = 0.4,
           label = sprintf("P(β > 0) = %.3f", p_pos(beta_overall)),
           hjust = 1.1, size = 4, colour = "steelblue4") +
  labs(x = "β (signed γ predictor)", y = NULL,
       title = "Step 3 remapped: overall β posterior",
       subtitle = "v2 experiment → v3 taxonomy via fuzzy matching") +
  theme_minimal(base_size = 12) +
  theme(axis.text.y = element_blank(), axis.ticks.y = element_blank())
ggsave(OUT_BETA_OVERALL, pA, width = 7, height = 5, units = "in", dpi = 150)

# Plot B: by profile
profile_df <- bind_rows(
  data.frame(beta = beta_novice, profile = "novice"),
  data.frame(beta = beta_inter,  profile = "intermediate"),
  data.frame(beta = beta_expert, profile = "expert")
) |> mutate(profile = factor(profile, levels = c("novice", "intermediate", "expert")))

p_labels_prof <- profile_df |>
  group_by(profile) |>
  summarise(label = sprintf("P(β > 0) = %.3f", mean(beta > 0)), .groups = "drop")

pB <- ggplot(profile_df, aes(x = beta, y = 0)) +
  stat_halfeye(.width = c(0.90, 0.95), point_interval = "mean_qi",
               fill = "steelblue", colour = "steelblue4", alpha = 0.7) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "firebrick", linewidth = 0.5) +
  geom_text(data = p_labels_prof, aes(x = Inf, y = 0.4, label = label),
            hjust = 1.1, size = 3.5, colour = "steelblue4", inherit.aes = FALSE) +
  facet_wrap(~ profile, ncol = 1) +
  labs(x = "β (signed γ predictor)", y = NULL,
       title = "Step 3 remapped: β posterior by expertise profile") +
  theme_minimal(base_size = 11) +
  theme(axis.text.y = element_blank(), axis.ticks.y = element_blank(),
        strip.text = element_text(face = "bold"))
ggsave(OUT_BETA_PROFILE, pB, width = 7, height = 8, units = "in", dpi = 150)

# Plot C: scatter
top_rec <- joined |> filter(n_recommended_total > 0) |>
  arrange(desc(n_recommended_total)) |> slice_head(n = 20)

pC <- ggplot(joined, aes(x = mean_gamma, y = n_recommended_total)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  geom_point(aes(colour = sig90), alpha = 0.6, size = 1.8) +
  geom_text_repel(data = top_rec, aes(label = l3), size = 2.0,
                  max.overlaps = 20, show.legend = FALSE) +
  scale_colour_manual(values = c("TRUE" = "firebrick", "FALSE" = "grey60"),
                      labels = c("TRUE" = "Credible (90%)", "FALSE" = "Uncertain"), name = NULL) +
  labs(x = "Posterior mean γ (signed)", y = "Remapped recommendation count",
       title = "γ vs. LLM recommendations (v2→v3 remapped)") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave(OUT_SCATTER, pC, width = 8, height = 6, units = "in", dpi = 150)

# Plot D: top 20 recommended
top20 <- joined |> arrange(desc(n_recommended_total)) |> slice_head(n = 20) |>
  mutate(
    direction = case_when(lo90 > 0 ~ "Growing", hi90 < 0 ~ "Declining", TRUE ~ "Uncertain"),
    direction = factor(direction, levels = c("Growing", "Declining", "Uncertain")),
    l3_label = factor(l3, levels = rev(l3[order(n_recommended_total)]))
  )

pD <- ggplot(top20, aes(x = n_recommended_total, y = l3_label, fill = direction)) +
  geom_col(width = 0.7) +
  scale_fill_manual(values = c("Growing" = "firebrick", "Declining" = "steelblue",
                                "Uncertain" = "grey70"), name = "Post-2023 direction") +
  labs(x = "Recommendation count (remapped)", y = NULL,
       title = "Top 20 recommended methods (v2→v3 remapped)") +
  theme_minimal(base_size = 10) +
  theme(axis.text.y = element_text(size = 8), legend.position = "bottom")
ggsave(OUT_DIRECTION, pD, width = 8, height = 7, units = "in", dpi = 150)

cat("\nAll plots saved to:", OUT_DIR, "\n")

# ── 8. Save outputs ──────────────────────────────────────────────────────────

draws_df <- data.frame(
  beta_overall = beta_overall, beta_novice = beta_novice,
  beta_inter = beta_inter, beta_expert = beta_expert
)
write.csv(draws_df, OUT_BETA_DRAWS, row.names = FALSE)

convergence_df <- data.frame(
  profile  = c("overall", "novice", "intermediate", "expert"),
  rhat_max = c(fit_overall$rhat_max, fit_novice$rhat_max,
               fit_inter$rhat_max, fit_expert$rhat_max),
  neff_min = c(fit_overall$neff_min, fit_novice$neff_min,
               fit_inter$neff_min, fit_expert$neff_min),
  run_date = Sys.Date()
)
write.csv(convergence_df, OUT_CONVERGENCE, row.names = FALSE)

beta_summary <- data.frame(
  profile   = c("overall", "novice", "intermediate", "expert"),
  beta_mean = c(mean(beta_overall), mean(beta_novice),
                mean(beta_inter), mean(beta_expert)),
  p_pos     = c(p_pos(beta_overall), p_pos(beta_novice),
                p_pos(beta_inter), p_pos(beta_expert)),
  run_date  = Sys.Date()
)
write.csv(beta_summary, OUT_BETA_SUMMARY, row.names = FALSE)

# ── 9. Generate results markdown ─────────────────────────────────────────────

ci90 <- function(draws) {
  sprintf("[%.3f, %.3f]", quantile(draws, 0.05), quantile(draws, 0.95))
}

n_matched <- sum(joined$n_recommended_total > 0)
n_total <- nrow(joined)
match_types <- table(mapping$match_type)

md <- c(
  "# Step 3 Remapped — v2 Experiment → v3 Taxonomy",
  "",
  sprintf("Script: `R/sensitivity/08_step3_v2_remapped.R`  "),
  sprintf("Run date: %s", Sys.Date()),
  "",
  "---",
  "",
  "## What this does",
  "",
  "The prompting experiment (Step 3) was run with the v2 taxonomy (225 L3 methods).",
  "Taxonomy v3 has a different L3 vocabulary (242 methods with renamed labels).",
  "Under direct matching, only 53/242 methods had recommendation data — too few",
  "for a meaningful regression.",
  "",
  "This script bridges the gap by mapping v2 L3 labels to v3 L3 labels using two",
  "strategies:",
  "",
  sprintf("1. **Prefix matching** (same L3 number, e.g. L3-009 → L3-009): %d methods",
          as.integer(match_types["prefix"])),
  sprintf("2. **Exact match** (identical labels): %d methods",
          as.integer(match_types["exact"])),
  sprintf("3. **Fuzzy string match** (Jaro-Winkler distance, close): %d methods",
          ifelse("fuzzy_close" %in% names(match_types), as.integer(match_types["fuzzy_close"]), 0L)),
  sprintf("4. **Fuzzy string match** (distant, >0.15): %d methods",
          ifelse("fuzzy_distant" %in% names(match_types), as.integer(match_types["fuzzy_distant"]), 0L)),
  "",
  sprintf("After remapping, **%d / %d** v3 methods have recommendation data (%.0f%%).",
          n_matched, n_total, 100 * n_matched / n_total),
  "",
  "The full mapping table is saved to `data/output/step3_v2_to_v3_mapping.csv`.",
  "",
  "---",
  "",
  "## Results",
  "",
  "| Profile | β mean | 90% CI | P(β > 0) |",
  "|---|---|---|---|",
  sprintf("| Overall | %.3f | %s | %.3f |", mean(beta_overall), ci90(beta_overall), p_pos(beta_overall)),
  sprintf("| Novice | %.3f | %s | %.3f |", mean(beta_novice), ci90(beta_novice), p_pos(beta_novice)),
  sprintf("| Intermediate | %.3f | %s | %.3f |", mean(beta_inter), ci90(beta_inter), p_pos(beta_inter)),
  sprintf("| Expert | %.3f | %s | %.3f |", mean(beta_expert), ci90(beta_expert), p_pos(beta_expert)),
  "",
  "### Convergence",
  "",
  "| Profile | Max Rhat | Min n_eff |",
  "|---|---|---|",
  sprintf("| Overall | %.4f | %d |", fit_overall$rhat_max, fit_overall$neff_min),
  sprintf("| Novice | %.4f | %d |", fit_novice$rhat_max, fit_novice$neff_min),
  sprintf("| Intermediate | %.4f | %d |", fit_inter$rhat_max, fit_inter$neff_min),
  sprintf("| Expert | %.4f | %d |", fit_expert$rhat_max, fit_expert$neff_min),
  "",
  "---",
  "",
  "## Plots",
  "",
  "### Overall β posterior",
  "",
  sprintf("![Overall beta](../data/output/figures/step3_remapped/plot_beta_posterior_overall.png)"),
  "",
  "### β posterior by expertise profile",
  "",
  sprintf("![Profile beta](../data/output/figures/step3_remapped/plot_beta_posterior_by_profile.png)"),
  "",
  "### γ vs. recommendation count",
  "",
  sprintf("![Scatter](../data/output/figures/step3_remapped/plot_gamma_vs_recommendations.png)"),
  "",
  "### Top 20 recommended methods",
  "",
  sprintf("![Top 20](../data/output/figures/step3_remapped/plot_top_recommended_direction.png)"),
  "",
  "---",
  "",
  "## Interpretation",
  "",
  "*(Auto-generated; update after reviewing results.)*"
)

writeLines(md, OUT_RESULTS_MD)
cat("\nResults markdown saved to:", OUT_RESULTS_MD, "\n")

# ── 10. Console summary ─────────────────────────────────────────────────────

cat("\n=== Step 3 remapped summary ===\n")
cat(sprintf("Match rate: %d/%d (%.0f%%)\n", n_matched, n_total, 100 * n_matched / n_total))
cat(sprintf("Overall   beta: mean = %.3f, P(beta>0) = %.3f\n", mean(beta_overall), p_pos(beta_overall)))
cat(sprintf("Novice    beta: mean = %.3f, P(beta>0) = %.3f\n", mean(beta_novice), p_pos(beta_novice)))
cat(sprintf("Intermed. beta: mean = %.3f, P(beta>0) = %.3f\n", mean(beta_inter), p_pos(beta_inter)))
cat(sprintf("Expert    beta: mean = %.3f, P(beta>0) = %.3f\n", mean(beta_expert), p_pos(beta_expert)))

cat("\n08_step3_v2_remapped.R complete.\n")
