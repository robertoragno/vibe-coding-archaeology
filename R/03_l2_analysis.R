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
FIT_L2_RDS <- "data/output/l2/fit_l2.rds"
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
  kappa     = 10.0,
  year_std  = year_std,
  post_llm  = post_llm
)

# ── Inline Stan model (identical structure to diversity_model.stan) ───────────
# No non-ASCII characters in Stan code. Hand-rolled dm_log, no built-in
# dirichlet_multinomial. kappa fixed at 10 as data input.
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
  real<lower=0> kappa;
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
      vector[K] alpha = softmax(eta) * kappa;
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
      vector[K] p   = softmax(eta);

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

  sm <- rstan::summary(l2_fit, pars = c("sigma_beta", "sigma_gamma"))$summary

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
cat("\nComputing inv_simpson summary per L1 group...\n")

inv_simp_tidy <- expand.grid(
    draw = seq_len(S),
    g    = seq_len(N_groups),
    t    = seq_len(N_years)
  ) |>
  mutate(
    inv_simpson = mapply(function(d, g, t) inv_simp_arr[d, g, t], draw, g, t),
    l1_group    = l1_levels[g],
    year        = year_levels[t]
  )

inv_simp_summary <- inv_simp_tidy |>
  group_by(l1_group, year) |>
  summarise(
    median = median(inv_simpson),
    lo90   = quantile(inv_simpson, 0.05),
    hi90   = quantile(inv_simpson, 0.95),
    lo50   = quantile(inv_simpson, 0.25),
    hi50   = quantile(inv_simpson, 0.75),
    .groups = "drop"
  )

p1 <- ggplot(inv_simp_summary, aes(x = year, y = median)) +
  geom_ribbon(aes(ymin = lo90, ymax = hi90), alpha = 0.15, fill = "steelblue") +
  geom_ribbon(aes(ymin = lo50, ymax = hi50), alpha = 0.30, fill = "steelblue") +
  geom_line(colour = "steelblue4", linewidth = 0.6) +
  geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
  annotate("text", x = 2023, y = Inf, label = "LLM adoption",
           hjust = -0.05, vjust = 1.5, size = 2.5, colour = "firebrick") +
  facet_wrap(~ l1_group, scales = "free_y") +
  labs(
    x = "Year", y = "Inverse Simpson (effective N of L2 methods)",
    title    = "L2-level: methodological diversity within L1 groups over time",
    subtitle = "Ribbon = 50% and 90% posterior credible intervals"
  ) +
  theme_minimal(base_size = 9) +
  theme(strip.text = element_text(size = 7), panel.grid.minor = element_blank())

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

# ── Plot 4: fitted share trajectories for top 10 ─────────────────────────────
cat("Plotting fitted share trajectories for top 10 L2 methods...\n")

draw_idx <- sample(seq_len(S), min(200, S))

traj_list <- vector("list", nrow(top10))

for (i in seq_len(nrow(top10))) {
  g_i <- top10$g[i]
  k_i <- top10$k[i]
  K_i <- K_g[g_i]

  # matrix() guards against K==1 dimension drop
  mu_g  <- matrix(mu_raw_arr[, g_i, 1:K_i],      nrow = S, ncol = K_i)
  bm_g  <- matrix(beta_method_arr[, g_i, 1:K_i],  nrow = S, ncol = K_i)
  gm_g  <- matrix(gamma_method_arr[, g_i, 1:K_i], nrow = S, ncol = K_i)

  mu_mean <- colMeans(mu_g)
  bm_mean <- colMeans(bm_g)
  gm_mean <- colMeans(gm_g)

  eta_mean_mat <- outer(bm_mean, year_std, "*") + outer(gm_mean, post_llm, "*")
  eta_mean_mat <- sweep(eta_mean_mat, 1, mu_mean, "+")

  p_mean_mat <- apply(eta_mean_mat, 2, function(e) {
    e <- e - max(e)
    exp(e) / sum(exp(e))
  })  # [K_i, N_years]
  p_mean_k <- p_mean_mat[k_i, ]

  p_draws_k <- matrix(NA_real_, nrow = length(draw_idx), ncol = N_years)
  for (di in seq_along(draw_idx)) {
    s <- draw_idx[di]
    for (ti in seq_len(N_years)) {
      eta_s <- mu_g[s, ] + bm_g[s, ] * year_std[ti] + gm_g[s, ] * post_llm[ti]
      eta_s <- eta_s - max(eta_s)
      p_s   <- exp(eta_s) / sum(exp(eta_s))
      p_draws_k[di, ti] <- p_s[k_i]
    }
  }

  method_label <- paste0(top10$l1_group[i], ": ", top10$level_2_mid[i])

  mean_df <- data.frame(
    method_id = method_label,
    year      = year_levels,
    p_mean    = p_mean_k,
    lo90      = apply(p_draws_k, 2, quantile, 0.05),
    hi90      = apply(p_draws_k, 2, quantile, 0.95),
    lo80      = apply(p_draws_k, 2, quantile, 0.10),
    hi80      = apply(p_draws_k, 2, quantile, 0.90)
  )
  traj_list[[i]] <- mean_df
}

traj_all <- bind_rows(traj_list) |>
  mutate(method_id = factor(
    method_id,
    levels = paste0(top10$l1_group, ": ", top10$level_2_mid)
  ))

p4 <- ggplot(traj_all, aes(x = year)) +
  geom_ribbon(aes(ymin = lo90, ymax = hi90), alpha = 0.12, fill = "steelblue") +
  geom_ribbon(aes(ymin = lo80, ymax = hi80), alpha = 0.20, fill = "steelblue") +
  geom_line(aes(y = p_mean), colour = "steelblue4", linewidth = 0.5) +
  geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
  annotate("text", x = 2023, y = Inf, label = "LLM adoption",
           hjust = -0.05, vjust = 1.5, size = 2.5, colour = "firebrick") +
  facet_wrap(~ method_id, scales = "free_y", ncol = 2) +
  labs(
    x = "Year", y = "Fitted softmax share",
    title    = "L2-level: top 10 methods by |gamma|: fitted share trajectories 2010-2025",
    subtitle = "Mean line + 80%/90% CI from 200 random draws; dashed = 2023 (LLM adoption)"
  ) +
  theme_minimal(base_size = 8) +
  theme(strip.text = element_text(size = 6), panel.grid.minor = element_blank())

out4 <- file.path(OUTPUT_DIR, "l2_plot_top_gamma_trajectories.png")
ggsave(out4, p4, width = 16, height = 10, units = "in", dpi = 150)
cat("Plot saved to:", out4, "\n")

# ── Plot 5: raw counts for top 10 ────────────────────────────────────────────
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

p5 <- ggplot(raw_all, aes(x = year, y = n_papers)) +
  geom_point(size = 1, colour = "grey40") +
  geom_smooth(method = "loess", se = FALSE, colour = "steelblue4",
              linewidth = 0.5, span = 0.75) +
  geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
  annotate("text", x = 2023, y = Inf, label = "LLM adoption",
           hjust = -0.05, vjust = 1.5, size = 2.5, colour = "firebrick") +
  facet_wrap(~ method_id, scales = "free_y", ncol = 2) +
  labs(
    x = "Year", y = "Observed paper count",
    title    = "L2-level: top 10 methods raw observed paper counts 2010-2025",
    subtitle = "Loess smoother; dashed = 2023; sanity check against fitted trajectories"
  ) +
  theme_minimal(base_size = 8) +
  theme(strip.text = element_text(size = 6), panel.grid.minor = element_blank())

out5 <- file.path(OUTPUT_DIR, "l2_plot_raw_counts.png")
ggsave(out5, p5, width = 16, height = 10, units = "in", dpi = 150)
cat("Plot saved to:", out5, "\n")

# ── Telegram: send all L2 plots ───────────────────────────────────────────────
all_plots <- c(out1, out2, out3, out4, out5)

cat("\nSending L2 plots via Telegram...\n")
for (plot_path in all_plots) {
  cat("Sending:", basename(plot_path), "\n")
  tryCatch({
    resp <- httr::POST(
      url  = paste0("https://api.telegram.org/bot", token, "/sendPhoto"),
      body = list(
        chat_id = chat_id,
        photo   = httr::upload_file(plot_path),
        caption = paste0("L2 analysis: ", basename(plot_path))
      ),
      encode = "multipart"
    )
    status <- httr::status_code(resp)
    cat("HTTP status:", status, "\n")
    if (status != 200) {
      cat("Response content:\n")
      print(httr::content(resp, as = "text", encoding = "UTF-8"))
    }
  }, error = function(e) {
    cat("WARNING: failed to send", basename(plot_path), ":", conditionMessage(e), "\n")
  })
}

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

cat("=== 03_l2_analysis.R DONE ===\n")
