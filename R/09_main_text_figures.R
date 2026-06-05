# 09_main_text_figures.R
# Generates all 8 main-text figures in greyscale academic style.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(ggdist)
})

OUT_DIR <- here("data/output/figures/main_text")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ── Shared theme ────────────────────────────────────────────────────────────
theme_paper <- theme_classic(base_size = 11, base_family = "serif") +
  theme(
    axis.line         = element_line(colour = "black", linewidth = 0.3),
    axis.ticks        = element_line(colour = "black", linewidth = 0.3),
    axis.text         = element_text(colour = "black"),
    strip.background  = element_blank(),
    strip.text        = element_text(face = "bold", size = 9),
    plot.title        = element_text(face = "bold", size = 11),
    plot.subtitle     = element_text(size = 9, colour = "grey30"),
    plot.caption      = element_text(size = 8, colour = "grey30", hjust = 0),
    legend.position   = "top",
    legend.key.size   = unit(0.4, "cm"),
    plot.margin       = margin(8, 8, 8, 8)
  )

grey_fills <- c("grey20", "grey50", "grey80")

# ── Load shared data ────────────────────────────────────────────────────────
vocab     <- readRDS(here("data/output/vocab.rds"))
stan_data <- readRDS(here("data/output/stan_data.rds"))
l3_vocab  <- vocab$l3_vocab |> arrange(g, k_local)
year_levels <- vocab$year_levels

gamma_csv <- here("data/output/phi_free/gamma_results.csv")
gamma_df  <- read.csv(gamma_csv, stringsAsFactors = FALSE)

# ═══════════════════════════════════════════════════════════════════════════
# Fig. 1 — Raw method counts over time
# ═══════════════════════════════════════════════════════════════════════════

K <- nrow(l3_vocab)
counts_long <- data.frame()
for (g in seq_len(stan_data$N_groups)) {
  for (k in seq_len(stan_data$K_g[g])) {
    row_idx <- sum(stan_data$K_g[seq_len(g - 1)]) + k
    for (t in seq_len(stan_data$N_years)) {
      counts_long <- rbind(counts_long, data.frame(
        l3   = l3_vocab$l3[row_idx],
        year = year_levels[t],
        n    = stan_data$counts[g, t, k]
      ))
    }
  }
}

totals <- counts_long |>
  group_by(l3) |>
  summarise(total = sum(n), .groups = "drop") |>
  arrange(desc(total))

top15 <- totals$l3[1:15]

# Clean L3 labels
clean_l3 <- function(x) sub("^L3-[0-9]+: ", "", x)

plot_df1 <- counts_long |>
  filter(l3 %in% top15, year <= 2025) |>
  mutate(l3_clean = clean_l3(l3),
         l3_clean = stringr::str_wrap(l3_clean, width = 30),
         l3_clean = factor(l3_clean, levels = stringr::str_wrap(clean_l3(top15), width = 30)))

fig1 <- ggplot(plot_df1, aes(x = year, y = n)) +
  geom_line(colour = "grey30", linewidth = 0.5) +
  geom_point(size = 0.8, colour = "grey30") +
  geom_vline(xintercept = 2023, linetype = "dashed", linewidth = 0.3) +
  facet_wrap(~ l3_clean, scales = "free_y", ncol = 3) +
  labs(x = "Year", y = "Paper count",
       title = "Top 15 L3 methods: observed counts (2010–2025)",
       caption = "Dashed line: 2023 LLM adoption boundary.") +
  theme_paper +
  theme(strip.text = element_text(size = 6.5))

ggsave(file.path(OUT_DIR, "fig1_raw_counts.png"), fig1,
       width = 9, height = 11, dpi = 300, bg = "white")
cat("Fig. 1 saved.\n")

# ═══════════════════════════════════════════════════════════════════════════
# Fig. 2 — Sigma posteriors
# ═══════════════════════════════════════════════════════════════════════════

fit <- readRDS(here("data/output/fit_phi_free.rds"))
draws <- fit$draws(format = "draws_matrix")

sigma_df <- data.frame(
  value = c(as.numeric(draws[, "sigma_beta"]),
            as.numeric(draws[, "sigma_gamma"])),
  parameter = rep(c("σβ: pre-LLM baseline",
                    "σγ: post-2023 shift spread"),
                  each = nrow(draws))
)

fig2 <- ggplot(sigma_df, aes(x = value, y = after_stat(density))) +
  geom_histogram(fill = "grey60", colour = "black", linewidth = 0.2,
                 bins = 50, boundary = 0) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.3) +
  facet_wrap(~ parameter, scales = "free", ncol = 2) +
  scale_x_continuous(expand = expansion(mult = c(0.02, 0.05))) +
  labs(x = "Posterior value", y = "Density",
       title = "Method-level variation before and after 2023",
       caption = "Posterior entirely above zero for σγ indicates uneven post-2023 divergence across methods.") +
  theme_paper

ggsave(file.path(OUT_DIR, "fig2_sigma_posteriors.png"), fig2,
       width = 8, height = 3.5, dpi = 300, bg = "white")
cat("Fig. 2 saved.\n")

# ═══════════════════════════════════════════════════════════════════════════
# Fig. 3 — Method share by L2: literature vs both LLMs
# ═══════════════════════════════════════════════════════════════════════════

pre_idx  <- which(year_levels < 2023)
post_idx <- which(year_levels >= 2023 & year_levels <= 2025)

l2_shares <- data.frame()
for (g in seq_len(stan_data$N_groups)) {
  pre_total  <- sum(stan_data$counts[g, pre_idx, 1:stan_data$K_g[g]])
  post_total <- sum(stan_data$counts[g, post_idx, 1:stan_data$K_g[g]])
  l2_shares <- rbind(l2_shares, data.frame(
    l2 = vocab$l2_levels[g], pre = pre_total, post = post_total
  ))
}

qwen_raw <- read.csv(here("experiment/analysis/experiment_results_QWEN.csv"),
                      stringsAsFactors = FALSE)
qwen_con <- qwen_raw |> filter(toupper(as.character(l3_mapping_consistent)) == "TRUE")

gemma_raw <- read.csv(here("experiment/analysis/experiment_results_GEMMA.csv"),
                      stringsAsFactors = FALSE)
gemma_con <- gemma_raw |> filter(toupper(as.character(l3_mapping_consistent)) == "TRUE")

l3_to_l2 <- setNames(l3_vocab$l2, l3_vocab$l3)

qwen_con$l2 <- l3_to_l2[qwen_con$l3_mapping]
qwen_l2 <- qwen_con |> filter(!is.na(l2)) |> count(l2, name = "qwen")

gemma_con$l2 <- l3_to_l2[gemma_con$l3_mapping]
gemma_l2 <- gemma_con |> filter(!is.na(l2)) |> count(l2, name = "gemma")

l2_shares <- l2_shares |>
  left_join(qwen_l2, by = "l2") |>
  left_join(gemma_l2, by = "l2") |>
  mutate(qwen = replace_na(qwen, 0), gemma = replace_na(gemma, 0))

l2_total_pre   <- sum(l2_shares$pre)
l2_total_post  <- sum(l2_shares$post)
l2_total_qwen  <- sum(l2_shares$qwen)
l2_total_gemma <- sum(l2_shares$gemma)

clean_l2 <- function(x) sub("^L2-[0-9]+: ", "", x)

plot_df3 <- l2_shares |>
  mutate(
    pre_share   = pre / l2_total_pre,
    post_share  = post / l2_total_post,
    qwen_share  = qwen / l2_total_qwen,
    gemma_share = gemma / l2_total_gemma,
    l2_clean    = clean_l2(l2)
  ) |>
  pivot_longer(cols = c(pre_share, post_share, qwen_share, gemma_share),
               names_to = "source", values_to = "share") |>
  mutate(source = recode(source,
    "pre_share"   = "Pre-2023 literature",
    "post_share"  = "Post-2023 literature",
    "qwen_share"  = "Qwen3",
    "gemma_share" = "Gemma"
  )) |>
  mutate(source = factor(source, levels = c("Qwen3", "Gemma",
                                             "Post-2023 literature",
                                             "Pre-2023 literature")))

l2_order <- l2_shares |>
  mutate(l2_clean = clean_l2(l2)) |>
  arrange(qwen / l2_total_qwen) |>
  pull(l2_clean)

plot_df3$l2_clean <- factor(plot_df3$l2_clean, levels = l2_order)

fig3 <- ggplot(plot_df3, aes(x = share, y = l2_clean, fill = source)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7,
           colour = "black", linewidth = 0.15) +
  scale_fill_manual(values = c("Qwen3" = "grey15",
                                "Gemma" = "grey40",
                                "Post-2023 literature" = "grey65",
                                "Pre-2023 literature" = "grey85"),
                    name = NULL) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x = "Share of total", y = NULL,
       title = "Method share by L2 sub-discipline") +
  theme_paper +
  theme(axis.text.y = element_text(size = 7.5))

ggsave(file.path(OUT_DIR, "fig3_l2_triple_bar.png"), fig3,
       width = 8, height = 7, dpi = 300, bg = "white")
cat("Fig. 3 saved.\n")

# ═══════════════════════════════════════════════════════════════════════════
# Fig. 4 — Top 10 L3: Qwen3 vs Gemma
# ═══════════════════════════════════════════════════════════════════════════

qwen_all <- qwen_con |>
  filter(!is.na(l3_mapping)) |>
  count(l3 = l3_mapping, name = "qwen") |>
  mutate(qwen_share = qwen / sum(qwen))

gemma_all <- gemma_con |>
  filter(!is.na(l3_mapping)) |>
  count(l3 = l3_mapping, name = "gemma") |>
  mutate(gemma_share = gemma / sum(gemma))

top10_q <- qwen_all |> slice_max(qwen, n = 10) |> pull(l3)
top10_g <- gemma_all |> slice_max(gemma, n = 10) |> pull(l3)
top10_union <- union(top10_q, top10_g)

gamma_df <- read.csv(if (file.exists(here("data/output/gamma_results.csv")))
                       here("data/output/gamma_results.csv") else
                       here("data/output/phi_free/gamma_results.csv"),
                     stringsAsFactors = FALSE)
gamma_lookup <- setNames(gamma_df$mean_gamma, gamma_df$l3)

cmp <- full_join(qwen_all, gemma_all, by = "l3") |>
  filter(l3 %in% top10_union) |>
  mutate(across(c(qwen_share, gemma_share), ~ replace_na(.x, 0)),
         l3_clean = sub("^L3-[0-9]+: ", "", l3),
         gamma = gamma_lookup[l3])

order4 <- cmp |> arrange(qwen_share) |> pull(l3_clean)

plot_df4 <- cmp |>
  select(l3_clean, Qwen3 = qwen_share, Gemma = gemma_share, gamma) |>
  pivot_longer(c(Qwen3, Gemma), names_to = "model", values_to = "share") |>
  mutate(l3_clean = factor(l3_clean, levels = order4))

gamma_labels <- cmp |>
  mutate(l3_clean = factor(l3_clean, levels = order4),
         max_share = pmax(qwen_share, gemma_share),
         gamma_lab = ifelse(gamma >= 0,
                            paste0("+", formatC(gamma, format = "f", digits = 2)),
                            formatC(gamma, format = "f", digits = 2)))

fig4 <- ggplot(plot_df4, aes(x = share, y = l3_clean, fill = model)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6,
           colour = "black", linewidth = 0.15) +
  geom_text(data = gamma_labels,
            aes(x = max_share, y = l3_clean, label = gamma_lab),
            inherit.aes = FALSE, hjust = -0.15, size = 2.8, family = "mono") +
  scale_fill_manual(values = c("Qwen3" = "grey30", "Gemma" = "grey70"), name = NULL) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 0.1),
                     expand = expansion(mult = c(0.01, 0.12))) +
  labs(x = "Share of total recommendations", y = NULL,
       title = "Top recommended L3 methods: Qwen3 vs. Gemma") +
  theme_paper +
  theme(axis.text.y = element_text(size = 7.5))

ggsave(file.path(OUT_DIR, "fig4_top10_qwen_vs_gemma.png"), fig4,
       width = 8, height = 5.5, dpi = 300, bg = "white")
cat("Fig. 4 saved.\n")

# ═══════════════════════════════════════════════════════════════════════════
# Fig. 5 — Concentration posteriors (inv Simpson)
# ═══════════════════════════════════════════════════════════════════════════

conc_draws <- read.csv(here("data/output/concentration_inv_simpson_draws.csv"),
                       stringsAsFactors = FALSE)

conc_long <- conc_draws |>
  mutate(draw_id = row_number()) |>
  pivot_longer(-draw_id, names_to = "source", values_to = "inv_simpson") |>
  mutate(source = gsub("\\.", " ", source),
         source = gsub("   ", " — ", source))

source_medians <- conc_long |>
  group_by(source) |>
  summarise(med = median(inv_simpson), .groups = "drop") |>
  arrange(desc(med))

conc_long$source <- factor(conc_long$source, levels = source_medians$source)

fig5 <- ggplot(conc_long, aes(x = inv_simpson, y = source)) +
  stat_halfeye(
    .width         = c(0.50, 0.90),
    point_interval = "median_qi",
    fill           = "grey60",
    colour         = "black",
    slab_alpha     = 0.6,
    linewidth      = 0.4,
    point_size     = 1.5
  ) +
  labs(x = "Effective number of methods (Inverse Simpson)",
       y = NULL,
       title = "Recommendation concentration: posterior distributions",
       caption = "Dirichlet conjugate posterior. Higher = more diverse. Dark band: 50% CI; light: 90% CI.\nIntervals treat recommendations as independent; within-response clustering would widen them ~1.5–2.5× without affecting the LLM–literature gap.") +
  theme_paper +
  theme(axis.text.y = element_text(size = 8))

ggsave(file.path(OUT_DIR, "fig5_concentration_posteriors.png"), fig5,
       width = 8, height = 5, dpi = 300, bg = "white")
cat("Fig. 5 saved.\n")

# ═══════════════════════════════════════════════════════════════════════════
# Fig. 6 — b_pre vs b_gamma posteriors (overall, both models)
# ═══════════════════════════════════════════════════════════════════════════

prev_draws <- read.csv(here("data/output/prevalence_gamma_draws.csv"),
                       stringsAsFactors = FALSE)

plot_df7 <- bind_rows(
  data.frame(value = prev_draws$qwen_b_gamma,
             parameter = "(A) b[gamma] (post-2023 excess)", model = "Qwen3"),
  data.frame(value = prev_draws$gemma_b_gamma,
             parameter = "(A) b[gamma] (post-2023 excess)", model = "Gemma"),
  data.frame(value = prev_draws$qwen_b_pre,
             parameter = "(B) b[pre] (corpus prevalence)", model = "Qwen3"),
  data.frame(value = prev_draws$gemma_b_pre,
             parameter = "(B) b[pre] (corpus prevalence)", model = "Gemma")
)

fig6 <- ggplot(plot_df7, aes(x = value, y = model, fill = model)) +
  stat_halfeye(
    .width         = c(0.50, 0.90),
    point_interval = "mean_qi",
    slab_alpha     = 0.6,
    linewidth      = 0.4,
    point_size     = 1.5
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.3) +
  facet_wrap(~ parameter, scales = "free_x", ncol = 1) +
  scale_fill_manual(values = c("Qwen3" = "grey35", "Gemma" = "grey70")) +
  labs(x = "Posterior coefficient", y = NULL,
       title = "Prevalence echo, not recent momentum",
       caption = "Coefficients from a two-predictor count regression: b_pre (how often a method appeared in pre-2023 literature) and b_gamma (whether it gained momentum post-2023). Overall profile. Bands: 50%/90% CI.") +
  theme_paper +
  theme(legend.position = "none")

ggsave(file.path(OUT_DIR, "fig6_bpre_bgamma_posteriors.png"), fig6,
       width = 7, height = 5, dpi = 300, bg = "white")
cat("Fig. 6 saved.\n")

# ═══════════════════════════════════════════════════════════════════════════
# Fig. 7 — b_gamma by profile and model
# ═══════════════════════════════════════════════════════════════════════════

prev_summary <- read.csv(here("data/output/prevalence_gamma_summary.csv"),
                         stringsAsFactors = FALSE)

# Need per-profile draws — refit is too expensive, use summary stats to
# simulate from normal approximation (mean + CI → sd)
# Better: re-read from the 08 script outputs. Check if per-profile draws exist.
# They don't — the saved draws are overall only. Use the summary table with CIs.

prev_summary$profile <- factor(prev_summary$profile,
                                levels = c("overall", "novice", "intermediate", "expert"),
                                labels = c("(A) overall", "(B) novice", "(C) intermediate", "(D) expert"))

fig7 <- ggplot(prev_summary, aes(y = model)) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.3) +
  geom_linerange(aes(xmin = b_gamma_lo90, xmax = b_gamma_hi90),
                 linewidth = 0.6, colour = "grey40") +
  geom_point(aes(x = b_gamma_mean), size = 2, shape = 21,
             fill = "grey50", colour = "black") +
  facet_wrap(~ profile, ncol = 1) +
  labs(x = "Post-2023 momentum coefficient (b_gamma)",
       y = NULL,
       title = "No profile gradient in post-2023 momentum effect",
       caption = "Point: posterior mean. Horizontal bar: 90% credible interval. Dashed line: zero.") +
  theme_paper

ggsave(file.path(OUT_DIR, "fig7_bgamma_by_profile.png"), fig7,
       width = 7, height = 5.5, dpi = 300, bg = "white")
cat("Fig. 7 saved.\n")

cat("\nAll main-text figures saved to:", OUT_DIR, "\n")
