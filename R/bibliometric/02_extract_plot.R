
library(cmdstanr)
library(posterior)
library(dplyr)
library(tidyr)
library(ggplot2)

FIT_RDS        <- "data/output/fit_phi_free.rds"
VOCAB_RDS      <- "data/output/vocab.rds"
STAN_DATA_RDS  <- "data/output/stan_data.rds"
SUMMARY_CSV    <- "data/output/inv_simpson_summary.csv"
PLOT_DIVERSITY <- "data/output/figures/l2_l3/plot_diversity_by_group.png"
PLOT_SIGMA     <- "data/output/figures/l2_l3/plot_sigma_posteriors.png"
PLOT_GAMMA_DOT <- "data/output/figures/l2_l3/plot_gamma_dotplot.png"
PLOT_RAW       <- "data/output/figures/l2_l3/plot_raw_counts.png"
DRAWS_RDS      <- "data/output/inv_simpson_draws.rds"

dir.create("data/output/l3", recursive = TRUE, showWarnings = FALSE)
dir.create("data/output/figures/l2_l3", recursive = TRUE, showWarnings = FALSE)

fit       <- readRDS(FIT_RDS)
vocab     <- readRDS(VOCAB_RDS)
stan_data <- readRDS(STAN_DATA_RDS)

l2_levels   <- vocab$l2_levels
year_levels <- vocab$year_levels
N_groups    <- length(l2_levels)
N_years     <- length(year_levels)
K_g_vec     <- vocab$K_g
year_std    <- stan_data$year_std
post_llm    <- stan_data$post_llm
K_max       <- stan_data$K_max

draws <- fit$draws(format = "draws_matrix")
S     <- nrow(draws)

draws_to_array <- function(draws, prefix, d1, d2) {
  arr <- array(NA_real_, dim = c(nrow(draws), d1, d2))
  for (i in seq_len(d1))
    for (j in seq_len(d2))
      arr[, i, j] <- draws[, sprintf("%s[%d,%d]", prefix, i, j)]
  arr
}

# Diagnostic: print array shapes immediately
cat("\n--- Array shape diagnostics ---\n")
mu_raw_arr       <- draws_to_array(draws, "mu_raw", N_groups, K_max)
beta_method_arr  <- draws_to_array(draws, "beta_method", N_groups, K_max)
gamma_method_arr <- draws_to_array(draws, "gamma_method", N_groups, K_max)
cat("mu_raw dims:       ", paste(dim(mu_raw_arr),       collapse = " x "), "\n")
cat("beta_method dims:  ", paste(dim(beta_method_arr),  collapse = " x "), "\n")
cat("gamma_method dims: ", paste(dim(gamma_method_arr), collapse = " x "), "\n")
cat("K_g range: min =", min(K_g_vec), ", max =", max(K_g_vec), "\n")

zero_K <- which(K_g_vec == 0)
if (length(zero_K) > 0) {
  stop("K_g == 0 for groups: ", paste(zero_K, collapse = ", "),
       " — data prep must have failed for these groups.")
}

cat("Posterior draws S =", S, ", K_max =", K_max, "\n")

# Plot 1: Diversity by group (inv_simpson)
inv_simp_arr <- draws_to_array(draws, "inv_simpson", N_groups, N_years)
cat("inv_simpson dims:", paste(dim(inv_simp_arr), collapse = " x "), "\n")

inv_simp_tidy <- expand.grid(
    draw = seq_len(S),
    g    = seq_len(N_groups),
    t    = seq_len(N_years)
  ) |>
  mutate(
    inv_simpson = mapply(function(d, g, t) inv_simp_arr[d, g, t], draw, g, t),
    l2 = l2_levels[g],
    year        = year_levels[t]
  )

saveRDS(inv_simp_tidy, DRAWS_RDS)
cat("Raw draws saved to:", DRAWS_RDS, "\n")

inv_simp_summary <- inv_simp_tidy |>
  group_by(l2, year) |>
  summarise(
    median = median(inv_simpson),
    lo90   = quantile(inv_simpson, 0.05),
    hi90   = quantile(inv_simpson, 0.95),
    lo50   = quantile(inv_simpson, 0.25),
    hi50   = quantile(inv_simpson, 0.75),
    .groups = "drop"
  )

write.csv(inv_simp_summary, SUMMARY_CSV, row.names = FALSE)
cat("Summary CSV saved to:", SUMMARY_CSV, "\n")


# Empirical inv_simpson from raw counts (no model)
emp_diversity <- do.call(rbind, lapply(seq_len(N_groups), function(g) {
  K <- K_g_vec[g]
  do.call(rbind, lapply(seq_len(N_years), function(t) {
    cts   <- stan_data$counts[g, t, 1:K]
    total <- sum(cts)
    if (total == 0) return(NULL)
    p <- cts / total
    p <- p[p > 0]
    data.frame(
      l2  = l2_levels[g],
      year         = year_levels[t],
      inv_simp_emp = 1 / sum(p^2),
      stringsAsFactors = FALSE
    )
  }))
})) |>
  mutate(label = sub("^L2-\\d+: ", "", l2))

# Conjugate-posterior ribbon: use stored inv_simpson draws from fit
conj_summary <- inv_simp_summary |>
  mutate(label = sub("^L2-\\d+: ", "", l2))

p1 <- ggplot(conj_summary, aes(x = year)) +
  geom_point(data = emp_diversity,
             aes(y = inv_simp_emp, colour = "Observed (annual)"),
             size = 0.8, alpha = 0.7) +
  geom_ribbon(aes(ymin = lo90, ymax = hi90), alpha = 0.15, fill = "steelblue") +
  geom_ribbon(aes(ymin = lo50, ymax = hi50), alpha = 0.30, fill = "steelblue") +
  geom_line(aes(y = median, colour = "Posterior median"), linewidth = 0.6) +
  geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
  annotate("text", x = 2023, y = Inf, label = "LLM adoption",
           hjust = -0.05, vjust = 1.5, size = 2, colour = "firebrick") +
  scale_colour_manual(
    values = c("Observed (annual)" = "grey40", "Posterior median" = "steelblue4"),
    name   = NULL
  ) +
  facet_wrap(~ label, scales = "free_y", ncol = 6) +
  labs(
    x        = "Year",
    y        = "Inverse Simpson (effective N of L3 methods)",
    title    = "Methodological diversity within L2 groups over time",
    subtitle = "Grey dots = observed annual diversity; ribbon = 50%/90% posterior credible intervals"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    strip.text      = element_text(size = 6),
    panel.grid.minor = element_blank(),
    legend.position = "bottom"
  )

ggsave(PLOT_DIVERSITY, p1, width = 20, height = 16, units = "in", dpi = 150)
cat("Plot saved to:", PLOT_DIVERSITY, "\n")

# Plot 2: sigma_beta and sigma_gamma side-by-side
sigma_beta_draws  <- as.numeric(draws[, "sigma_beta"])
sigma_gamma_draws <- as.numeric(draws[, "sigma_gamma"])

sigma_df <- data.frame(
  value     = c(sigma_beta_draws, sigma_gamma_draws),
  parameter = rep(c("sigma_beta (baseline trend)", "sigma_gamma (post-LLM shift)"),
                  each = length(sigma_beta_draws))
)

x_max <- max(quantile(sigma_beta_draws, 0.999), quantile(sigma_gamma_draws, 0.999))

p2 <- ggplot(sigma_df, aes(x = value, fill = parameter)) +
  geom_density(alpha = 0.5, colour = NA) +
  scale_fill_manual(values = c("sigma_beta (baseline trend)"   = "steelblue",
                                "sigma_gamma (post-LLM shift)" = "firebrick")) +
  coord_cartesian(xlim = c(0, x_max)) +
  facet_wrap(~ parameter, ncol = 2) +
  labs(
    x        = "Posterior value",
    y        = "Density",
    title    = "Sigma posteriors: baseline trend vs post-LLM shift",
    subtitle = "Primary diagnostic for whether post-LLM variation exists globally"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none")

ggsave(PLOT_SIGMA, p2, width = 10, height = 5, units = "in", dpi = 150)
cat("Plot saved to:", PLOT_SIGMA, "\n")

cat("\n--- sigma_beta summary ---\n")
print(fit$summary("sigma_beta"))
cat("\n--- sigma_gamma summary (KEY SCIENTIFIC QUANTITY) ---\n")
print(fit$summary("sigma_gamma"))

# Extract diagnostic values for doc auto-fill
n_divergences <- sum(fit$diagnostic_summary()$num_divergent)
sm_diag <- fit$summary(c("sigma_beta", "sigma_gamma", "phi"))

sb_row  <- sm_diag[sm_diag$variable == "sigma_beta", ]
sg_row  <- sm_diag[sm_diag$variable == "sigma_gamma", ]
phi_row <- sm_diag[sm_diag$variable == "phi", ]

rhat_sigma_beta  <- sb_row$rhat
rhat_sigma_gamma <- sg_row$rhat
ess_sigma_beta   <- sb_row$ess_bulk
ess_sigma_gamma  <- sg_row$ess_bulk
sigma_beta_mean  <- sb_row$mean
sigma_gamma_mean <- sg_row$mean
phi_mean         <- phi_row$mean

sigma_beta_ci  <- quantile(sigma_beta_draws, c(0.025, 0.975))
sigma_gamma_ci <- quantile(sigma_gamma_draws, c(0.025, 0.975))
sigma_beta_ci_str  <- paste0("[", round(sigma_beta_ci[1], 4), ", ", round(sigma_beta_ci[2], 4), "]")
sigma_gamma_ci_str <- paste0("[", round(sigma_gamma_ci[1], 4), ", ", round(sigma_gamma_ci[2], 4), "]")

phi_draws <- as.numeric(draws[, "phi"])
phi_90ci  <- quantile(phi_draws, c(0.05, 0.95))

# Extract gamma_method posteriors
# gamma_method_arr shape: [S, N_groups, K_max]
# Use matrix(..., nrow=S, ncol=K) to guard against K==1 dimension drop.

gamma_list <- vector("list", N_groups)

for (grp in seq_len(N_groups)) {
  K <- K_g_vec[grp]

  gm_g <- matrix(gamma_method_arr[, grp, 1:K], nrow = S, ncol = K)

  method_labels <- vocab$l3_vocab |>
    filter(g == grp) |>
    arrange(k_local) |>
    pull(l3)

  gamma_list[[grp]] <- data.frame(
    g            = grp,
    l2  = l2_levels[grp],
    k            = seq_len(K),
    l3 = method_labels,
    mean_gamma   = colMeans(gm_g),
    lo90         = apply(gm_g, 2, quantile, 0.05),
    hi90         = apply(gm_g, 2, quantile, 0.95),
    stringsAsFactors = FALSE
  )
}

gamma_df <- bind_rows(gamma_list) |>
  mutate(
    sig         = (lo90 > 0 | hi90 < 0),
    group_label = sub("^L2-\\d+: ", "", l2),
    method_id   = paste0(group_label, ": ", l3)
  )

cat("Methods with 90% CI excluding zero (credible post-LLM shift):",
    sum(gamma_df$sig, na.rm = TRUE), "\n")

# Plot 3: gamma dotplot

sig_gamma <- gamma_df |> filter(sig)

all_shown <- nrow(sig_gamma) == 0
if (all_shown) {
  cat("WARNING: no significant gamma methods; showing all methods instead\n")
  sig_gamma <- gamma_df
}

sig_gamma <- sig_gamma |>
  arrange(mean_gamma) |>
  mutate(
    method_id = factor(method_id, levels = unique(method_id)),
    direction = ifelse(mean_gamma > 0, "positive", "negative")
  )

dotplot_subtitle <- if (all_shown) {
  "No method's 90% CI excludes zero; all methods shown; red = gaining share, blue = losing share"
} else {
  "Only methods where 90% CI excludes zero; red = gaining share, blue = losing share"
}

p3 <- ggplot(sig_gamma, aes(x = mean_gamma, y = method_id, colour = direction)) +
  geom_point(size = 1.5) +
  geom_errorbarh(aes(xmin = lo90, xmax = hi90),
                 height = 0.3, linewidth = 0.35) +
  scale_colour_manual(values = c("positive" = "firebrick", "negative" = "steelblue"),
                      guide = "none") +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  labs(
    x        = "Posterior mean gamma (post-LLM differential slope)",
    y        = NULL,
    title    = "Differential post-2023 method slopes (gamma_method)",
    subtitle = dotplot_subtitle
  ) +
  theme_minimal(base_size = 8) +
  theme(
    axis.text.y        = element_text(size = 5),
    panel.grid.major.y = element_blank()
  )

plot_h <- max(8, 0.15 * nrow(sig_gamma))
ggsave(PLOT_GAMMA_DOT, p3, width = 14, height = plot_h, units = "in", dpi = 150, limitsize = FALSE)
cat("Plot saved to:", PLOT_GAMMA_DOT, "\n")

# Top 15 methods by |gamma|
top15 <- gamma_df |>
  mutate(abs_gamma = abs(mean_gamma)) |>
  arrange(desc(abs_gamma)) |>
  slice_head(n = 15)

cat("\nTop 15 methods by |mean_gamma|:\n")
print(top15 |> select(l2, l3, mean_gamma, lo90, hi90))

# Plot 4: raw observed counts for top 15

raw_counts_list <- vector("list", nrow(top15))

for (i in seq_len(nrow(top15))) {
  g_i <- top15$g[i]
  k_i <- top15$k[i]

  raw_df <- data.frame(
    year    = year_levels,
    n_papers = as.integer(stan_data$counts[g_i, , k_i])
  )

  method_label <- paste0(
    sub("^L2-\\d+: ", "", l2_levels[g_i]), ": ", top15$l3[i]
  )
  raw_df$method_id <- method_label
  raw_counts_list[[i]] <- raw_df
}

raw_all <- bind_rows(raw_counts_list) |>
  mutate(method_id = factor(
    method_id,
    levels = paste0(
      sub("^L2-\\d+: ", "", l2_levels[top15$g]),
      ": ", top15$l3
    )
  ))

p5 <- ggplot(raw_all, aes(x = year, y = n_papers)) +
  geom_point(size = 1, colour = "grey40") +
  geom_smooth(method = "loess", formula = y ~ x, se = TRUE,
              colour = "darkorange3", fill = "darkorange", alpha = 0.2,
              linewidth = 1.2, span = 0.75) +
  geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick",
             linewidth = 0.4) +
  annotate("text", x = 2023, y = Inf, label = "LLM adoption",
           hjust = -0.05, vjust = 1.5, size = 2, colour = "firebrick") +
  facet_wrap(~ method_id, scales = "free_y", ncol = 3) +
  labs(
    x = "Year", y = "Observed paper count",
    title    = "Top 15 methods: raw observed paper counts 2010-2025",
    subtitle = "Orange = non-parametric loess smoother (NOT the Bayesian model); dashed = 2023 LLM adoption boundary"
  ) +
  theme_minimal(base_size = 7) +
  theme(strip.text = element_text(size = 5), panel.grid.minor = element_blank())

ggsave(PLOT_RAW, p5, width = 18, height = 12, units = "in", dpi = 150)
cat("Plot saved to:", PLOT_RAW, "\n")

# Auto-update l2_l3_results.md diagnostics
DOC_PATH <- "docs/l2_l3_results.md"
if (file.exists(DOC_PATH)) {
  doc <- readLines(DOC_PATH)
  txt <- paste(doc, collapse = "\n")

  max_rhat <- max(sm_diag$rhat, na.rm = TRUE)
  sg_90ci  <- quantile(sigma_gamma_draws, c(0.05, 0.95))

  update_row <- function(txt, label, value) {
    pattern <- paste0("(\\|\\s*", label, "\\s*\\|)\\s*[^|]+(\\|)")
    gsub(pattern, paste0("\\1 ", value, " \\2"), txt)
  }

  txt <- update_row(txt, "phi posterior mean",     round(phi_mean))
  txt <- update_row(txt, "phi 90% CI",
                    paste0("[", round(phi_90ci[1]), ", ", round(phi_90ci[2]), "]"))
  txt <- update_row(txt, "sigma_gamma mean",       round(sigma_gamma_mean, 3))
  txt <- update_row(txt, "sigma_gamma 90% CI",
                    paste0("[", round(sg_90ci[1], 3), ", ", round(sg_90ci[2], 3), "]"))
  txt <- update_row(txt, "sigma_beta mean",        round(sigma_beta_mean, 3))
  txt <- update_row(txt, "Rhat \\(all params\\)",  paste0("< ", round(max_rhat, 3)))
  txt <- update_row(txt, "ESS \\(sigma_gamma\\)",  round(ess_sigma_gamma))
  txt <- update_row(txt, "Divergences",            n_divergences)

  writeLines(strsplit(txt, "\n")[[1]], DOC_PATH)
  cat("Diagnostics table updated in", DOC_PATH, "\n")
} else {
  cat("WARNING:", DOC_PATH, "not found; skipping auto-population.\n")
}

