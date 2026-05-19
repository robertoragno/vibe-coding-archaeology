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

EXPERIMENT_CSV <- here("experiment/analysis/experiment_results.csv")
REMAPPED_CSV   <- here("data/output/step3_remapped_joined.csv")
GAMMA_CSV      <- here("data/output/phi_free/gamma_results.csv")
STAN_DATA_RDS  <- here("data/output/stan_data.rds")
VOCAB_RDS      <- here("data/output/vocab.rds")

OUT_DIR <- here("data/output/figures/exploratory")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ── Load data ────────────────────────────────────────────────────────────────

experiment <- read.csv(EXPERIMENT_CSV)
remapped   <- read.csv(REMAPPED_CSV)
gamma_df   <- read.csv(GAMMA_CSV)
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

# ── G2: Top 20 L3 methods with gamma coloring (remapped) ────────────────────

rec_gamma <- remapped |>
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
    title = "Top 20 recommended L3 methods (remapped, 205/242 match)",
    subtitle = expression("Bar colour = signed posterior mean" ~ gamma ~ "(red = gaining post-2023, blue = declining)"),
    x = "Total recommendations", y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "plot_top20_l3_remapped.png"), plot_g2,
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

rec_vec <- setNames(remapped$n_recommended_total, remapped$l3)
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

# ── G4: L2-level scatter (LLM share vs post-2023 shift) ─────────────────────

spearman_l2 <- cor.test(l2_agg$delta, l2_agg$share_llm, method = "spearman",
                        exact = FALSE)
rho_l2 <- spearman_l2$estimate
p_l2   <- spearman_l2$p.value

plot_g4 <- ggplot(l2_agg, aes(x = delta, y = share_llm)) +
  geom_point(size = 3, colour = "#0072B2") +
  geom_smooth(method = "lm", se = TRUE, colour = "grey40", linewidth = 0.7) +
  geom_text_repel(aes(label = l2_short), size = 2.8, max.overlaps = 25) +
  annotate("text", x = Inf, y = Inf,
           label = sprintf("Spearman rho = %.3f\np = %.3f", rho_l2, p_l2),
           hjust = 1.1, vjust = 1.5, size = 3.5) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  labs(
    title = "L2-level: LLM recommendation share vs. post-2023 literature shift",
    subtitle = "Each point = one of 25 L2 sub-disciplines",
    x = "Post-2023 share minus pre-2023 share",
    y = "LLM recommendation share"
  ) +
  theme_minimal(base_size = 11)

ggsave(file.path(OUT_DIR, "plot_l2_scatter.png"), plot_g4,
       width = 8, height = 6, dpi = 200, bg = "white")
cat("G4 saved.\n")

# ── G5: Spearman rank correlation L3 (permutation) ──────────────────────────
# L2-level gamma aggregation is not meaningful: L3 gammas are compositional
# within each L2 group, so their weighted mean is near-zero by construction.
# The valid L2-level test is G4 (delta share vs LLM share).

gamma_vec <- setNames(gamma_df$mean_gamma, gamma_df$l3)

l3_for_corr <- l3_freq |>
  mutate(mean_gamma = gamma_vec[l3]) |>
  filter(!is.na(mean_gamma))

spearman_l3 <- cor.test(l3_for_corr$mean_gamma, l3_for_corr$freq_llm,
                        method = "spearman", exact = FALSE)

set.seed(42)
n_perm <- 10000
perm_l3 <- replicate(n_perm, {
  cor(sample(l3_for_corr$mean_gamma), l3_for_corr$freq_llm, method = "spearman")
})

perm_df <- tibble(rho = perm_l3)
obs_rho <- spearman_l3$estimate

plot_g5 <- ggplot(perm_df, aes(x = rho)) +
  geom_histogram(bins = 60, fill = "grey70", colour = "grey50") +
  geom_vline(xintercept = obs_rho, colour = "#D55E00", linewidth = 1) +
  annotate("text", x = obs_rho, y = Inf,
           label = sprintf("rho = %.3f", obs_rho),
           vjust = 2, hjust = -0.1, colour = "#D55E00", size = 3.5) +
  labs(
    title = "L3-level Spearman rank correlation: LLM recommendation count vs. mean gamma",
    subtitle = "Grey = permutation null (10,000 shuffles); red line = observed (242 methods)",
    x = expression("Spearman" ~ rho), y = "Count"
  ) +
  theme_minimal(base_size = 11)

ggsave(file.path(OUT_DIR, "plot_rank_correlation.png"), plot_g5,
       width = 7, height = 5, dpi = 200, bg = "white")
cat("G5 saved.\n")

# ── Summary stats ────────────────────────────────────────────────────────────

cat("\n=== Summary ===\n")
cat(sprintf("L3-level Spearman: rho = %.3f, p = %.3f\n",
            spearman_l3$estimate, spearman_l3$p.value))
cat(sprintf("L2-level Spearman (delta share vs LLM share): rho = %.3f, p = %.3f\n",
            rho_l2, p_l2))
cat(sprintf("L3 permutation p (one-sided, rho >= obs): %.4f\n",
            mean(perm_l3 >= spearman_l3$estimate)))

cat("\nAll graphs saved to:", OUT_DIR, "\n")
