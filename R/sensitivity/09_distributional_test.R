# 09_distributional_test.R
# Distributional comparison: does the LLM recommendation vector resemble the
# post-2023 method mix more than the pre-2023 mix?
#
# Instead of regressing on noisy individual gammas, we compare whole frequency
# distributions using cosine similarity and KL divergence. If LLMs are driving
# convergence, their recommendations should look more like the post-2023
# literature than the pre-2023 literature.
#
# We also run a permutation test to assess whether the observed similarity
# difference is larger than expected by chance.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(ggplot2)
})

# ── 1. Paths ─────────────────────────────────────────────────────────────────

STAN_DATA_RDS  <- here("data/output/stan_data.rds")
VOCAB_RDS      <- here("data/output/vocab.rds")
REMAPPED_TABLE <- here("data/output/step3_remapped_joined.csv")

OUT_DIR <- here("data/output/figures/distributional")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
OUT_RESULTS_MD <- here("docs/distributional_test_results.md")

# ── 2. Build frequency vectors ──────────────────────────────────────────────

stan_data <- readRDS(STAN_DATA_RDS)
vocab     <- readRDS(VOCAB_RDS)

l3_vocab    <- vocab$l3_vocab
year_levels <- vocab$year_levels
N_groups    <- stan_data$N_groups
N_years     <- stan_data$N_years
K_g         <- stan_data$K_g

pre_idx  <- which(year_levels < 2023)
post_idx <- which(year_levels >= 2023)
cat("Pre-LLM years:", year_levels[pre_idx], "\n")
cat("Post-LLM years:", year_levels[post_idx], "\n")

# Flatten counts array to L3-level frequency vectors
# counts[g, t, k] → sum over years for pre/post, then concatenate across groups
l3_methods <- l3_vocab |> arrange(g, k_local)

freq_pre  <- numeric(nrow(l3_methods))
freq_post <- numeric(nrow(l3_methods))

row_idx <- 0
for (g in seq_len(N_groups)) {
  K <- K_g[g]
  for (k in seq_len(K)) {
    row_idx <- row_idx + 1
    freq_pre[row_idx]  <- sum(stan_data$counts[g, pre_idx, k])
    freq_post[row_idx] <- sum(stan_data$counts[g, post_idx, k])
  }
}

# LLM recommendation vector (from remapped experiment)
rec_table <- read.csv(REMAPPED_TABLE)
rec_vec <- setNames(rec_table$n_recommended_total, rec_table$l3)
freq_llm <- rec_vec[l3_methods$l3]
freq_llm[is.na(freq_llm)] <- 0

# Also build profile-specific LLM vectors
rec_novice  <- setNames(rec_table$n_recommended_novice, rec_table$l3)
rec_inter   <- setNames(rec_table$n_recommended_intermediate, rec_table$l3)
rec_expert  <- setNames(rec_table$n_recommended_expert, rec_table$l3)
freq_llm_novice  <- rec_novice[l3_methods$l3]; freq_llm_novice[is.na(freq_llm_novice)] <- 0
freq_llm_inter   <- rec_inter[l3_methods$l3];  freq_llm_inter[is.na(freq_llm_inter)] <- 0
freq_llm_expert  <- rec_expert[l3_methods$l3];  freq_llm_expert[is.na(freq_llm_expert)] <- 0

cat("\nFrequency vector lengths:", length(freq_pre), length(freq_post), length(freq_llm), "\n")
cat("Total papers pre:", sum(freq_pre), "  post:", sum(freq_post), "\n")
cat("Total LLM recs:", sum(freq_llm), "\n")

# ── 3. Similarity metrics ───────────────────────────────────────────────────

# Normalise to proportions
to_prop <- function(x) {
  s <- sum(x)
  if (s == 0) return(rep(0, length(x)))
  x / s
}

cosine_sim <- function(a, b) {
  sum(a * b) / (sqrt(sum(a^2)) * sqrt(sum(b^2)))
}

kl_divergence <- function(p, q, epsilon = 1e-10) {
  p <- p + epsilon
  q <- q + epsilon
  p <- p / sum(p)
  q <- q / sum(q)
  sum(p * log(p / q))
}

# Hellinger distance (bounded [0,1], symmetric)
hellinger <- function(p, q) {
  p <- to_prop(p)
  q <- to_prop(q)
  sqrt(sum((sqrt(p) - sqrt(q))^2) / 2)
}

prop_pre  <- to_prop(freq_pre)
prop_post <- to_prop(freq_post)
prop_llm  <- to_prop(freq_llm)

# Cosine similarity
cos_llm_pre  <- cosine_sim(freq_llm, freq_pre)
cos_llm_post <- cosine_sim(freq_llm, freq_post)
cos_pre_post <- cosine_sim(freq_pre, freq_post)

# KL divergence (LLM || reference)
kl_llm_pre  <- kl_divergence(prop_llm, prop_pre)
kl_llm_post <- kl_divergence(prop_llm, prop_post)

# Hellinger distance
hel_llm_pre  <- hellinger(freq_llm, freq_pre)
hel_llm_post <- hellinger(freq_llm, freq_post)

cat("\n=== Distributional similarity (overall) ===\n")
cat(sprintf("Cosine(LLM, pre):   %.4f\n", cos_llm_pre))
cat(sprintf("Cosine(LLM, post):  %.4f\n", cos_llm_post))
cat(sprintf("Cosine(pre, post):  %.4f\n", cos_pre_post))
cat(sprintf("KL(LLM || pre):     %.4f\n", kl_llm_pre))
cat(sprintf("KL(LLM || post):    %.4f\n", kl_llm_post))
cat(sprintf("Hellinger(LLM, pre):  %.4f\n", hel_llm_pre))
cat(sprintf("Hellinger(LLM, post): %.4f\n", hel_llm_post))

delta_cos <- cos_llm_post - cos_llm_pre
delta_kl  <- kl_llm_pre - kl_llm_post  # positive = closer to post
delta_hel <- hel_llm_pre - hel_llm_post  # positive = closer to post
cat(sprintf("\nDelta cosine (post - pre):     %+.4f  [positive = LLM closer to post]\n", delta_cos))
cat(sprintf("Delta KL (pre - post):         %+.4f  [positive = LLM closer to post]\n", delta_kl))
cat(sprintf("Delta Hellinger (pre - post):  %+.4f  [positive = LLM closer to post]\n", delta_hel))

# ── 4. By-profile comparison ────────────────────────────────────────────────

profile_results <- data.frame(
  profile = character(),
  cos_pre = numeric(), cos_post = numeric(), delta_cos = numeric(),
  kl_pre = numeric(), kl_post = numeric(), delta_kl = numeric(),
  hel_pre = numeric(), hel_post = numeric(), delta_hel = numeric(),
  stringsAsFactors = FALSE
)

for (pname in c("overall", "novice", "intermediate", "expert")) {
  fv <- switch(pname,
    overall = freq_llm,
    novice = freq_llm_novice,
    intermediate = freq_llm_inter,
    expert = freq_llm_expert
  )
  pv <- to_prop(fv)
  profile_results <- rbind(profile_results, data.frame(
    profile   = pname,
    cos_pre   = cosine_sim(fv, freq_pre),
    cos_post  = cosine_sim(fv, freq_post),
    delta_cos = cosine_sim(fv, freq_post) - cosine_sim(fv, freq_pre),
    kl_pre    = kl_divergence(pv, prop_pre),
    kl_post   = kl_divergence(pv, prop_post),
    delta_kl  = kl_divergence(pv, prop_pre) - kl_divergence(pv, prop_post),
    hel_pre   = hellinger(fv, freq_pre),
    hel_post  = hellinger(fv, freq_post),
    delta_hel = hellinger(fv, freq_pre) - hellinger(fv, freq_post),
    stringsAsFactors = FALSE
  ))
}

cat("\n=== By-profile results ===\n")
print(profile_results |> select(profile, cos_pre, cos_post, delta_cos, hel_pre, hel_post, delta_hel))

# ── 5. Permutation test ─────────────────────────────────────────────────────

set.seed(42)
N_PERM <- 10000

cat(sprintf("\nRunning %d permutations...\n", N_PERM))

# Under the null, the LLM recommendation vector is unrelated to pre/post
# distinction. We permute the assignment of years to pre/post and recompute
# the delta cosine.
all_years <- seq_len(N_years)
n_post <- length(post_idx)

perm_delta_cos <- numeric(N_PERM)
perm_delta_hel <- numeric(N_PERM)

for (p in seq_len(N_PERM)) {
  # Randomly assign years to "post"
  perm_post <- sample(all_years, n_post)
  perm_pre  <- setdiff(all_years, perm_post)

  perm_freq_pre  <- numeric(nrow(l3_methods))
  perm_freq_post <- numeric(nrow(l3_methods))
  row_idx <- 0
  for (g in seq_len(N_groups)) {
    K <- K_g[g]
    for (k in seq_len(K)) {
      row_idx <- row_idx + 1
      perm_freq_pre[row_idx]  <- sum(stan_data$counts[g, perm_pre, k])
      perm_freq_post[row_idx] <- sum(stan_data$counts[g, perm_post, k])
    }
  }

  perm_delta_cos[p] <- cosine_sim(freq_llm, perm_freq_post) -
                        cosine_sim(freq_llm, perm_freq_pre)
  perm_delta_hel[p] <- hellinger(freq_llm, perm_freq_pre) -
                        hellinger(freq_llm, perm_freq_post)
}

# p-value: fraction of permutations with delta >= observed
# (one-sided: we test whether LLM is closer to post than expected by chance)
p_cos <- mean(perm_delta_cos >= delta_cos)
p_hel <- mean(perm_delta_hel >= delta_hel)

cat(sprintf("\nPermutation test (N=%d):\n", N_PERM))
cat(sprintf("  Observed delta cosine: %+.4f, p = %.4f\n", delta_cos, p_cos))
cat(sprintf("  Observed delta Hellinger: %+.4f, p = %.4f\n", delta_hel, p_hel))

# ── 6. Plots ─────────────────────────────────────────────────────────────────

# Plot A: permutation distribution with observed value
perm_df <- data.frame(delta = perm_delta_cos)

pA <- ggplot(perm_df, aes(x = delta)) +
  geom_histogram(bins = 80, fill = "grey70", colour = "grey50", linewidth = 0.2) +
  geom_vline(xintercept = delta_cos, colour = "firebrick", linewidth = 0.8) +
  annotate("text", x = delta_cos, y = Inf, vjust = 2, hjust = -0.1,
           label = sprintf("observed = %+.4f\np = %.3f", delta_cos, p_cos),
           colour = "firebrick", size = 3.5) +
  labs(x = "Delta cosine similarity (post - pre)",
       y = "Permutation count",
       title = "Is the LLM closer to post-2023 literature than pre-2023?",
       subtitle = sprintf("Permutation test (N = %d): randomly shuffle year→pre/post assignment", N_PERM)) +
  theme_minimal(base_size = 11)

ggsave(file.path(OUT_DIR, "plot_permutation_cosine.png"), pA,
       width = 7, height = 5, units = "in", dpi = 150)

# Plot B: bar chart comparing similarities
bar_df <- data.frame(
  comparison = rep(c("LLM vs Pre-2023", "LLM vs Post-2023"), 3),
  metric     = rep(c("Cosine similarity", "1 - Hellinger distance", "1 / KL divergence"), each = 2),
  value      = c(cos_llm_pre, cos_llm_post,
                 1 - hel_llm_pre, 1 - hel_llm_post,
                 1/kl_llm_pre, 1/kl_llm_post)
)

pB <- ggplot(bar_df |> filter(metric == "Cosine similarity"),
             aes(x = comparison, y = value, fill = comparison)) +
  geom_col(width = 0.6) +
  scale_fill_manual(values = c("LLM vs Pre-2023" = "steelblue", "LLM vs Post-2023" = "firebrick")) +
  labs(x = NULL, y = "Cosine similarity",
       title = "LLM recommendations: closer to pre- or post-2023 literature?",
       subtitle = "Higher = more similar distribution of method frequencies") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none") +
  coord_cartesian(ylim = c(0, 1))

ggsave(file.path(OUT_DIR, "plot_cosine_comparison.png"), pB,
       width = 6, height = 5, units = "in", dpi = 150)

# Plot C: by-profile cosine comparison
prof_long <- profile_results |>
  select(profile, cos_pre, cos_post) |>
  tidyr::pivot_longer(cols = c(cos_pre, cos_post),
                      names_to = "period", values_to = "cosine") |>
  mutate(
    period = ifelse(period == "cos_pre", "Pre-2023", "Post-2023"),
    profile = factor(profile, levels = c("overall", "novice", "intermediate", "expert"))
  )

pC <- ggplot(prof_long, aes(x = profile, y = cosine, fill = period)) +
  geom_col(position = "dodge", width = 0.6) +
  scale_fill_manual(values = c("Pre-2023" = "steelblue", "Post-2023" = "firebrick")) +
  labs(x = "Expertise profile", y = "Cosine similarity", fill = NULL,
       title = "LLM similarity to pre/post-2023 literature by expertise profile") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top") +
  coord_cartesian(ylim = c(0, 1))

ggsave(file.path(OUT_DIR, "plot_cosine_by_profile.png"), pC,
       width = 7, height = 5, units = "in", dpi = 150)

cat("\nPlots saved to:", OUT_DIR, "\n")

# ── 7. Generate results markdown ─────────────────────────────────────────────

direction_cos <- ifelse(delta_cos > 0, "post-2023 (supports mean-collapse)",
                        "pre-2023 (does not support mean-collapse)")
direction_hel <- ifelse(delta_hel > 0, "post-2023", "pre-2023")

md <- c(
  "# Distributional Test — LLM Recommendations vs. Pre/Post-2023 Literature",
  "",
  sprintf("Script: `R/sensitivity/09_distributional_test.R`  "),
  sprintf("Run date: %s", Sys.Date()),
  "",
  "---",
  "",
  "## Design",
  "",
  "Instead of regressing recommendation counts on noisy individual gammas (Step 3),",
  "this test compares whole frequency distributions. For each of the 242 L3 methods,",
  "we compute three vectors:",
  "",
  sprintf("- **Pre-2023 literature** — total paper counts 2010–2022 (%d papers)", sum(freq_pre)),
  sprintf("- **Post-2023 literature** — total paper counts 2023–2026 (%d papers)", sum(freq_post)),
  sprintf("- **LLM recommendations** — Qwen3 recommendation counts from the prompting experiment (%d recommendations, remapped to v3 taxonomy)", sum(freq_llm)),
  "",
  "If LLMs are driving convergence, their recommendation distribution should resemble",
  "the post-2023 literature more than the pre-2023 literature. We measure similarity",
  "using cosine similarity, Hellinger distance, and KL divergence.",
  "",
  "---",
  "",
  "## Results",
  "",
  "### Overall similarity",
  "",
  "| Metric | LLM vs Pre-2023 | LLM vs Post-2023 | Delta | Direction |",
  "|---|---|---|---|---|",
  sprintf("| Cosine similarity | %.4f | %.4f | %+.4f | %s |",
          cos_llm_pre, cos_llm_post, delta_cos, direction_cos),
  sprintf("| Hellinger distance | %.4f | %.4f | %+.4f | %s |",
          hel_llm_pre, hel_llm_post, -delta_hel,
          ifelse(delta_hel > 0, "Closer to post", "Closer to pre")),
  sprintf("| KL divergence | %.4f | %.4f | %+.4f | %s |",
          kl_llm_pre, kl_llm_post, -(delta_kl),
          ifelse(delta_kl > 0, "Closer to post", "Closer to pre")),
  "",
  "*For cosine: higher = more similar. For Hellinger/KL: lower = more similar.*",
  "",
  "### By expertise profile",
  "",
  "| Profile | Cosine(LLM, Pre) | Cosine(LLM, Post) | Delta |",
  "|---|---|---|---|",
  sprintf("| Overall | %.4f | %.4f | %+.4f |",
          profile_results$cos_pre[1], profile_results$cos_post[1], profile_results$delta_cos[1]),
  sprintf("| Novice | %.4f | %.4f | %+.4f |",
          profile_results$cos_pre[2], profile_results$cos_post[2], profile_results$delta_cos[2]),
  sprintf("| Intermediate | %.4f | %.4f | %+.4f |",
          profile_results$cos_pre[3], profile_results$cos_post[3], profile_results$delta_cos[3]),
  sprintf("| Expert | %.4f | %.4f | %+.4f |",
          profile_results$cos_pre[4], profile_results$cos_post[4], profile_results$delta_cos[4]),
  "",
  sprintf("### Permutation test (N = %s)", format(N_PERM, big.mark = ",")),
  "",
  "Under the null hypothesis, the LLM recommendation vector is unrelated to the",
  "pre/post-2023 distinction. We randomly shuffle which years are assigned to",
  sprintf("'post' (keeping the same number of post years = %d) and recompute the", n_post),
  "delta cosine similarity each time.",
  "",
  sprintf("- **Observed delta cosine:** %+.4f", delta_cos),
  sprintf("- **Permutation p-value:** %.4f", p_cos),
  sprintf("- **Observed delta Hellinger:** %+.4f", delta_hel),
  sprintf("- **Permutation p-value:** %.4f", p_hel),
  "",
  "---",
  "",
  "## Plots",
  "",
  "### Permutation distribution",
  "",
  "![Permutation](../data/output/figures/distributional/plot_permutation_cosine.png)",
  "",
  "### Cosine similarity comparison",
  "",
  "![Cosine](../data/output/figures/distributional/plot_cosine_comparison.png)",
  "",
  "### By-profile comparison",
  "",
  "![Profile](../data/output/figures/distributional/plot_cosine_by_profile.png)",
  "",
  "---",
  "",
  "## Interpretation",
  "",
  "*(Auto-generated; update after reviewing results.)*"
)

writeLines(md, OUT_RESULTS_MD)
cat("Results saved to:", OUT_RESULTS_MD, "\n")

cat("\n09_distributional_test.R complete.\n")
