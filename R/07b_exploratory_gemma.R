# 07b_exploratory_gemma.R
# Exploratory graphs for Gemma experiment results + cross-model comparison
# with Qwen3. Mirrors 07_exploratory_graphs.R structure.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggrepel)
})

# ── Paths ────────────────────────────────────────────────────────────────────

GEMMA_CSV  <- here("experiment/analysis/experiment_results_GEMMA.csv")
QWEN_CSV   <- here("experiment/analysis/experiment_results_QWEN.csv")
JOINED_CSV <- here("data/output/step3_joined_table.csv")
GAMMA_CSV  <- here("data/output/phi_free/gamma_results.csv")
BETA_CSV   <- here("data/output/phi_free/beta_results.csv")
STAN_DATA_RDS <- here("data/output/stan_data.rds")
VOCAB_RDS  <- here("data/output/vocab.rds")

OUT_DIR <- here("data/output/figures/exploratory_gemma")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ── Load data ────────────────────────────────────────────────────────────────

gemma     <- read.csv(GEMMA_CSV)
qwen      <- read.csv(QWEN_CSV)
joined    <- read.csv(JOINED_CSV)
gamma_df  <- read.csv(GAMMA_CSV)
beta_df   <- read.csv(BETA_CSV)
stan_data <- readRDS(STAN_DATA_RDS)
vocab     <- readRDS(VOCAB_RDS)

cat("Gemma rows:", nrow(gemma), "\n")
cat("Qwen rows:", nrow(qwen), "\n")

# ── Helper: Inverse Simpson ──────────────────────────────────────────────────

inv_simpson <- function(x) {
  p <- x / sum(x)
  p <- p[p > 0]
  1 / sum(p^2)
}

# ── G1: Top 20 L4 methods — Gemma ───────────────────────────────────────────

collapse_l4 <- function(x) {
  x <- trimws(x)
  x <- gsub("\\s*\\([^)]*\\)", "", x)
  x <- gsub("\\s+with\\s+.*$", "", x)
  x <- gsub("^(agent-based\\s+){2,}", "Agent-Based ", x, ignore.case = TRUE)
  x <- gsub("\\s+", " ", x)
  x <- tools::toTitleCase(tolower(x))
  x
}

l4_raw_gemma <- gemma |>
  filter(l4_method != "") |>
  mutate(l4_clean = collapse_l4(l4_method)) |>
  count(l4_clean, profile, name = "n") |>
  group_by(l4_clean) |>
  mutate(total = sum(n)) |>
  ungroup()

top20_l4_gemma <- l4_raw_gemma |>
  distinct(l4_clean, total) |>
  slice_max(total, n = 20) |>
  pull(l4_clean)

plot_g1 <- l4_raw_gemma |>
  filter(l4_clean %in% top20_l4_gemma) |>
  mutate(
    l4_clean = factor(l4_clean, levels = rev(
      l4_raw_gemma |> distinct(l4_clean, total) |>
        filter(l4_clean %in% top20_l4_gemma) |>
        arrange(total) |> pull(l4_clean)
    )),
    profile = factor(profile, levels = c("novice", "intermediate", "expert"))
  ) |>
  ggplot(aes(x = n, y = l4_clean, fill = profile)) +
  geom_col() +
  scale_fill_manual(values = c(novice = "#E69F00", intermediate = "#56B4E9", expert = "#009E73")) +
  labs(
    title = "Top 20 L4 methods recommended by Gemma",
    x = "Number of recommendations", y = NULL, fill = "Profile"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "plot_top20_l4_gemma.png"), plot_g1,
       width = 8, height = 6, dpi = 200, bg = "white")
cat("G1 (Gemma L4) saved.\n")

# ── G2: Top 20 L3 methods with gamma — Gemma ────────────────────────────────

gemma_consistent <- gemma |>
  filter(toupper(as.character(l3_mapping_consistent)) == "TRUE")

n_gemma_l3 <- gemma_consistent |>
  count(l3 = l3_mapping, name = "n_recommended_total")

l3_vocab <- vocab$l3_vocab |> arrange(g, k_local)
all_l3   <- l3_vocab |> select(l3) |> distinct()

joined_gemma <- all_l3 |>
  left_join(n_gemma_l3, by = "l3") |>
  mutate(n_recommended_total = replace_na(n_recommended_total, 0L)) |>
  left_join(
    gamma_df |> select(l3, mean_gamma, sd_gamma, sig90, lo90, hi90),
    by = "l3"
  )

# By profile
n_gemma_prof <- gemma_consistent |>
  count(profile, l3 = l3_mapping) |>
  pivot_wider(names_from = profile, values_from = n,
              names_prefix = "n_recommended_", values_fill = 0L)

joined_gemma <- joined_gemma |>
  left_join(n_gemma_prof, by = "l3") |>
  mutate(across(starts_with("n_recommended_"), ~ replace_na(.x, 0L)))

cat("Gemma: L3 methods with >= 1 recommendation:",
    sum(joined_gemma$n_recommended_total > 0), "/ ", nrow(joined_gemma), "\n")

rec_gamma_gemma <- joined_gemma |>
  filter(n_recommended_total > 0) |>
  arrange(desc(n_recommended_total)) |>
  head(20) |>
  mutate(
    l3_short = sub("^L3-\\d+: ", "", l3),
    l3_short = factor(l3_short, levels = rev(l3_short))
  )

gamma_range <- max(abs(rec_gamma_gemma$mean_gamma))

plot_g2 <- ggplot(rec_gamma_gemma, aes(x = n_recommended_total, y = l3_short, fill = mean_gamma)) +
  geom_col() +
  geom_text(aes(label = sprintf("%+.3f", mean_gamma)),
            hjust = -0.1, size = 3) +
  scale_fill_gradient2(
    low = "#2166AC", mid = "grey85", high = "#B2182B",
    midpoint = 0, limits = c(-gamma_range, gamma_range),
    name = expression(bar(gamma))
  ) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = paste0("Top 20 recommended L3 methods — Gemma (",
                   sum(joined_gemma$n_recommended_total > 0), "/242 matched)"),
    subtitle = expression("Bar colour = signed posterior mean" ~ gamma ~ "(red = gaining, blue = declining)"),
    x = "Total recommendations", y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "plot_top20_l3_gemma.png"), plot_g2,
       width = 9, height = 6, dpi = 200, bg = "white")
cat("G2 (Gemma L3) saved.\n")

# ── G3: L2-level triple bar — Gemma ─────────────────────────────────────────

year_levels <- vocab$year_levels
N_groups <- stan_data$N_groups
K_g      <- stan_data$K_g

pre_idx  <- which(year_levels < 2023)
post_idx <- which(year_levels >= 2023)

freq_pre  <- numeric(nrow(l3_vocab))
freq_post <- numeric(nrow(l3_vocab))

row_idx <- 0
for (g in seq_len(N_groups)) {
  K <- K_g[g]
  for (k in seq_len(K)) {
    row_idx <- row_idx + 1
    freq_pre[row_idx]  <- sum(stan_data$counts[g, pre_idx, k])
    freq_post[row_idx] <- sum(stan_data$counts[g, post_idx, k])
  }
}

l3_freq <- l3_vocab |>
  mutate(freq_pre = freq_pre, freq_post = freq_post)

rec_vec_gemma <- setNames(joined_gemma$n_recommended_total, joined_gemma$l3)
l3_freq$freq_gemma <- rec_vec_gemma[l3_freq$l3]
l3_freq$freq_gemma[is.na(l3_freq$freq_gemma)] <- 0

l2_agg_gemma <- l3_freq |>
  group_by(l2) |>
  summarise(
    freq_pre   = sum(freq_pre),
    freq_post  = sum(freq_post),
    freq_gemma = sum(freq_gemma),
    .groups = "drop"
  ) |>
  mutate(
    share_pre   = freq_pre   / sum(freq_pre),
    share_post  = freq_post  / sum(freq_post),
    share_gemma = freq_gemma / sum(freq_gemma),
    l2_short    = sub("^L2-\\d+: ", "", l2)
  )

l2_long_gemma <- l2_agg_gemma |>
  select(l2_short, share_pre, share_post, share_gemma) |>
  pivot_longer(cols = starts_with("share_"),
               names_to = "source", values_to = "share") |>
  mutate(source = recode(source,
    share_pre   = "Pre-2023 literature",
    share_post  = "Post-2023 literature",
    share_gemma = "Gemma recommendations"
  ))

l2_order_gemma <- l2_agg_gemma |> arrange(share_gemma) |> pull(l2_short)
l2_long_gemma$l2_short <- factor(l2_long_gemma$l2_short, levels = l2_order_gemma)
l2_long_gemma$source <- factor(l2_long_gemma$source,
  levels = c("Gemma recommendations", "Post-2023 literature", "Pre-2023 literature"))

plot_g3 <- ggplot(l2_long_gemma, aes(x = share, y = l2_short, fill = source)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.65) +
  scale_fill_manual(values = c(
    "Gemma recommendations"  = "#CC79A7",
    "Post-2023 literature"   = "#D55E00",
    "Pre-2023 literature"    = "#56B4E9"
  )) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Method share by L2 sub-discipline — Gemma",
    subtitle = "Gemma recommendations vs. pre/post-2023 published literature",
    x = "Share of total", y = NULL, fill = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "plot_l2_triple_bar_gemma.png"), plot_g3,
       width = 10, height = 8, dpi = 200, bg = "white")
cat("G3 (Gemma L2 triple bar) saved.\n")

# ── G4: Beta/gamma scatter — Gemma ──────────────────────────────────────────

gamma_vec <- setNames(gamma_df$mean_gamma, gamma_df$l3)
beta_vec  <- setNames(beta_df$mean_beta, beta_df$l3)

l3_combined_gemma <- l3_freq |>
  mutate(
    mean_gamma = gamma_vec[l3],
    mean_beta  = beta_vec[l3],
    log_gemma  = log1p(freq_gemma)
  ) |>
  filter(!is.na(mean_gamma), !is.na(mean_beta))

scatter_long_gemma <- l3_combined_gemma |>
  filter(freq_gemma > 0) |>
  select(l3, l2, freq_gemma, mean_beta, mean_gamma) |>
  pivot_longer(cols = c(mean_beta, mean_gamma),
               names_to = "parameter", values_to = "value") |>
  mutate(
    parameter = recode(parameter,
      mean_beta  = "beta (pre-existing trend 2010-2022)",
      mean_gamma = "gamma (post-2023 excess above trend)"
    ),
    l3_short = sub("^L3-\\d+: ", "", l3)
  )

top_labels_gemma <- l3_combined_gemma |>
  filter(freq_gemma > 0) |>
  slice_max(freq_gemma, n = 10) |>
  pull(l3)

scatter_long_gemma <- scatter_long_gemma |>
  mutate(show_label = l3 %in% top_labels_gemma)

plot_g4 <- ggplot(scatter_long_gemma, aes(x = value, y = freq_gemma)) +
  geom_point(alpha = 0.5, size = 2, colour = "#CC79A7") +
  geom_text_repel(
    data = filter(scatter_long_gemma, show_label),
    aes(label = l3_short), size = 2.5, max.overlaps = 15,
    segment.alpha = 0.3
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
  facet_wrap(~parameter, scales = "free_x") +
  scale_y_log10() +
  labs(
    title = "Gemma: Were the recommended methods already growing before LLMs?",
    subtitle = "Each point = one L3 method with >= 1 recommendation (log scale)",
    x = "Posterior mean", y = "Gemma recommendation count (log scale)"
  ) +
  theme_minimal(base_size = 11) +
  theme(strip.text = element_text(size = 10, face = "bold"))

ggsave(file.path(OUT_DIR, "plot_beta_gamma_scatter_gemma.png"), plot_g4,
       width = 12, height = 6, dpi = 200, bg = "white")
cat("G4 (Gemma scatter) saved.\n")

# ══════════════════════════════════════════════════════════════════════════════
# CROSS-MODEL COMPARISON: Gemma vs Qwen
# ══════════════════════════════════════════════════════════════════════════════

COMP_DIR <- here("data/output/figures/comparison")
dir.create(COMP_DIR, recursive = TRUE, showWarnings = FALSE)

# ── C1: Side-by-side L3 frequency scatter ────────────────────────────────────

qwen_l3_freq <- qwen |>
  filter(toupper(as.character(l3_mapping_consistent)) == "TRUE") |>
  count(l3 = l3_mapping, name = "n_qwen")

gemma_l3_freq <- gemma_consistent |>
  count(l3 = l3_mapping, name = "n_gemma")

cross <- full_join(qwen_l3_freq, gemma_l3_freq, by = "l3") |>
  mutate(
    n_qwen  = replace_na(n_qwen, 0),
    n_gemma = replace_na(n_gemma, 0),
    l3_short = sub("^L3-\\d+: ", "", l3)
  )

top_either <- cross |>
  mutate(total = n_qwen + n_gemma) |>
  slice_max(total, n = 10) |>
  pull(l3)

plot_c1 <- ggplot(cross, aes(x = n_qwen, y = n_gemma)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey50") +
  geom_point(alpha = 0.5, size = 2, colour = "#0072B2") +
  geom_text_repel(
    data = filter(cross, l3 %in% top_either),
    aes(label = l3_short), size = 2.5, max.overlaps = 15,
    segment.alpha = 0.3
  ) +
  scale_x_log10() + scale_y_log10() +
  labs(
    title = "L3 recommendation frequency: Qwen3 vs Gemma",
    subtitle = paste0("Spearman rho = ",
                      round(cor(cross$n_qwen, cross$n_gemma, method = "spearman"), 3),
                      ". Dashed line = equal frequency."),
    x = "Qwen3 recommendations (log)", y = "Gemma recommendations (log)"
  ) +
  theme_minimal(base_size = 11)

ggsave(file.path(COMP_DIR, "plot_l3_qwen_vs_gemma.png"), plot_c1,
       width = 8, height = 7, dpi = 200, bg = "white")
cat("C1 (L3 scatter Qwen vs Gemma) saved.\n")

# ── C2: Concentration comparison table (Inverse Simpson) ────────────────────

conc_table <- data.frame(
  Distribution = c(
    "Pre-2023 literature", "Post-2023 literature",
    "Qwen3 overall", "Qwen3 — novice", "Qwen3 — intermediate", "Qwen3 — expert",
    "Gemma overall", "Gemma — novice", "Gemma — intermediate", "Gemma — expert"
  ),
  stringsAsFactors = FALSE
)

# Literature concentrations from existing data
rec_vec_qwen <- setNames(joined$n_recommended_total, joined$l3)
l3_freq$freq_qwen <- rec_vec_qwen[l3_freq$l3]
l3_freq$freq_qwen[is.na(l3_freq$freq_qwen)] <- 0

conc_table$Inv_Simpson <- c(
  inv_simpson(l3_freq$freq_pre),
  inv_simpson(l3_freq$freq_post),
  inv_simpson(l3_freq$freq_qwen),
  inv_simpson(qwen |> filter(toupper(l3_mapping_consistent)=="TRUE", profile=="novice") |> pull(l3_mapping) |> table()),
  inv_simpson(qwen |> filter(toupper(l3_mapping_consistent)=="TRUE", profile=="intermediate") |> pull(l3_mapping) |> table()),
  inv_simpson(qwen |> filter(toupper(l3_mapping_consistent)=="TRUE", profile=="expert") |> pull(l3_mapping) |> table()),
  inv_simpson(l3_freq$freq_gemma),
  inv_simpson(gemma_consistent |> filter(profile=="novice") |> pull(l3_mapping) |> table()),
  inv_simpson(gemma_consistent |> filter(profile=="intermediate") |> pull(l3_mapping) |> table()),
  inv_simpson(gemma_consistent |> filter(profile=="expert") |> pull(l3_mapping) |> table())
)

conc_table$Inv_Simpson <- round(conc_table$Inv_Simpson, 1)

# Methods covering 50% of mass
methods_50 <- function(x) {
  if (is.table(x)) x <- as.numeric(x)
  x <- sort(x, decreasing = TRUE)
  p <- x / sum(x)
  cs <- cumsum(p)
  sum(cs <= 0.5) + 1
}

conc_table$Methods_50pct <- c(
  methods_50(l3_freq$freq_pre),
  methods_50(l3_freq$freq_post),
  methods_50(l3_freq$freq_qwen),
  methods_50(qwen |> filter(toupper(l3_mapping_consistent)=="TRUE", profile=="novice") |> pull(l3_mapping) |> table()),
  methods_50(qwen |> filter(toupper(l3_mapping_consistent)=="TRUE", profile=="intermediate") |> pull(l3_mapping) |> table()),
  methods_50(qwen |> filter(toupper(l3_mapping_consistent)=="TRUE", profile=="expert") |> pull(l3_mapping) |> table()),
  methods_50(l3_freq$freq_gemma),
  methods_50(gemma_consistent |> filter(profile=="novice") |> pull(l3_mapping) |> table()),
  methods_50(gemma_consistent |> filter(profile=="intermediate") |> pull(l3_mapping) |> table()),
  methods_50(gemma_consistent |> filter(profile=="expert") |> pull(l3_mapping) |> table())
)

# Total recommendations
conc_table$Total_Recs <- c(
  sum(l3_freq$freq_pre), sum(l3_freq$freq_post),
  sum(l3_freq$freq_qwen),
  nrow(qwen |> filter(toupper(l3_mapping_consistent)=="TRUE", profile=="novice")),
  nrow(qwen |> filter(toupper(l3_mapping_consistent)=="TRUE", profile=="intermediate")),
  nrow(qwen |> filter(toupper(l3_mapping_consistent)=="TRUE", profile=="expert")),
  sum(l3_freq$freq_gemma),
  nrow(gemma_consistent |> filter(profile=="novice")),
  nrow(gemma_consistent |> filter(profile=="intermediate")),
  nrow(gemma_consistent |> filter(profile=="expert"))
)

cat("\n=== Concentration comparison ===\n")
print(conc_table)

write.csv(conc_table, file.path(COMP_DIR, "concentration_comparison.csv"), row.names = FALSE)

# ── C3: Concentration bar chart ──────────────────────────────────────────────

conc_plot_df <- conc_table |>
  filter(grepl("novice|intermediate|expert|overall|literature", Distribution, ignore.case = TRUE)) |>
  mutate(
    model = case_when(
      grepl("Pre-2023", Distribution)  ~ "Literature",
      grepl("Post-2023", Distribution) ~ "Literature",
      grepl("Qwen", Distribution)      ~ "Qwen3",
      grepl("Gemma", Distribution)     ~ "Gemma"
    ),
    Distribution = factor(Distribution, levels = rev(conc_table$Distribution))
  )

plot_c3 <- ggplot(conc_plot_df, aes(x = Inv_Simpson, y = Distribution, fill = model)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = round(Inv_Simpson, 1)), hjust = -0.1, size = 3) +
  scale_fill_manual(values = c(
    "Literature" = "#56B4E9", "Qwen3" = "#E69F00", "Gemma" = "#CC79A7"
  )) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Effective method count (Inverse Simpson index)",
    subtitle = "Both LLMs are dramatically more concentrated than the literature",
    x = "Effective methods", y = NULL, fill = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(COMP_DIR, "plot_concentration_comparison.png"), plot_c3,
       width = 9, height = 6, dpi = 200, bg = "white")
cat("C3 (Concentration comparison) saved.\n")

# ── C4: Top 10 per model — divergence chart ─────────────────────────────────

top10_qwen  <- cross |> slice_max(n_qwen, n = 10) |> pull(l3)
top10_gemma <- cross |> slice_max(n_gemma, n = 10) |> pull(l3)
top_union   <- unique(c(top10_qwen, top10_gemma))

cross_top <- cross |>
  filter(l3 %in% top_union) |>
  mutate(
    share_qwen  = n_qwen / sum(cross$n_qwen),
    share_gemma = n_gemma / sum(cross$n_gemma),
    l3_short = factor(l3_short, levels = rev(l3_short[order(share_qwen + share_gemma)]))
  ) |>
  pivot_longer(cols = c(share_qwen, share_gemma),
               names_to = "model", values_to = "share") |>
  mutate(model = recode(model, share_qwen = "Qwen3", share_gemma = "Gemma"))

plot_c4 <- ggplot(cross_top, aes(x = share, y = l3_short, fill = model)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  scale_fill_manual(values = c("Qwen3" = "#E69F00", "Gemma" = "#CC79A7")) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 0.1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Top recommended L3 methods: Qwen3 vs Gemma",
    subtitle = "Union of each model's top 10. Share of total recommendations.",
    x = "Share of total recommendations", y = NULL, fill = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom")

ggsave(file.path(COMP_DIR, "plot_top10_qwen_vs_gemma.png"), plot_c4,
       width = 10, height = 7, dpi = 200, bg = "white")
cat("C4 (Top 10 divergence) saved.\n")

# ── Summary stats for Results.md ─────────────────────────────────────────────

cat("\n=== GEMMA EXPERIMENT SUMMARY ===\n")
cat("Total rows:", nrow(gemma), "\n")
cat("Consistent mappings:", nrow(gemma_consistent), "\n")
cat("L3 methods with >= 1 rec:", sum(joined_gemma$n_recommended_total > 0), "\n")
cat("Distinct L3 covered:", length(unique(gemma_consistent$l3_mapping)), "\n")

cat("\nPer profile:\n")
for (prof in c("novice", "intermediate", "expert")) {
  sub <- gemma_consistent |> filter(profile == prof)
  cat(sprintf("  %s: %d recs, %d distinct L3\n",
              prof, nrow(sub), length(unique(sub$l3_mapping))))
}

cat("\nSpearman rho (L3 freq: Qwen vs Gemma):",
    round(cor(cross$n_qwen, cross$n_gemma, method = "spearman"), 3), "\n")

# Top 10 Gemma with gamma
cat("\nGemma top 10 L3 with gamma:\n")
top10_info <- joined_gemma |>
  filter(n_recommended_total > 0) |>
  arrange(desc(n_recommended_total)) |>
  head(10) |>
  select(l3, n_recommended_total, mean_gamma, sig90)
print(top10_info, n = 10)

cat("\nAll Gemma graphs saved to:", OUT_DIR, "\n")
cat("Comparison graphs saved to:", COMP_DIR, "\n")
