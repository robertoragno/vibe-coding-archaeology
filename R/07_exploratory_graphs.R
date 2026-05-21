# 07_exploratory_graphs.R
# Descriptive exploratory graphs of LLM experiment recommendations.
# No Stan model — runs in seconds. Produces graphs for experiment/Results.md.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggrepel)
})

# ── Paths ────────────────────────────────────────────────────────────────────

EXPERIMENT_CSV <- here("experiment/analysis/experiment_results_QWEN.csv")
JOINED_CSV     <- here("data/output/step3_joined_table.csv")
GAMMA_CSV      <- here("data/output/phi_free/gamma_results.csv")
BETA_CSV       <- here("data/output/phi_free/beta_results.csv")
STAN_DATA_RDS  <- here("data/output/stan_data.rds")
VOCAB_RDS      <- here("data/output/vocab.rds")

OUT_DIR <- here("data/output/figures/exploratory")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ── Load data ────────────────────────────────────────────────────────────────

experiment <- read.csv(EXPERIMENT_CSV)
joined   <- read.csv(JOINED_CSV)
gamma_df   <- read.csv(GAMMA_CSV)
beta_df    <- read.csv(BETA_CSV)
stan_data  <- readRDS(STAN_DATA_RDS)
vocab      <- readRDS(VOCAB_RDS)

# ── G1: Top 20 L4 methods recommended ────────────────────────────────────────

collapse_l4 <- function(x) {
  x <- trimws(x)
  x <- gsub("\\s*\\([^)]*\\)", "", x)          # strip parenthetical abbreviations
  x <- gsub("\\s+with\\s+.*$", "", x)           # strip "with ..." suffixes
  x <- gsub("^(agent-based\\s+){2,}", "Agent-Based ", x, ignore.case = TRUE)
  x <- gsub("\\s+", " ", x)
  x <- tools::toTitleCase(tolower(x))
  x
}

l4_raw <- experiment |>
  filter(l4_method != "") |>
  mutate(l4_clean = collapse_l4(l4_method)) |>
  count(l4_clean, profile, name = "n") |>
  group_by(l4_clean) |>
  mutate(total = sum(n)) |>
  ungroup()

top20_l4 <- l4_raw |>
  distinct(l4_clean, total) |>
  slice_max(total, n = 20) |>
  pull(l4_clean)

plot_g1 <- l4_raw |>
  filter(l4_clean %in% top20_l4) |>
  mutate(
    l4_clean = factor(l4_clean, levels = rev(
      l4_raw |> distinct(l4_clean, total) |>
        filter(l4_clean %in% top20_l4) |>
        arrange(total) |> pull(l4_clean)
    )),
    profile = factor(profile, levels = c("novice", "intermediate", "expert"))
  ) |>
  ggplot(aes(x = n, y = l4_clean, fill = profile)) +
  geom_col() +
  scale_fill_manual(values = c(novice = "#E69F00", intermediate = "#56B4E9", expert = "#009E73")) +
  labs(
    title = "Top 20 L4 methods recommended by Qwen3",
    x = "Number of recommendations", y = NULL, fill = "Profile"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "plot_top20_l4.png"), plot_g1,
       width = 8, height = 6, dpi = 200, bg = "white")
cat("G1 saved.\n")

# ── G2: Top 20 L3 methods with gamma coloring (joined) ────────────────────

rec_gamma <- joined |>
  filter(n_recommended_total > 0) |>
  arrange(desc(n_recommended_total)) |>
  head(20) |>
  mutate(
    l3_short = sub("^L3-\\d+: ", "", l3),
    l3_short = factor(l3_short, levels = rev(l3_short))
  )

gamma_range <- max(abs(rec_gamma$mean_gamma))

plot_g2 <- ggplot(rec_gamma, aes(x = n_recommended_total, y = l3_short, fill = mean_gamma)) +
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
    title = "Top 20 recommended L3 methods (194/242 matched)",
    subtitle = expression("Bar colour = signed posterior mean" ~ gamma ~ "(red = gaining post-2023, blue = declining)"),
    x = "Total recommendations", y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "plot_top20_l3.png"), plot_g2,
       width = 9, height = 6, dpi = 200, bg = "white")
cat("G2 saved.\n")

# ── Build L2-level frequency vectors ────────────────────────────────────────

l3_vocab    <- vocab$l3_vocab |> arrange(g, k_local)
year_levels <- vocab$year_levels
N_groups    <- stan_data$N_groups
K_g         <- stan_data$K_g

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

rec_vec <- setNames(joined$n_recommended_total, joined$l3)
l3_freq$freq_llm <- rec_vec[l3_freq$l3]
l3_freq$freq_llm[is.na(l3_freq$freq_llm)] <- 0

l2_agg <- l3_freq |>
  group_by(l2) |>
  summarise(
    freq_pre  = sum(freq_pre),
    freq_post = sum(freq_post),
    freq_llm  = sum(freq_llm),
    .groups = "drop"
  ) |>
  mutate(
    share_pre  = freq_pre  / sum(freq_pre),
    share_post = freq_post / sum(freq_post),
    share_llm  = freq_llm  / sum(freq_llm),
    delta      = share_post - share_pre,
    l2_short   = sub("^L2-\\d+: ", "", l2)
  )

cat("\nL2-level aggregation:\n")
cat("Total papers pre:", sum(l2_agg$freq_pre),
    " post:", sum(l2_agg$freq_post),
    " LLM recs:", sum(l2_agg$freq_llm), "\n")

# ── G3: L2-level triple bar chart ────────────────────────────────────────────

l2_long <- l2_agg |>
  select(l2_short, share_pre, share_post, share_llm) |>
  pivot_longer(cols = starts_with("share_"),
               names_to = "source", values_to = "share") |>
  mutate(source = recode(source,
    share_pre  = "Pre-2023 literature",
    share_post = "Post-2023 literature",
    share_llm  = "LLM recommendations"
  ))

l2_order <- l2_agg |> arrange(share_llm) |> pull(l2_short)
l2_long$l2_short <- factor(l2_long$l2_short, levels = l2_order)
l2_long$source <- factor(l2_long$source,
  levels = c("LLM recommendations", "Post-2023 literature", "Pre-2023 literature"))

plot_g3 <- ggplot(l2_long, aes(x = share, y = l2_short, fill = source)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.65) +
  scale_fill_manual(values = c(
    "LLM recommendations"  = "#E69F00",
    "Post-2023 literature" = "#D55E00",
    "Pre-2023 literature"  = "#56B4E9"
  )) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Method share by L2 sub-discipline",
    subtitle = "LLM recommendations vs. pre/post-2023 published literature",
    x = "Share of total", y = NULL, fill = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "plot_l2_triple_bar.png"), plot_g3,
       width = 10, height = 8, dpi = 200, bg = "white")
cat("G3 saved.\n")

# ── G4: Pre-existing trend vs post-2023 excess (two-panel L3 scatter) ────────
# The key confound: does the LLM recommend methods that were already growing
# (positive beta) rather than methods that specifically accelerated post-2023
# (positive gamma)? This two-panel scatter separates the two.

gamma_vec <- setNames(gamma_df$mean_gamma, gamma_df$l3)
beta_vec  <- setNames(beta_df$mean_beta, beta_df$l3)

l3_combined <- l3_freq |>
  mutate(
    mean_gamma = gamma_vec[l3],
    mean_beta  = beta_vec[l3],
    log_llm    = log1p(freq_llm)
  ) |>
  filter(!is.na(mean_gamma), !is.na(mean_beta))

scatter_long <- l3_combined |>
  filter(freq_llm > 0) |>
  select(l3, l2, freq_llm, mean_beta, mean_gamma) |>
  pivot_longer(cols = c(mean_beta, mean_gamma),
               names_to = "parameter", values_to = "value") |>
  mutate(
    parameter = recode(parameter,
      mean_beta  = "beta (pre-existing trend 2010-2022)",
      mean_gamma = "gamma (post-2023 excess above trend)"
    ),
    l3_short = sub("^L3-\\d+: ", "", l3)
  )

top_labels <- l3_combined |>
  filter(freq_llm > 0) |>
  slice_max(freq_llm, n = 10) |>
  pull(l3)

scatter_long <- scatter_long |>
  mutate(show_label = l3 %in% top_labels)

plot_g4 <- ggplot(scatter_long, aes(x = value, y = freq_llm)) +
  geom_point(alpha = 0.5, size = 2, colour = "#0072B2") +
  geom_text_repel(
    data = filter(scatter_long, show_label),
    aes(label = l3_short), size = 2.5, max.overlaps = 15,
    segment.alpha = 0.3
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
  facet_wrap(~parameter, scales = "free_x") +
  scale_y_log10() +
  labs(
    title = "Were the recommended methods already growing before LLMs?",
    subtitle = "Each point = one L3 method with >= 1 recommendation (log scale). Left: pre-existing trend; right: post-2023 excess.",
    x = "Posterior mean", y = "LLM recommendation count (log scale)"
  ) +
  theme_minimal(base_size = 11) +
  theme(strip.text = element_text(size = 10, face = "bold"))

ggsave(file.path(OUT_DIR, "plot_beta_gamma_scatter.png"), plot_g4,
       width = 12, height = 6, dpi = 200, bg = "white")
cat("G4 saved.\n")

# ── LLM concentration stats (no plot — diversity trajectory already in ────────
# docs/l2_l3_results.md via the primary model's posterior inv_simpson).
# We just compute the LLM-side numbers for the Results.md table.

inv_simpson <- function(x) {
  p <- x / sum(x)
  p <- p[p > 0]
  1 / sum(p^2)
}

rec_novice  <- setNames(joined$n_recommended_novice, joined$l3)
rec_inter   <- setNames(joined$n_recommended_intermediate, joined$l3)
rec_expert  <- setNames(joined$n_recommended_expert, joined$l3)

freq_novice  <- rec_novice[l3_vocab$l3];  freq_novice[is.na(freq_novice)] <- 0
freq_inter   <- rec_inter[l3_vocab$l3];   freq_inter[is.na(freq_inter)] <- 0
freq_expert  <- rec_expert[l3_vocab$l3];  freq_expert[is.na(freq_expert)] <- 0

cat("\n=== LLM recommendation concentration ===\n")
cat(sprintf("Overall:      %.1f effective methods\n", inv_simpson(l3_freq$freq_llm)))
cat(sprintf("Novice:       %.1f effective methods\n", inv_simpson(freq_novice)))
cat(sprintf("Intermediate: %.1f effective methods\n", inv_simpson(freq_inter)))
cat(sprintf("Expert:       %.1f effective methods\n", inv_simpson(freq_expert)))

cat("\nAll graphs saved to:", OUT_DIR, "\n")
