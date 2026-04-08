cat("=== 03_l2_analysis.R ===\n")
cat("L1->L2 complementary analysis (sensitivity check at L1 group level)\n")

library(readxl)
library(dplyr)
library(tidyr)
library(ggplot2)
library(rstan)
library(httr)

options(mc.cores = parallel::detectCores())
rstan_options(auto_write = TRUE)

# ── Paths ─────────────────────────────────────────────────────────────────────
INPUT_FILE <- "data/input/qwen_dataset.xlsx"
OUTPUT_DIR <- "data/output/l2"
FIT_L2_RDS    <- "data/output/l2/fit_l2.rds"
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

token   <- "TELEGRAM_BOT_TOKEN_REDACTED"
chat_id <- Sys.getenv("TELEGRAM_CHAT_ID")

# ── Data preparation ──────────────────────────────────────────────────────────
cat("Loading data...\n")
raw <- read_excel(INPUT_FILE) |>
  filter(Year >= 2010, Year <= 2025)
cat("Rows loaded:", nrow(raw), "\n")

df_clean <- raw |>
  distinct(abstract_id, Year, level_1_macro, level_2_mid)

cat("Rows after dedup:", nrow(df_clean), "\n")

l1_levels   <- sort(unique(df_clean$level_1_macro))
year_levels <- sort(unique(df_clean$Year))
N_groups    <- length(l1_levels)
N_years     <- length(year_levels)

cat("L1 groups:", N_groups, "\n")
cat("Years:    ", N_years, "(", min(year_levels), "-", max(year_levels), ")\n")

l2_vocab <- df_clean |>
  distinct(level_1_macro, level_2_mid) |>
  arrange(level_1_macro, level_2_mid) |>
  group_by(level_1_macro) |>
  mutate(k_local = row_number(), K_g = n()) |>
  ungroup() |>
  mutate(g = match(level_1_macro, l1_levels))

K_g   <- l2_vocab |> group_by(g) |> summarise(K = first(K_g)) |> pull(K)
K_max <- max(K_g)

cat("K_max (largest L1 group):", K_max, "\n")
cat("Total L2 methods:        ", nrow(l2_vocab |> distinct(level_2_mid)), "\n")

df_indexed <- df_clean |>
  mutate(
    g = match(level_1_macro, l1_levels),
    t = match(Year, year_levels)
  ) |>
  left_join(
    l2_vocab |> select(level_1_macro, level_2_mid, k_local),
    by = c("level_1_macro", "level_2_mid")
  )

counts_long  <- df_indexed |> count(g, t, k_local, name = "n_papers")
counts_array <- array(0L, dim = c(N_groups, N_years, K_max))
for (i in seq_len(nrow(counts_long))) {
  counts_array[counts_long$g[i], counts_long$t[i], counts_long$k_local[i]] <-
    counts_long$n_papers[i]
}

years_vec <- 2010:2025
year_std  <- as.numeric(scale(year_levels))
post_llm  <- as.integer(years_vec >= 2023)

cat("post_llm vector (2010-2025):", post_llm, "\n")

stan_data <- list(
  N_groups  = N_groups,
  N_years   = N_years,
  K_max     = K_max,
  K_g       = K_g,
  counts    = counts_array,
  phi     = 10.0,
  year_std  = year_std,
  post_llm  = post_llm
)

# ── Inline Stan model (identical structure to diversity_model.stan) ───────────
# No non-ASCII characters in Stan code. Hand-rolled dm_log, no built-in
# dirichlet_multinomial. phi fixed at 10 as data input.
stan_code <- "
functions {
  real dm_log(array[] int n, vector alpha) {
    real a0 = sum(alpha);
    int N = sum(n);
    return lgamma(a0) - lgamma(a0 + N)
         + sum(lgamma(alpha + to_vector(n))) - sum(lgamma(alpha));
  }
}

data {
  int<lower=1> N_groups;
  int<lower=1> N_years;
  int<lower=1> K_max;
  array[N_groups] int<lower=1> K_g;
  array[N_groups, N_years, K_max] int<lower=0> counts;
  real<lower=0> phi;
  vector[N_years] year_std;
  array[N_years] int post_llm;
}

parameters {
  array[N_groups] vector[K_max] mu_raw;
  array[N_groups] vector[K_max] beta_method_raw;
  real<lower=0> sigma_beta;
  array[N_groups] vector[K_max] gamma_method_raw;
  real<lower=0> sigma_gamma;
}

transformed parameters {
  array[N_groups] vector[K_max] beta_method;
  array[N_groups] vector[K_max] gamma_method;
  for (g in 1:N_groups) {
    beta_method[g]  = sigma_beta  * beta_method_raw[g];
    gamma_method[g] = sigma_gamma * gamma_method_raw[g];
  }
}

model {
  sigma_beta  ~ exponential(2);
  sigma_gamma ~ exponential(4);

  for (g in 1:N_groups) {
    int K = K_g[g];

    mu_raw[g][1:K] ~ normal(0, 1);
    sum(mu_raw[g][1:K]) ~ normal(0, 0.001 * K);

    beta_method_raw[g][1:K] ~ normal(0, 1);
    sum(beta_method_raw[g][1:K]) ~ normal(0, 0.001 * K);

    gamma_method_raw[g][1:K] ~ normal(0, 1);
    sum(gamma_method_raw[g][1:K]) ~ normal(0, 0.001 * K);

    if (K < K_max) {
      mu_raw[g][(K+1):K_max]           ~ normal(0, 0.001);
      beta_method_raw[g][(K+1):K_max]  ~ normal(0, 0.001);
      gamma_method_raw[g][(K+1):K_max] ~ normal(0, 0.001);
    }
  }

  for (g in 1:N_groups) {
    int K = K_g[g];
    for (t in 1:N_years) {
      if (sum(counts[g, t, 1:K]) == 0) continue;

      vector[K] eta   = mu_raw[g][1:K]
                        + beta_method[g][1:K]  * year_std[t]
                        + gamma_method[g][1:K] * post_llm[t];
      vector[K] alpha = softmax(eta) * phi;
      array[K] int y  = counts[g, t, 1:K];

      target += dm_log(y, alpha);
    }
  }
}

generated quantities {
  matrix[N_groups, N_years] inv_simpson;
  matrix[N_groups, N_years] eff_N_shannon;

  for (g in 1:N_groups) {
    int K = K_g[g];
    for (t in 1:N_years) {
      vector[K] eta = mu_raw[g][1:K]
                      + beta_method[g][1:K]  * year_std[t]
                      + gamma_method[g][1:K] * post_llm[t];

      // Conjugate Dirichlet posterior: combines the trend prior with observed
      // counts for this group-year.
      //
      // Prior:     pi[g,t] ~ Dirichlet(softmax(eta) * phi)
      // Likelihood:  y     ~ Multinomial(pi[g,t])
      // Posterior: pi[g,t] | y ~ Dirichlet(softmax(eta) * phi + y)
      //
      // Effect: years with many papers are dominated by the observed shares
      // (more data -> tighter diversity CI); sparse years stay regularised
      // toward the trend prediction. The crossover is near N_papers ~ phi.

      int N_gt = sum(counts[g, t, 1:K]);
      vector[K] p;

      if (N_gt > 0) {
        vector[K] y_k;
        for (k in 1:K) y_k[k] = counts[g, t, k];
        p = dirichlet_rng(softmax(eta) * phi + y_k);
      } else {
        // No papers this group-year: fall back to trend-only prediction.
        p = softmax(eta);
      }

      inv_simpson[g, t]   = 1.0 / dot_self(p);
      eff_N_shannon[g, t] = exp(-dot_product(p, log(p)));
    }
  }
}
"

# ── Compile and fit (guarded) ─────────────────────────────────────────────────
if (!file.exists(FIT_L2_RDS)) {
  cat("Compiling Stan model (L1->L2 level)...\n")
  l2_mod <- stan_model(model_code = stan_code)

  cat("Sampling (this will take a while)...\n")
  t_start <- proc.time()

  l2_fit <- suppressWarnings(sampling(
    l2_mod,
    data    = stan_data,
    chains  = 4,
    iter    = 2000,
    warmup  = 1000,
    cores   = 4,
    seed    = 42,
    control = list(adapt_delta = 0.95, max_treedepth = 15),
    refresh = 100
  ))

  t_elapsed   <- proc.time() - t_start
  elapsed_min <- round(t_elapsed["elapsed"] / 60, 1)
  cat("Sampling done. Elapsed:", elapsed_min, "minutes\n")

  cat("\n--- HMC diagnostics ---\n")
  check_hmc_diagnostics(l2_fit)

  cat("\n--- sigma_beta summary ---\n")
  print(summary(l2_fit, pars = "sigma_beta")$summary)
  cat("\n--- sigma_gamma summary (KEY SCIENTIFIC QUANTITY) ---\n")
  print(summary(l2_fit, pars = "sigma_gamma")$summary)

  saveRDS(l2_fit, FIT_L2_RDS)
  cat("L2 fit saved to:", FIT_L2_RDS, "\n")

} else {
  message("fit_l2.rds already exists — skipping Stan run. Delete it to refit.")
  l2_fit <- readRDS(FIT_L2_RDS)
}

# ── Telegram: L2-level diagnostics ───────────────────────────────────────────
tryCatch({
  n_div    <- sum(rstan::get_divergent_iterations(l2_fit))
  div_flag <- if (n_div == 0) "Divergences: 0" else paste0("Divergences: ", n_div, " !!!")

  sm <- rstan::summary(l2_fit, pars = c("sigma_beta", "sigma_gamma"),
                       probs = c(0.05, 0.95))$summary

  rhat_sb <- round(sm["sigma_beta",  "Rhat"],  3)
  rhat_sg <- round(sm["sigma_gamma", "Rhat"],  3)
  ess_sb  <- round(sm["sigma_beta",  "n_eff"])
  ess_sg  <- round(sm["sigma_gamma", "n_eff"])

  rhat_sb_flag <- if (rhat_sb > 1.01) {
    paste0("sigma_beta Rhat = ", rhat_sb, " [BAD > 1.01]")
  } else {
    paste0("sigma_beta Rhat = ", rhat_sb, " [OK]")
  }
  rhat_sg_flag <- if (rhat_sg > 1.01) {
    paste0("sigma_gamma Rhat = ", rhat_sg, " [BAD > 1.01]")
  } else {
    paste0("sigma_gamma Rhat = ", rhat_sg, " [OK]")
  }
  ess_sb_flag <- if (ess_sb < 400) {
    paste0("sigma_beta ESS = ", ess_sb, " [BAD < 400]")
  } else {
    paste0("sigma_beta ESS = ", ess_sb, " [OK]")
  }
  ess_sg_flag <- if (ess_sg < 400) {
    paste0("sigma_gamma ESS = ", ess_sg, " [BAD < 400]")
  } else {
    paste0("sigma_gamma ESS = ", ess_sg, " [OK]")
  }

  sg_mean <- round(sm["sigma_gamma", "mean"], 4)
  sg_lo   <- round(sm["sigma_gamma", "5%"],   4)
  sg_hi   <- round(sm["sigma_gamma", "95%"],  4)
  sg_line <- paste0("sigma_gamma (KEY - post-LLM shift scale): mean = ", sg_mean,
                    ", 90% CI [", sg_lo, ", ", sg_hi, "]")

  msg <- paste(
    "L2-level model diagnostics: L1->L2 sensitivity check",
    div_flag,
    rhat_sb_flag,
    rhat_sg_flag,
    ess_sb_flag,
    ess_sg_flag,
    sg_line,
    paste0("Elapsed: ", elapsed_min, " min"),
    sep = "\n"
  )

  print("Sending Telegram L2 diagnostics...")
  resp   <- httr::POST(
    url    = paste0("https://api.telegram.org/bot", token, "/sendMessage"),
    body   = list(chat_id = chat_id, text = msg),
    encode = "form"
  )
  status <- httr::status_code(resp)
  cat("Telegram response status:", status, "\n")
  if (status != 200) {
    cat("Telegram response content:\n")
    print(httr::content(resp, as = "text", encoding = "UTF-8"))
  }
}, error = function(e) {
  message("Telegram diagnostics error: ", conditionMessage(e))
}, warning = function(w) {
  message("Telegram diagnostics warning: ", conditionMessage(w))
})

# ── Extract arrays ────────────────────────────────────────────────────────────
mu_raw_arr       <- rstan::extract(l2_fit, pars = "mu_raw")$mu_raw
beta_method_arr  <- rstan::extract(l2_fit, pars = "beta_method")$beta_method
gamma_method_arr <- rstan::extract(l2_fit, pars = "gamma_method")$gamma_method
inv_simp_arr     <- rstan::extract(l2_fit, pars = "inv_simpson")$inv_simpson

S <- dim(mu_raw_arr)[1]
cat("Posterior draws S =", S, "\n")

# ── Plot 1: Diversity by L1 group ─────────────────────────────────────────────
cat("\nComputing diversity plots per L1 group...\n")

# Empirical inv_simpson from raw counts (no model)
emp_diversity_l2 <- do.call(rbind, lapply(seq_len(N_groups), function(g) {
  K <- K_g[g]
  do.call(rbind, lapply(seq_len(N_years), function(t) {
    cts   <- counts_array[g, t, 1:K]
    total <- sum(cts)
    if (total == 0) return(NULL)
    p <- cts / total
    p <- p[p > 0]
    data.frame(
      l1_group     = l1_levels[g],
      year         = year_levels[t],
      inv_simp_emp = 1 / sum(p^2),
      stringsAsFactors = FALSE
    )
  }))
}))

# ── Conjugate-posterior ribbon: summarise stored inv_simpson draws ────────────
# inv_simp_arr [S, N_groups, N_years] was computed in generated quantities with
# the conjugate Dirichlet posterior update. Summarise directly.
conj_summary_l2 <- do.call(rbind, lapply(seq_len(N_groups), function(g) {
  do.call(rbind, lapply(seq_len(N_years), function(t) {
    vals <- inv_simp_arr[, g, t]
    data.frame(
      l1_group = l1_levels[g],
      year     = year_levels[t],
      median   = median(vals),
      lo90     = quantile(vals, 0.05),
      hi90     = quantile(vals, 0.95),
      lo50     = quantile(vals, 0.25),
      hi50     = quantile(vals, 0.75),
      stringsAsFactors = FALSE
    )
  }))
}))

p1 <- ggplot(conj_summary_l2, aes(x = year)) +
  geom_point(data = emp_diversity_l2,
             aes(y = inv_simp_emp, colour = "Observed (annual)"),
             size = 0.8, alpha = 0.7) +
  geom_ribbon(aes(ymin = lo90, ymax = hi90), alpha = 0.15, fill = "steelblue") +
  geom_ribbon(aes(ymin = lo50, ymax = hi50), alpha = 0.30, fill = "steelblue") +
  geom_line(aes(y = median, colour = "Posterior median"), linewidth = 0.6) +
  geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
  annotate("text", x = 2023, y = Inf, label = "LLM adoption",
           hjust = -0.05, vjust = 1.5, size = 2.5, colour = "firebrick") +
  scale_colour_manual(
    values = c("Observed (annual)" = "grey40", "Posterior median" = "steelblue4"),
    name   = NULL
  ) +
  facet_wrap(~ l1_group, scales = "free_y") +
  labs(
    x        = "Year",
    y        = "Inverse Simpson (effective N of L2 methods)",
    title    = "L2-level: methodological diversity within L1 groups over time",
    subtitle = "Grey dots = observed annual diversity; ribbon = 50%/90% posterior credible intervals"
  ) +
  theme_minimal(base_size = 9) +
  theme(
    strip.text       = element_text(size = 7),
    panel.grid.minor = element_blank(),
    legend.position  = "bottom"
  )

out1 <- file.path(OUTPUT_DIR, "l2_plot_diversity_by_group.png")
ggsave(out1, p1, width = 14, height = 10, units = "in", dpi = 150)
cat("Plot saved to:", out1, "\n")

# ── Plot 2: sigma posteriors side-by-side ─────────────────────────────────────
cat("Plotting sigma posteriors...\n")
sigma_beta_draws  <- rstan::extract(l2_fit, pars = "sigma_beta")$sigma_beta
sigma_gamma_draws <- rstan::extract(l2_fit, pars = "sigma_gamma")$sigma_gamma

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
    title    = "L2-level sigma posteriors: baseline trend vs post-LLM shift",
    subtitle = "Primary diagnostic for whether post-LLM variation exists at L1->L2 level"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none")

out2 <- file.path(OUTPUT_DIR, "l2_plot_sigma_posteriors.png")
ggsave(out2, p2, width = 10, height = 5, units = "in", dpi = 150)
cat("Plot saved to:", out2, "\n")

# ── Extract gamma_method posteriors ──────────────────────────────────────────
cat("\nExtracting gamma_method posteriors per L2 method...\n")

gamma_list <- vector("list", N_groups)

for (grp in seq_len(N_groups)) {
  K <- K_g[grp]
  # matrix() prevents dim-drop when K == 1
  gm_g <- matrix(gamma_method_arr[, grp, 1:K], nrow = S, ncol = K)

  method_labels <- l2_vocab |>
    filter(g == grp) |>
    arrange(k_local) |>
    pull(level_2_mid)

  gamma_list[[grp]] <- data.frame(
    g           = grp,
    l1_group    = l1_levels[grp],
    k           = seq_len(K),
    level_2_mid = method_labels,
    mean_gamma  = colMeans(gm_g),
    lo90        = apply(gm_g, 2, quantile, 0.05),
    hi90        = apply(gm_g, 2, quantile, 0.95),
    stringsAsFactors = FALSE
  )
}

gamma_df <- bind_rows(gamma_list) |>
  mutate(
    sig       = (lo90 > 0 | hi90 < 0),
    method_id = paste0(l1_group, ": ", level_2_mid)
  )

cat("L2 methods with 90% CI excluding zero:", sum(gamma_df$sig, na.rm = TRUE), "\n")

# ── Plot 3: gamma dotplot ─────────────────────────────────────────────────────
cat("Plotting gamma dotplot...\n")
sig_gamma <- gamma_df |> filter(sig)

if (nrow(sig_gamma) == 0) {
  cat("WARNING: no significant gamma methods; showing all methods instead\n")
  sig_gamma <- gamma_df
}

sig_gamma <- sig_gamma |>
  arrange(mean_gamma) |>
  mutate(
    method_id = factor(method_id, levels = unique(method_id)),
    direction = ifelse(mean_gamma > 0, "positive", "negative")
  )

p3 <- ggplot(sig_gamma, aes(x = mean_gamma, y = method_id, colour = direction)) +
  geom_point(size = 1.5) +
  geom_errorbarh(aes(xmin = lo90, xmax = hi90), height = 0.3, linewidth = 0.35) +
  scale_colour_manual(values = c("positive" = "firebrick", "negative" = "steelblue"),
                      guide = "none") +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  labs(
    x        = "Posterior mean gamma (post-LLM differential slope)",
    y        = NULL,
    title    = "L2-level: differential post-2023 method slopes (gamma_method)",
    subtitle = "Only methods where 90% CI excludes zero; red = gaining share, blue = losing share"
  ) +
  theme_minimal(base_size = 9) +
  theme(axis.text.y = element_text(size = 6), panel.grid.major.y = element_blank())

n_methods_shown <- nrow(sig_gamma)
plot_h3 <- max(6, 0.18 * n_methods_shown)
out3 <- file.path(OUTPUT_DIR, "l2_plot_gamma_dotplot.png")
ggsave(out3, p3, width = 12, height = plot_h3, units = "in", dpi = 150, limitsize = FALSE)
cat("Plot saved to:", out3, "\n")

# ── Top 10 methods by |gamma| ─────────────────────────────────────────────────
top10 <- gamma_df |>
  mutate(abs_gamma = abs(mean_gamma)) |>
  arrange(desc(abs_gamma)) |>
  slice_head(n = 10)

cat("\nTop 10 L2 methods by |mean_gamma|:\n")
print(top10 |> select(l1_group, level_2_mid, mean_gamma, lo90, hi90))

# ── Plot 4: raw counts for top 10 ────────────────────────────────────────────
cat("Plotting raw counts for top 10 L2 methods...\n")

raw_counts_list <- vector("list", nrow(top10))

for (i in seq_len(nrow(top10))) {
  g_i <- top10$g[i]
  k_i <- top10$k[i]

  raw_df <- data.frame(
    year     = year_levels,
    n_papers = as.integer(stan_data$counts[g_i, , k_i])
  )
  raw_df$method_id <- paste0(top10$l1_group[i], ": ", top10$level_2_mid[i])
  raw_counts_list[[i]] <- raw_df
}

raw_all <- bind_rows(raw_counts_list) |>
  mutate(method_id = factor(
    method_id,
    levels = paste0(top10$l1_group, ": ", top10$level_2_mid)
  ))

p4 <- ggplot(raw_all, aes(x = year, y = n_papers)) +
  geom_point(size = 1, colour = "grey40") +
  geom_smooth(method = "loess", formula = y ~ x, se = TRUE,
              colour = "darkorange3", fill = "darkorange", alpha = 0.2,
              linewidth = 1.2, span = 0.75) +
  geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
  annotate("text", x = 2023, y = Inf, label = "LLM adoption",
           hjust = -0.05, vjust = 1.5, size = 2.5, colour = "firebrick") +
  facet_wrap(~ method_id, scales = "free_y", ncol = 2) +
  labs(
    x = "Year", y = "Observed paper count",
    title    = "L2-level: top 10 methods raw observed paper counts 2010-2025",
    subtitle = "Orange = non-parametric loess smoother (NOT the Bayesian model); dashed = 2023 LLM adoption boundary"
  ) +
  theme_minimal(base_size = 8) +
  theme(strip.text = element_text(size = 6), panel.grid.minor = element_blank())

out4 <- file.path(OUTPUT_DIR, "l2_plot_raw_counts.png")
ggsave(out4, p4, width = 16, height = 10, units = "in", dpi = 150)
cat("Plot saved to:", out4, "\n")

# ── Extract diagnostic values for L2 doc auto-fill ────────────────────────────
n_divergences_l2    <- sum(rstan::get_divergent_iterations(l2_fit))
sm_diag_l2          <- rstan::summary(l2_fit, pars = c("sigma_beta", "sigma_gamma"))$summary
rhat_sigma_beta_l2  <- sm_diag_l2["sigma_beta",  "Rhat"]
rhat_sigma_gamma_l2 <- sm_diag_l2["sigma_gamma", "Rhat"]
ess_sigma_beta_l2   <- sm_diag_l2["sigma_beta",  "n_eff"]
ess_sigma_gamma_l2  <- sm_diag_l2["sigma_gamma", "n_eff"]
sigma_beta_mean_l2  <- sm_diag_l2["sigma_beta",  "mean"]
sigma_gamma_mean_l2 <- sm_diag_l2["sigma_gamma", "mean"]
sigma_beta_ci_str_l2  <- paste0("[", round(sm_diag_l2["sigma_beta",  "2.5%"],  4),
                                 ", ", round(sm_diag_l2["sigma_beta",  "97.5%"], 4), "]")
sigma_gamma_ci_str_l2 <- paste0("[", round(sm_diag_l2["sigma_gamma", "2.5%"],  4),
                                 ", ", round(sm_diag_l2["sigma_gamma", "97.5%"], 4), "]")

# ── Auto-push L2 results to GitHub ────────────────────────────────────────────
message("Pushing L2 results to GitHub...")
results_text <- readLines("docs/l2_results.md")
results_text <- gsub("{{DIVERGENCES_L2}}",     n_divergences_l2,                                    results_text, fixed = TRUE)
results_text <- gsub("{{RHAT_SIGMA_BETA_L2}}",  round(rhat_sigma_beta_l2,  4),                      results_text, fixed = TRUE)
results_text <- gsub("{{RHAT_SIGMA_GAMMA_L2}}", round(rhat_sigma_gamma_l2, 4),                      results_text, fixed = TRUE)
results_text <- gsub("{{ESS_SIGMA_BETA_L2}}",   round(ess_sigma_beta_l2),                           results_text, fixed = TRUE)
results_text <- gsub("{{ESS_SIGMA_GAMMA_L2}}",  round(ess_sigma_gamma_l2),                          results_text, fixed = TRUE)
results_text <- gsub("{{SIGMA_BETA_MEAN_L2}}",  round(sigma_beta_mean_l2,  4),                      results_text, fixed = TRUE)
results_text <- gsub("{{SIGMA_BETA_CI_L2}}",    sigma_beta_ci_str_l2,                               results_text, fixed = TRUE)
results_text <- gsub("{{SIGMA_GAMMA_MEAN_L2}}", round(sigma_gamma_mean_l2, 4),                      results_text, fixed = TRUE)
results_text <- gsub("{{SIGMA_GAMMA_CI_L2}}",   sigma_gamma_ci_str_l2,                              results_text, fixed = TRUE)
results_text <- gsub("{{RATIO_L2}}",            round(sigma_gamma_mean_l2 / sigma_beta_mean_l2, 3), results_text, fixed = TRUE)
writeLines(results_text, "docs/l2_results.md")
system("git -C ~/R_projects/Vibe_Coding_Paper add data/output/l2/*.png docs/l2_results.md && git -C ~/R_projects/Vibe_Coding_Paper commit -m 'auto: L2 model results update' && git -C ~/R_projects/Vibe_Coding_Paper push")

# ── L2 phi-free fit ──────────────────────────────────────────────────────────
FIT_L2_KF_RDS  <- "data/output/l2/fit_l2_phi_free.rds"
KF_OUTPUT_DIR  <- "data/output/l2/phi_free"
dir.create(KF_OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Stan model: same structure as stan_code but phi estimated as exp(log_phi)
stan_code_phi_free <- "
functions {
  real dm_log(array[] int n, vector alpha) {
    real a0 = sum(alpha);
    int N = sum(n);
    return lgamma(a0) - lgamma(a0 + N)
         + sum(lgamma(alpha + to_vector(n))) - sum(lgamma(alpha));
  }
}

data {
  int<lower=1> N_groups;
  int<lower=1> N_years;
  int<lower=1> K_max;
  array[N_groups] int<lower=1> K_g;
  array[N_groups, N_years, K_max] int<lower=0> counts;
  vector[N_years] year_std;
  array[N_years] int post_llm;
}

parameters {
  real log_phi;
  array[N_groups] vector[K_max] mu_raw;
  array[N_groups] vector[K_max] beta_method_raw;
  real<lower=0> sigma_beta;
  array[N_groups] vector[K_max] gamma_method_raw;
  real<lower=0> sigma_gamma;
}

transformed parameters {
  real<lower=0> phi = exp(log_phi);
  array[N_groups] vector[K_max] beta_method;
  array[N_groups] vector[K_max] gamma_method;
  for (g in 1:N_groups) {
    beta_method[g]  = sigma_beta  * beta_method_raw[g];
    gamma_method[g] = sigma_gamma * gamma_method_raw[g];
  }
}

model {
  log_phi     ~ normal(log(100), 1.0);
  sigma_beta  ~ exponential(2);
  sigma_gamma ~ exponential(4);

  for (g in 1:N_groups) {
    int K = K_g[g];

    mu_raw[g][1:K] ~ normal(0, 1);
    sum(mu_raw[g][1:K]) ~ normal(0, 0.001 * K);

    beta_method_raw[g][1:K] ~ normal(0, 1);
    sum(beta_method_raw[g][1:K]) ~ normal(0, 0.001 * K);

    gamma_method_raw[g][1:K] ~ normal(0, 1);
    sum(gamma_method_raw[g][1:K]) ~ normal(0, 0.001 * K);

    if (K < K_max) {
      mu_raw[g][(K+1):K_max]           ~ normal(0, 0.001);
      beta_method_raw[g][(K+1):K_max]  ~ normal(0, 0.001);
      gamma_method_raw[g][(K+1):K_max] ~ normal(0, 0.001);
    }
  }

  for (g in 1:N_groups) {
    int K = K_g[g];
    for (t in 1:N_years) {
      if (sum(counts[g, t, 1:K]) == 0) continue;

      vector[K] eta   = mu_raw[g][1:K]
                        + beta_method[g][1:K]  * year_std[t]
                        + gamma_method[g][1:K] * post_llm[t];
      vector[K] alpha = softmax(eta) * phi;
      array[K] int y  = counts[g, t, 1:K];

      target += dm_log(y, alpha);
    }
  }
}

generated quantities {
  matrix[N_groups, N_years] inv_simpson;
  matrix[N_groups, N_years] eff_N_shannon;

  for (g in 1:N_groups) {
    int K = K_g[g];
    for (t in 1:N_years) {
      vector[K] eta = mu_raw[g][1:K]
                      + beta_method[g][1:K]  * year_std[t]
                      + gamma_method[g][1:K] * post_llm[t];

      int N_gt = sum(counts[g, t, 1:K]);
      vector[K] p;

      if (N_gt > 0) {
        vector[K] y_k;
        for (k in 1:K) y_k[k] = counts[g, t, k];
        p = dirichlet_rng(softmax(eta) * phi + y_k);
      } else {
        p = softmax(eta);
      }

      inv_simpson[g, t]   = 1.0 / dot_self(p);
      eff_N_shannon[g, t] = exp(-dot_product(p, log(p)));
    }
  }
}
"

# ── Fit (guarded) ──────────────────────────────────────────────────────────────
if (!file.exists(FIT_L2_KF_RDS)) {
  cat("Compiling and sampling L2 phi-free model...\n")
  cat("Prior: log_phi ~ N(log(100), 1.0)  [phi median=100, 90% CI ~14-716]\n")
  cat("Settings: chains=4, iter=3000, warmup=1500, max_treedepth=14\n")

  stan_data_kf       <- stan_data
  stan_data_kf$phi <- NULL  # phi is now a parameter

  l2_mod_kf <- stan_model(model_code = stan_code_phi_free)

  t_start_kf <- proc.time()
  l2_fit_kf <- suppressWarnings(sampling(
    l2_mod_kf,
    data    = stan_data_kf,
    chains  = 4,
    iter    = 3000,
    warmup  = 1500,
    cores   = 4,
    seed    = 42,
    control = list(adapt_delta = 0.95, max_treedepth = 14),
    refresh = 100
  ))

  t_elapsed_kf   <- proc.time() - t_start_kf
  elapsed_min_kf <- round(t_elapsed_kf["elapsed"] / 60, 1)
  cat("L2 phi-free sampling done. Elapsed:", elapsed_min_kf, "minutes\n")

  cat("\n--- L2 phi-free HMC diagnostics ---\n")
  check_hmc_diagnostics(l2_fit_kf)
  cat("\n--- sigma_beta ---\n");  print(summary(l2_fit_kf, pars = "sigma_beta")$summary)
  cat("\n--- sigma_gamma ---\n"); print(summary(l2_fit_kf, pars = "sigma_gamma")$summary)
  cat("\n--- phi ---\n");         print(summary(l2_fit_kf, pars = "phi")$summary)

  saveRDS(l2_fit_kf, FIT_L2_KF_RDS)
  cat("L2 phi-free fit saved to:", FIT_L2_KF_RDS, "\n")

  # Telegram diagnostics
  tryCatch({
    n_div_kf <- sum(rstan::get_divergent_iterations(l2_fit_kf))
    sm_kf    <- rstan::summary(l2_fit_kf,
                               pars  = c("sigma_beta", "sigma_gamma", "phi"),
                               probs = c(0.05, 0.95))$summary

    fmt_kf <- function(par) {
      sprintf("%s: mean=%.4f 90%%CI=[%.4f,%.4f]  Rhat=%.3f  ESS=%d",
              par,
              sm_kf[par, "mean"],  sm_kf[par, "5%"],  sm_kf[par, "95%"],
              sm_kf[par, "Rhat"],  round(sm_kf[par, "n_eff"]))
    }

    msg_kf <- paste(
      paste0("L2 phi-free diagnostics  Divergences: ",
             if (n_div_kf == 0) "0" else paste0(n_div_kf, " !!!")),
      fmt_kf("sigma_beta"),
      fmt_kf("sigma_gamma"),
      fmt_kf("phi"),
      paste0("Runtime: ", elapsed_min_kf, " min"),
      sep = "\n"
    )
    httr::POST(url    = paste0("https://api.telegram.org/bot", token, "/sendMessage"),
               body   = list(chat_id = chat_id, text = msg_kf),
               encode = "form")
  }, error = function(e) message("Telegram L2 phi-free diagnostics error: ", conditionMessage(e)))

} else {
  elapsed_min_kf <- NA_real_
  message("fit_l2_phi_free.rds already exists — loading.")
  l2_fit_kf <- readRDS(FIT_L2_KF_RDS)
}

# ── Post-processing: always runs ───────────────────────────────────────────────
{
  mu_raw_kf    <- rstan::extract(l2_fit_kf, pars = "mu_raw")$mu_raw
  beta_kf      <- rstan::extract(l2_fit_kf, pars = "beta_method")$beta_method
  gamma_kf     <- rstan::extract(l2_fit_kf, pars = "gamma_method")$gamma_method
  inv_simp_kf  <- rstan::extract(l2_fit_kf, pars = "inv_simpson")$inv_simpson
  phi_draws_kf <- rstan::extract(l2_fit_kf, pars = "phi")$phi
  sg_draws_kf  <- rstan::extract(l2_fit_kf, pars = "sigma_gamma")$sigma_gamma
  sb_draws_kf  <- rstan::extract(l2_fit_kf, pars = "sigma_beta")$sigma_beta
  # also grab phi=10 reference draws for comparison panels
  sb_draws_ref <- rstan::extract(l2_fit,    pars = "sigma_beta")$sigma_beta
  sg_draws_ref <- rstan::extract(l2_fit,    pars = "sigma_gamma")$sigma_gamma

  S_kf <- dim(mu_raw_kf)[1]

  KF_PLOT_SIGMA     <- file.path(KF_OUTPUT_DIR, "l2_kf_plot_sigma_posteriors.png")
  KF_PLOT_DIVERSITY <- file.path(KF_OUTPUT_DIR, "l2_kf_plot_diversity_by_group.png")
  KF_PLOT_GAMMA_DOT <- file.path(KF_OUTPUT_DIR, "l2_kf_plot_gamma_dotplot.png")
  KF_PLOT_TOP_GAMMA <- file.path(KF_OUTPUT_DIR, "l2_kf_plot_top_gamma_trajectories.png")
  KF_PLOT_RAW       <- file.path(KF_OUTPUT_DIR, "l2_kf_plot_raw_counts.png")

  # ── Plot 1: sigma posteriors + phi ─────────────────────────────────────────
  sigma_df_kf <- data.frame(
    value     = c(sb_draws_kf, sb_draws_ref, sg_draws_kf, sg_draws_ref),
    parameter = c(rep("sigma_beta",  length(sb_draws_kf)),
                  rep("sigma_beta",  length(sb_draws_ref)),
                  rep("sigma_gamma", length(sg_draws_kf)),
                  rep("sigma_gamma", length(sg_draws_ref))),
    model     = c(rep("phi free", length(sb_draws_kf)),
                  rep("phi=10",   length(sb_draws_ref)),
                  rep("phi free", length(sg_draws_kf)),
                  rep("phi=10",   length(sg_draws_ref)))
  )

  x_phi_max <- quantile(phi_draws_kf, 0.999)
  x_phi_seq <- seq(0.1, x_phi_max * 1.5, length.out = 500)
  phi_prior_df_kf <- data.frame(
    value   = x_phi_seq,
    density = dlnorm(x_phi_seq, log(100), 1.0)
  )

  p_sb_kf <- ggplot(sigma_df_kf |> filter(parameter == "sigma_beta"),
                    aes(x = value, colour = model, linetype = model)) +
    geom_density(fill = NA) +
    scale_colour_manual(values = c("phi free" = "steelblue", "phi=10" = "steelblue4")) +
    scale_linetype_manual(values = c("phi free" = "solid", "phi=10" = "dashed")) +
    labs(x = "sigma_beta", y = "Density", title = "sigma_beta", colour = NULL, linetype = NULL) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom")

  p_sg_kf <- ggplot(sigma_df_kf |> filter(parameter == "sigma_gamma"),
                    aes(x = value, colour = model, linetype = model)) +
    geom_density(fill = NA) +
    scale_colour_manual(values = c("phi free" = "firebrick", "phi=10" = "firebrick4")) +
    scale_linetype_manual(values = c("phi free" = "solid", "phi=10" = "dashed")) +
    labs(x = "sigma_gamma", y = "Density", title = "sigma_gamma (post-LLM shift)",
         colour = NULL, linetype = NULL) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom")

  p_phi_kf <- ggplot(data.frame(value = phi_draws_kf), aes(x = value)) +
    geom_density(colour = "darkorchid", fill = "darkorchid", alpha = 0.3) +
    geom_line(data = phi_prior_df_kf, aes(x = value, y = density),
              linetype = "dashed", colour = "grey40", inherit.aes = FALSE) +
    coord_cartesian(xlim = c(0, x_phi_max * 1.2)) +
    labs(x = "phi", y = "Density",
         title = "phi: posterior (solid) vs prior (dashed)",
         subtitle = "log_phi ~ N(log(100), 1.0)") +
    theme_minimal(base_size = 11)

  p2_kf <- gridExtra::arrangeGrob(
    p_sb_kf, p_sg_kf, p_phi_kf, nrow = 1,
    top = "L2 phi-free: sigma posteriors vs phi=10 reference"
  )
  ggsave(KF_PLOT_SIGMA, p2_kf, width = 10, height = 5, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_SIGMA, "\n")

  # ── Plot 2: diversity by L1 group ─────────────────────────────────────────
  conj_kf <- do.call(rbind, lapply(seq_len(N_groups), function(g) {
    do.call(rbind, lapply(seq_len(N_years), function(t) {
      vals <- inv_simp_kf[, g, t]
      data.frame(l1_group = l1_levels[g], year = year_levels[t],
                 median = median(vals),
                 lo90 = quantile(vals, 0.05), hi90 = quantile(vals, 0.95),
                 lo50 = quantile(vals, 0.25), hi50 = quantile(vals, 0.75),
                 stringsAsFactors = FALSE)
    }))
  }))

  p1_kf <- ggplot(conj_kf, aes(x = year)) +
    geom_point(data = emp_diversity_l2,
               aes(y = inv_simp_emp, colour = "Observed (annual)"),
               size = 0.8, alpha = 0.7) +
    geom_ribbon(aes(ymin = lo90, ymax = hi90), alpha = 0.15, fill = "steelblue") +
    geom_ribbon(aes(ymin = lo50, ymax = hi50), alpha = 0.30, fill = "steelblue") +
    geom_line(aes(y = median, colour = "Posterior median"), linewidth = 0.6) +
    geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
    annotate("text", x = 2023, y = Inf, label = "LLM adoption",
             hjust = -0.05, vjust = 1.5, size = 2.5, colour = "firebrick") +
    scale_colour_manual(
      values = c("Observed (annual)" = "grey40", "Posterior median" = "steelblue4"),
      name   = NULL
    ) +
    facet_wrap(~ l1_group, scales = "free_y") +
    labs(x = "Year", y = "Inverse Simpson (effective N of L2 methods)",
         title    = "L2 phi-free: diversity within L1 groups over time",
         subtitle = "Grey dots = observed; ribbon = 50%/90% posterior CIs") +
    theme_minimal(base_size = 9) +
    theme(strip.text = element_text(size = 7), panel.grid.minor = element_blank(),
          legend.position = "bottom")

  ggsave(KF_PLOT_DIVERSITY, p1_kf, width = 14, height = 10, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_DIVERSITY, "\n")

  # ── Extract gamma posteriors ───────────────────────────────────────────────
  gamma_list_kf <- vector("list", N_groups)
  for (grp in seq_len(N_groups)) {
    K   <- K_g[grp]
    g_m <- matrix(gamma_kf[, grp, 1:K], nrow = S_kf, ncol = K)
    method_labels <- l2_vocab |> filter(g == grp) |> arrange(k_local) |> pull(level_2_mid)
    gamma_list_kf[[grp]] <- data.frame(
      g           = grp,
      l1_group    = l1_levels[grp],
      k           = seq_len(K),
      level_2_mid = method_labels,
      mean_gamma  = colMeans(g_m),
      lo90        = apply(g_m, 2, quantile, 0.05),
      hi90        = apply(g_m, 2, quantile, 0.95),
      stringsAsFactors = FALSE
    )
  }

  gamma_df_kf <- bind_rows(gamma_list_kf) |>
    mutate(sig       = (lo90 > 0 | hi90 < 0),
           method_id = paste0(l1_group, ": ", level_2_mid))
  cat("L2 phi-free methods with 90% CI excluding zero:", sum(gamma_df_kf$sig, na.rm = TRUE), "\n")

  # ── Plot 3: gamma dotplot ─────────────────────────────────────────────────
  sig_gamma_kf <- gamma_df_kf |> filter(sig)
  if (nrow(sig_gamma_kf) == 0) { cat("WARNING: no sig gamma; showing all\n"); sig_gamma_kf <- gamma_df_kf }
  sig_gamma_kf <- sig_gamma_kf |>
    arrange(mean_gamma) |>
    mutate(method_id = factor(method_id, levels = unique(method_id)),
           direction = ifelse(mean_gamma > 0, "positive", "negative"))

  p3_kf <- ggplot(sig_gamma_kf, aes(x = mean_gamma, y = method_id, colour = direction)) +
    geom_point(size = 1.5) +
    geom_errorbarh(aes(xmin = lo90, xmax = hi90), height = 0.3, linewidth = 0.35) +
    scale_colour_manual(values = c("positive" = "firebrick", "negative" = "steelblue"),
                        guide = "none") +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
    labs(x = "Posterior mean gamma (post-LLM differential slope)", y = NULL,
         title    = "L2 phi-free: differential post-2023 method slopes",
         subtitle = "90% CI excludes zero; red = gaining, blue = losing") +
    theme_minimal(base_size = 9) +
    theme(axis.text.y = element_text(size = 6), panel.grid.major.y = element_blank())

  plot_h_kf <- max(6, 0.18 * nrow(sig_gamma_kf))
  ggsave(KF_PLOT_GAMMA_DOT, p3_kf, width = 12, height = plot_h_kf, units = "in", dpi = 150,
         limitsize = FALSE)
  cat("Plot saved:", KF_PLOT_GAMMA_DOT, "\n")

  # ── Top 15 by |gamma| ─────────────────────────────────────────────────────
  top15_kf <- gamma_df_kf |>
    mutate(abs_gamma = abs(mean_gamma)) |>
    arrange(desc(abs_gamma)) |>
    slice_head(n = 15)

  cat("\nTop 15 L2 methods by |mean_gamma| (phi-free):\n")
  print(top15_kf |> select(l1_group, level_2_mid, mean_gamma, lo90, hi90))

  # ── Plot 4: share trajectories for top 15 ────────────────────────────────
  n_draws_traj_kf <- min(200, S_kf)
  draw_idx_kf     <- sample(S_kf, n_draws_traj_kf)

  traj_list_kf <- vector("list", nrow(top15_kf))
  for (i in seq_len(nrow(top15_kf))) {
    g_i  <- top15_kf$g[i]
    k_i  <- top15_kf$k[i]
    K    <- K_g[g_i]
    share_mat <- matrix(0, nrow = n_draws_traj_kf, ncol = N_years)
    for (di in seq_len(n_draws_traj_kf)) {
      s <- draw_idx_kf[di]
      for (t in seq_len(N_years)) {
        eta_vec <- mu_raw_kf[s, g_i, 1:K] +
                   beta_kf[s, g_i, 1:K]  * year_std[t] +
                   gamma_kf[s, g_i, 1:K] * post_llm[t]
        p_vec   <- exp(eta_vec - max(eta_vec)); p_vec <- p_vec / sum(p_vec)
        share_mat[di, t] <- p_vec[k_i]
      }
    }
    method_label <- paste0(top15_kf$l1_group[i], ": ", top15_kf$level_2_mid[i])
    traj_list_kf[[i]] <- data.frame(
      year      = year_levels,
      mean      = colMeans(share_mat),
      lo80      = apply(share_mat, 2, quantile, 0.10),
      hi80      = apply(share_mat, 2, quantile, 0.90),
      lo90      = apply(share_mat, 2, quantile, 0.05),
      hi90      = apply(share_mat, 2, quantile, 0.95),
      method_id = method_label
    )
  }

  traj_all_kf <- bind_rows(traj_list_kf) |>
    mutate(method_id = factor(method_id, levels = unique(method_id)))

  p4_kf <- ggplot(traj_all_kf, aes(x = year)) +
    geom_ribbon(aes(ymin = lo90, ymax = hi90), alpha = 0.15, fill = "steelblue") +
    geom_ribbon(aes(ymin = lo80, ymax = hi80), alpha = 0.25, fill = "steelblue") +
    geom_line(aes(y = mean), colour = "steelblue4", linewidth = 0.7) +
    geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
    annotate("text", x = 2023, y = Inf, label = "LLM adoption",
             hjust = -0.05, vjust = 1.5, size = 2, colour = "firebrick") +
    facet_wrap(~ method_id, scales = "free_y", ncol = 3) +
    labs(x = "Year", y = "Fitted method share",
         title    = "L2 phi-free: top 15 L2 methods — fitted share trajectories",
         subtitle = "Ribbon = 80%/90% CI from 200 posterior draws; dashed = 2023") +
    theme_minimal(base_size = 7) +
    theme(strip.text = element_text(size = 5), panel.grid.minor = element_blank())

  ggsave(KF_PLOT_TOP_GAMMA, p4_kf, width = 18, height = 12, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_TOP_GAMMA, "\n")

  # ── Plot 5: raw counts for top 15 ─────────────────────────────────────────
  raw_list_kf <- vector("list", nrow(top15_kf))
  for (i in seq_len(nrow(top15_kf))) {
    g_i <- top15_kf$g[i]; k_i <- top15_kf$k[i]
    raw_df <- data.frame(year = year_levels,
                         n_papers = as.integer(stan_data$counts[g_i, , k_i]))
    raw_df$method_id <- paste0(top15_kf$l1_group[i], ": ", top15_kf$level_2_mid[i])
    raw_list_kf[[i]] <- raw_df
  }
  raw_all_kf <- bind_rows(raw_list_kf) |>
    mutate(method_id = factor(
      method_id,
      levels = paste0(top15_kf$l1_group, ": ", top15_kf$level_2_mid)
    ))

  p5_kf <- ggplot(raw_all_kf, aes(x = year, y = n_papers)) +
    geom_point(size = 1, colour = "grey40") +
    geom_smooth(method = "loess", formula = y ~ x, se = TRUE,
                colour = "darkorange3", fill = "darkorange", alpha = 0.2,
                linewidth = 1.2, span = 0.75) +
    geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
    annotate("text", x = 2023, y = Inf, label = "LLM adoption",
             hjust = -0.05, vjust = 1.5, size = 2, colour = "firebrick") +
    facet_wrap(~ method_id, scales = "free_y", ncol = 3) +
    labs(x = "Year", y = "Observed paper count",
         title    = "L2 phi-free: top 15 L2 methods — raw observed counts",
         subtitle = "Orange = loess smoother; dashed = 2023") +
    theme_minimal(base_size = 7) +
    theme(strip.text = element_text(size = 5), panel.grid.minor = element_blank())

  ggsave(KF_PLOT_RAW, p5_kf, width = 18, height = 12, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_RAW, "\n")

  # ── Telegram: send all 5 phi-free plots ─────────────────────────────────
  kf_plots <- c(KF_PLOT_SIGMA, KF_PLOT_DIVERSITY, KF_PLOT_GAMMA_DOT,
                KF_PLOT_TOP_GAMMA, KF_PLOT_RAW)
  cat("\nSending L2 phi-free plots via Telegram...\n")
  for (plot_path in kf_plots) {
    tryCatch({
      resp <- httr::POST(
        url  = paste0("https://api.telegram.org/bot", token, "/sendPhoto"),
        body = list(chat_id = chat_id,
                    photo   = httr::upload_file(plot_path),
                    caption = paste0("L2 phi-free: ", basename(plot_path))),
        encode = "multipart"
      )
      cat("Telegram photo HTTP", httr::status_code(resp), ":", basename(plot_path), "\n")
    }, error = function(e) {
      cat("WARNING: Telegram photo failed:", basename(plot_path), ":", conditionMessage(e), "\n")
    })
  }

  # ── Auto-push: fill l2_results.md placeholders and push ─────────────────
  message("Filling l2_results.md phi-free placeholders...")

  sm_kf_full <- rstan::summary(l2_fit_kf,
                               pars  = c("phi", "sigma_beta", "sigma_gamma"),
                               probs = c(0.025, 0.05, 0.95, 0.975))$summary

  phi_mean_kf   <- round(sm_kf_full["phi",       "mean"],  1)
  phi_ci_kf     <- paste0("[", round(sm_kf_full["phi",       "2.5%"],  1),
                           ", ", round(sm_kf_full["phi",       "97.5%"], 1), "]")
  sg_mean_kf    <- round(sm_kf_full["sigma_gamma", "mean"],  4)
  sg_ci_kf      <- paste0("[", round(sm_kf_full["sigma_gamma", "5%"],   4),
                           ", ", round(sm_kf_full["sigma_gamma", "95%"],  4), "]")
  sb_mean_kf    <- round(sm_kf_full["sigma_beta",  "mean"],  4)
  sg_rhat_kf    <- round(sm_kf_full["sigma_gamma", "Rhat"],  4)
  sg_ess_kf     <- round(sm_kf_full["sigma_gamma", "n_eff"])
  ratio_kf      <- round(sg_mean_kf / sb_mean_kf, 3)
  converged_kf  <- ifelse(sg_rhat_kf < 1.01 & sg_ess_kf > 400,
                          "YES (Rhat OK, ESS OK)",
                          paste0("PARTIAL (Rhat=", sg_rhat_kf, ", ESS=", sg_ess_kf, ")"))
  runtime_kf    <- if (is.na(elapsed_min_kf)) "N/A (loaded)" else as.character(elapsed_min_kf)

  l2_doc <- readLines("docs/l2_results.md")
  l2_doc <- gsub("{{L2_PHI_FREE_PHI_MEAN}}",        phi_mean_kf,   l2_doc, fixed = TRUE)
  l2_doc <- gsub("{{L2_PHI_FREE_PHI_CI}}",           phi_ci_kf,    l2_doc, fixed = TRUE)
  l2_doc <- gsub("{{L2_PHI_FREE_SIGMA_GAMMA_MEAN}}", sg_mean_kf,   l2_doc, fixed = TRUE)
  l2_doc <- gsub("{{L2_PHI_FREE_SIGMA_GAMMA_CI}}",   sg_ci_kf,     l2_doc, fixed = TRUE)
  l2_doc <- gsub("{{L2_PHI_FREE_SIGMA_BETA_MEAN}}",  sb_mean_kf,   l2_doc, fixed = TRUE)
  l2_doc <- gsub("{{L2_PHI_FREE_RHAT}}",             sg_rhat_kf,   l2_doc, fixed = TRUE)
  l2_doc <- gsub("{{L2_PHI_FREE_ESS}}",              sg_ess_kf,    l2_doc, fixed = TRUE)
  l2_doc <- gsub("{{L2_PHI_FREE_RUNTIME}}",          runtime_kf,   l2_doc, fixed = TRUE)
  l2_doc <- gsub("{{L2_PHI_FREE_CONVERGED}}",        converged_kf, l2_doc, fixed = TRUE)
  l2_doc <- gsub("{{L2_PHI_FREE_RATIO}}",            ratio_kf,     l2_doc, fixed = TRUE)
  writeLines(l2_doc, "docs/l2_results.md")

  system(paste0(
    "cd ~/R_projects/Vibe_Coding_Paper && ",
    "git add docs/l2_results.md data/output/l2/phi_free/*.png && ",
    "git commit -m 'auto: L2 phi-free results and plots' && ",
    "git push"
  ))
  message("L2 phi-free GitHub push complete.")
}

cat("=== 03_l2_analysis.R DONE ===\n")
