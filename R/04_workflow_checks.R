cat("=== 04_workflow_checks.R ===\n")
cat("Gelman et al. (arXiv:2011.01808) Bayesian Workflow checks\n")
cat("Sections: (1) Prior Predictive, (2) PPC, (3) Fake Data, (4) Sensitivity, (5) Summary\n\n")

library(rstan)
library(dplyr)
library(tidyr)
library(ggplot2)
library(httr)

options(mc.cores = parallel::detectCores())
rstan_options(auto_write = TRUE)

# ── Paths ─────────────────────────────────────────────────────────────────────
FIT_RDS       <- "data/output/fit.rds"
FIT_K50_RDS   <- "data/output/fit_kappa50.rds"
VOCAB_RDS     <- "data/output/vocab.rds"
STAN_DATA_RDS <- "data/output/stan_data.rds"
STAN_FILE     <- "stan/diversity_model.stan"
OUT_DIR       <- "data/output/workflow"

token   <- "TELEGRAM_BOT_TOKEN_REDACTED"
chat_id <- Sys.getenv("TELEGRAM_CHAT_ID")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create("logs",  recursive = TRUE, showWarnings = FALSE)

# ── Helpers ───────────────────────────────────────────────────────────────────
softmax_r <- function(x) { ex <- exp(x - max(x)); ex / sum(ex) }

tg_photo <- function(path, caption) {
  tryCatch({
    resp <- httr::POST(
      url  = paste0("https://api.telegram.org/bot", token, "/sendPhoto"),
      body = list(chat_id = chat_id,
                  photo   = httr::upload_file(path),
                  caption = caption),
      encode = "multipart"
    )
    cat("Telegram sent:", basename(path), "(HTTP", httr::status_code(resp), ")\n")
  }, error = function(e) cat("WARNING Telegram:", conditionMessage(e), "\n"))
}

# Dirichlet-Multinomial sampler: draw p ~ Dir(alpha), then y ~ Multinom(N, p)
rdm_sample <- function(N, alpha) {
  if (N == 0L) return(rep(0L, length(alpha)))
  p <- rgamma(length(alpha), shape = alpha, rate = 1)
  p <- p / sum(p)
  as.integer(rmultinom(1L, N, p))
}

# ── Load data objects ─────────────────────────────────────────────────────────
cat("Loading vocab and stan_data...\n")
vocab     <- readRDS(VOCAB_RDS)
stan_data <- readRDS(STAN_DATA_RDS)

l2_levels   <- vocab$l2_levels
year_levels <- vocab$year_levels
N_groups    <- length(l2_levels)
N_years     <- length(year_levels)
K_g_vec     <- vocab$K_g
year_std    <- stan_data$year_std
post_llm    <- stan_data$post_llm
counts_arr  <- stan_data$counts

# Group sizes (total papers across all years and methods)
total_papers <- sapply(seq_len(N_groups),
                       function(g) sum(counts_arr[g, , ]))

# Observed empirical inv_simpson per (g, t) — no model, just raw counts
cat("Computing observed empirical inv_simpson...\n")
obs_inv_simp <- matrix(NA_real_, nrow = N_groups, ncol = N_years)
for (g in seq_len(N_groups)) {
  K <- K_g_vec[g]
  for (t in seq_len(N_years)) {
    cts  <- counts_arr[g, t, 1:K]
    ntot <- sum(cts)
    if (ntot > 0) {
      p  <- cts / ntot
      p  <- p[p > 0]
      obs_inv_simp[g, t] <- 1 / sum(p^2)
    }
  }
}

# ── Load fit.rds and extract posterior arrays ─────────────────────────────────
cat("Loading fit.rds (309 MB — may take ~30 s)...\n")
fit <- readRDS(FIT_RDS)

cat("Extracting posterior arrays...\n")
mu_raw_arr       <- rstan::extract(fit, pars = "mu_raw")$mu_raw          # [S, G, K_max]
beta_method_arr  <- rstan::extract(fit, pars = "beta_method")$beta_method  # [S, G, K_max]
gamma_method_arr <- rstan::extract(fit, pars = "gamma_method")$gamma_method # [S, G, K_max]
sigma_beta_post  <- rstan::extract(fit, pars = "sigma_beta")$sigma_beta    # [S]
sigma_gamma_post <- rstan::extract(fit, pars = "sigma_gamma")$sigma_gamma  # [S]

S     <- dim(mu_raw_arr)[1]
K_max <- dim(mu_raw_arr)[3]
cat(sprintf("S=%d draws, N_groups=%d, N_years=%d, K_max=%d\n",
            S, N_groups, N_years, K_max))


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 1 — Prior Predictive Check (Gelman et al. §2.4)
# ══════════════════════════════════════════════════════════════════════════════
cat("\n===== SECTION 1: Prior Predictive Check =====\n")

set.seed(42)
S_prior  <- 1000L
top5_g   <- order(total_papers, decreasing = TRUE)[seq_len(min(5L, N_groups))]

prior_records <- vector("list", length(top5_g) * S_prior)
idx_r <- 1L

for (g in top5_g) {
  K <- K_g_vec[g]
  sigma_beta_p  <- rexp(S_prior, rate = 2)
  sigma_gamma_p <- rexp(S_prior, rate = 4)

  for (s in seq_len(S_prior)) {
    mu_r    <- rnorm(K)
    beta_g  <- sigma_beta_p[s]  * rnorm(K)
    gamma_g <- sigma_gamma_p[s] * rnorm(K)

    # Random year to sample across the full year range
    t   <- sample.int(N_years, 1L)
    eta <- mu_r + beta_g * year_std[t] + gamma_g * post_llm[t]
    p   <- softmax_r(eta)
    prior_records[[idx_r]] <- data.frame(
      inv_simpson = 1 / sum(p^2),
      group       = sub("^L2-\\d+: ", "", l2_levels[g]),
      stringsAsFactors = FALSE
    )
    idx_r <- idx_r + 1L
  }
}

prior_df  <- bind_rows(prior_records)
obs_range <- range(obs_inv_simp, na.rm = TRUE)

p_prior <- ggplot(prior_df, aes(x = inv_simpson, fill = group, colour = group)) +
  geom_density(alpha = 0.28, linewidth = 0.5) +
  annotate("rect",
           xmin = obs_range[1], xmax = obs_range[2],
           ymin = -Inf, ymax = Inf,
           fill = "grey20", alpha = 0.08) +
  annotate("text",
           x = mean(obs_range), y = Inf,
           label = sprintf("Observed range\n[%.1f, %.1f]", obs_range[1], obs_range[2]),
           vjust = 1.5, size = 3, colour = "grey30") +
  scale_x_continuous(limits = c(1, NA)) +
  labs(
    x        = "Inverse Simpson (prior predictive)",
    y        = "Density",
    fill     = "Group", colour = "Group",
    title    = "Section 1 — Prior Predictive Check",
    subtitle = paste0("5 largest L2 groups; S=1000 draws per group; random year sampled each draw\n",
                      "Priors: sigma_beta~Exp(2), sigma_gamma~Exp(4), mu/beta/gamma_raw~N(0,1)"),
    caption  = paste0(
      "Interpretation: if prior predictive covers 1 to K_g ",
      "(one dominant method to perfectly uniform), priors are weakly informative and acceptable."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

PLOT_PRIOR <- file.path(OUT_DIR, "plot_prior_predictive.png")
ggsave(PLOT_PRIOR, p_prior, width = 10, height = 6, dpi = 150)
cat("Saved:", PLOT_PRIOR, "\n")

prior_med   <- median(prior_df$inv_simpson)
prior_q05   <- quantile(prior_df$inv_simpson, 0.05)
prior_q95   <- quantile(prior_df$inv_simpson, 0.95)
# Pass if the prior predictive plausibly covers the observed range
ppc1_pass   <- prior_q05 <= obs_range[2] && prior_q95 >= obs_range[1]
ppc1_status <- if (ppc1_pass) "PASS" else "WARN"
cat(sprintf("Prior predictive: [%s]\n  prior 5th-95th = [%.2f, %.2f]; observed = [%.2f, %.2f]\n",
            ppc1_status, prior_q05, prior_q95, obs_range[1], obs_range[2]))

tg_photo(PLOT_PRIOR, "Workflow check: Section 1 — Prior Predictive Check (inv_simpson)")


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 2 — Posterior Predictive Check (Gelman et al. §6.1)
# ══════════════════════════════════════════════════════════════════════════════
cat("\n===== SECTION 2: Posterior Predictive Check =====\n")

set.seed(42)
S_ppc    <- min(200L, S)
draw_idx <- sample.int(S, S_ppc, replace = FALSE)
top9_g   <- order(total_papers, decreasing = TRUE)[seq_len(min(9L, N_groups))]

cat(sprintf("PPC: %d posterior draws × %d groups × %d years\n", S_ppc, N_groups, N_years))

# Single pass: collect summary stats + draw-level data for top9 groups
ppc_summary_list <- list()
ppc_draws_list   <- list()

for (g in seq_len(N_groups)) {
  K       <- K_g_vec[g]
  in_top9 <- g %in% top9_g
  cat(sprintf("  g=%d (%s)\n", g, sub("^L2-\\d+: ", "", l2_levels[g])))

  for (t in seq_len(N_years)) {
    N_gt <- sum(counts_arr[g, t, 1:K])
    if (N_gt == 0L) next
    obs_is <- obs_inv_simp[g, t]
    if (is.na(obs_is)) next

    is_rep <- numeric(S_ppc)
    for (di in seq_len(S_ppc)) {
      d   <- draw_idx[di]
      eta <- mu_raw_arr[d, g, 1:K] +
             beta_method_arr[d, g, 1:K]  * year_std[t] +
             gamma_method_arr[d, g, 1:K] * post_llm[t]
      pi_d  <- softmax_r(eta)
      y_rep <- as.integer(rmultinom(1L, N_gt, pi_d))
      p_rep <- y_rep / N_gt
      p_rep <- p_rep[p_rep > 0]
      is_rep[di] <- if (length(p_rep) > 0L) 1 / sum(p_rep^2) else 1
    }

    ppc_summary_list[[length(ppc_summary_list) + 1L]] <- data.frame(
      g           = g,
      t           = t,
      level_2_mid = l2_levels[g],
      obs         = obs_is,
      mean_rep    = mean(is_rep),
      bpval       = mean(is_rep > obs_is),
      stringsAsFactors = FALSE
    )

    if (in_top9) {
      ppc_draws_list[[length(ppc_draws_list) + 1L]] <- data.frame(
        level_2_mid  = l2_levels[g],
        inv_simp_rep = is_rep,
        stringsAsFactors = FALSE
      )
    }
  }
}

ppc_sum_df  <- bind_rows(ppc_summary_list)
ppc_dens_df <- bind_rows(ppc_draws_list) |>
  mutate(label = sub("^L2-\\d+: ", "", level_2_mid))

# Group-level PPC tail probabilities (averaged over years with data)
# Tail probability = fraction of posterior predictive draws exceeding observed.
# Near 0.5 = well-calibrated; near 0 or 1 = systematic misfit (over- or under-prediction).
bpval_grp <- ppc_sum_df |>
  group_by(level_2_mid) |>
  summarise(
    bpval_group = mean(bpval),
    n_years_obs = n(),
    .groups = "drop"
  ) |>
  mutate(
    label  = sub("^L2-\\d+: ", "", level_2_mid),
    status = case_when(
      bpval_group < 0.05 | bpval_group > 0.95 ~ "FAIL",
      bpval_group < 0.10 | bpval_group > 0.90 ~ "WARN",
      TRUE ~ "PASS"
    ),
    flagged = bpval_group < 0.05 | bpval_group > 0.95
  )

n_pass_ppc  <- sum(bpval_grp$status == "PASS")
n_total_ppc <- nrow(bpval_grp)

cat("\nPPC tail probabilities per group:\n")
print(bpval_grp |> select(label, bpval_group, status), n = Inf)
cat(sprintf("\nGroups passing (0.05-0.95): %d / %d\n", n_pass_ppc, n_total_ppc))

# ── Plot: PPC density panels ──────────────────────────────────────────────────
# Observed group mean (pooled over years) as red line.
# The grey density is pooled over ALL years × posterior draws — so temporal
# heterogeneity within a group will spread the density, and the red line
# (a single cross-year mean) need not sit at the peak. This is expected.
# A red line deep in the TAILS (not just off-centre) signals misfit — confirm
# with the tail probability plot. Off-centre but within the body = no concern.
obs_grp_mean <- ppc_sum_df |>
  group_by(level_2_mid) |>
  summarise(obs_mean = mean(obs), .groups = "drop") |>
  filter(level_2_mid %in% unique(ppc_dens_df$level_2_mid)) |>
  mutate(label = sub("^L2-\\d+: ", "", level_2_mid))

p_dens <- ggplot(ppc_dens_df, aes(x = inv_simp_rep)) +
  geom_density(fill = "grey72", colour = "grey50", alpha = 0.75) +
  geom_vline(data = obs_grp_mean,
             aes(xintercept = obs_mean),
             colour = "firebrick", linewidth = 0.9) +
  facet_wrap(~ label, scales = "free", ncol = 3) +
  labs(
    x        = "Inv. Simpson (replicated)",
    y        = "Density",
    title    = "Section 2a — PPC: replicated vs observed inv_simpson",
    subtitle = "Grey = posterior predictive (pooled over years × draws); red = observed group mean\nOff-centre red line is expected (temporal spread); concern only if red is in the tail — confirm with 2b"
  ) +
  theme_minimal(base_size = 9) +
  theme(strip.text = element_text(size = 7), panel.grid.minor = element_blank())

PLOT_PPC_DENS <- file.path(OUT_DIR, "plot_ppc_density.png")
ggsave(PLOT_PPC_DENS, p_dens, width = 12, height = 10, dpi = 150)
cat("Saved:", PLOT_PPC_DENS, "\n")

# ── Plot: PPC tail probabilities dot plot ────────────────────────────────────
bpval_plot <- bpval_grp |>
  arrange(bpval_group) |>
  mutate(label = factor(label, levels = unique(label)))

p_bpval <- ggplot(bpval_plot, aes(x = bpval_group, y = label)) +
  annotate("rect", xmin = 0.05, xmax = 0.95,
           ymin = -Inf, ymax = Inf, fill = "#90EE90", alpha = 0.12) +
  annotate("rect", xmin = 0.10, xmax = 0.90,
           ymin = -Inf, ymax = Inf, fill = "#90EE90", alpha = 0.12) +
  geom_point(aes(colour = flagged), size = 3.5) +
  scale_colour_manual(
    values = c("FALSE" = "steelblue4", "TRUE" = "firebrick"),
    labels = c("FALSE" = "OK", "TRUE" = "flagged"),
    name   = NULL
  ) +
  geom_vline(xintercept = c(0.05, 0.95), linetype = "dashed",
             colour = "darkorange3", linewidth = 0.6) +
  geom_vline(xintercept = c(0.10, 0.90), linetype = "dotted",
             colour = "forestgreen",  linewidth = 0.5) +
  annotate("text", x = 0.50, y = Inf,
           label = "acceptable (0.05-0.95)", vjust = 1.6, size = 3,
           colour = "darkorange3") +
  annotate("text", x = 0.50, y = Inf,
           label = "good (0.10-0.90)", vjust = 3.2, size = 3,
           colour = "forestgreen") +
  scale_x_continuous(limits = c(0, 1),
                     breaks = c(0, 0.05, 0.10, 0.50, 0.90, 0.95, 1)) +
  labs(
    x        = "PPC tail probability (averaged over years)",
    y        = NULL,
    title    = "Section 2b — PPC tail probabilities per group",
    subtitle = "Red = outside acceptable band (0.05-0.95); blue = OK"
  ) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(size = 8), legend.position = "top")

PLOT_PPC_BPVAL <- file.path(OUT_DIR, "plot_ppc_pvalues.png")
ggsave(PLOT_PPC_BPVAL, p_bpval, width = 10, height = 6, dpi = 150)
cat("Saved:", PLOT_PPC_BPVAL, "\n")

tg_photo(PLOT_PPC_DENS,  "Workflow check: Section 2 — PPC density (replicated vs observed)")
tg_photo(PLOT_PPC_BPVAL, "Workflow check: Section 2b — PPC tail probabilities per group")


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 3 — Fake Data Simulation (Gelman et al. §4.1)
# ══════════════════════════════════════════════════════════════════════════════
cat("\n===== SECTION 3: Fake Data Simulation =====\n")

g_fake <- which.max(total_papers)
K_fake <- K_g_vec[g_fake]
cat(sprintf("Fake data group: g=%d  %s  K=%d\n", g_fake, l2_levels[g_fake], K_fake))

# Ground truth
set.seed(123)
sigma_beta_true  <- 0.10
sigma_gamma_true <- 0.06
mu_true    <- rnorm(K_fake)
beta_true  <- rnorm(K_fake) * sigma_beta_true
gamma_true <- rnorm(K_fake) * sigma_gamma_true

# N_gt observed for this group (to keep the same sample sizes)
N_gt_obs <- sapply(seq_len(N_years),
                   function(t) sum(counts_arr[g_fake, t, 1:K_fake]))

# Generate fake DM counts
kappa_fake  <- 10.0
fake_counts <- array(0L, dim = c(1L, N_years, K_fake))
for (t in seq_len(N_years)) {
  if (N_gt_obs[t] == 0L) next
  eta   <- mu_true + beta_true * year_std[t] + gamma_true * post_llm[t]
  alpha <- softmax_r(eta) * kappa_fake
  fake_counts[1L, t, 1:K_fake] <- rdm_sample(N_gt_obs[t], alpha)
}

stan_data_fake <- list(
  N_groups = 1L,
  N_years  = N_years,
  K_max    = K_fake,
  K_g      = array(K_fake, dim = 1L),
  counts   = fake_counts,
  kappa    = kappa_fake,
  year_std = year_std,
  post_llm = post_llm
)

cat("Compiling Stan model (or loading cached)...\n")
mod <- rstan::stan_model(STAN_FILE)

cat("Fitting single-group model to fake data (2 chains × 500 samples)...\n")
fit_fake <- rstan::sampling(
  mod,
  data    = stan_data_fake,
  chains  = 2L,
  iter    = 1000L,
  warmup  = 500L,
  cores   = 2L,
  control = list(adapt_delta = 0.90, max_treedepth = 12),
  seed    = 99L,
  refresh = 200L
)

sg_fake_draws <- rstan::extract(fit_fake, pars = "sigma_gamma")$sigma_gamma
sg_fake_mean  <- mean(sg_fake_draws)
sg_fake_ci90  <- quantile(sg_fake_draws, c(0.05, 0.95))
inside_ci     <- sigma_gamma_true >= sg_fake_ci90[1] & sigma_gamma_true <= sg_fake_ci90[2]

cat(sprintf(
  paste0("Recovery check: true sigma_gamma=%.4f, recovered mean=%.4f,",
         " 90%% CI=[%.4f, %.4f], true value inside CI: %s\n"),
  sigma_gamma_true, sg_fake_mean,
  sg_fake_ci90[1], sg_fake_ci90[2],
  toupper(as.character(inside_ci))
))

# ── Fake-data recovery plot ───────────────────────────────────────────────────
sg_prior_viz <- rexp(5000L, rate = 4)

p_fake <- ggplot() +
  geom_density(data = data.frame(x = sg_prior_viz),
               aes(x = x, linetype = "Prior  Exp(4)"),
               fill = "grey85", colour = "grey55",
               alpha = 0.50, linewidth = 0.8) +
  geom_density(data = data.frame(x = sg_fake_draws),
               aes(x = x, linetype = "Posterior (fake data)"),
               fill = "steelblue", colour = "steelblue4",
               alpha = 0.45, linewidth = 1.0) +
  geom_vline(xintercept = sigma_gamma_true,
             colour = "firebrick", linewidth = 1.2) +
  annotate("text", x = sigma_gamma_true, y = Inf,
           label = sprintf("True = %.3f", sigma_gamma_true),
           colour = "firebrick", hjust = -0.1, vjust = 1.5, size = 3.5) +
  scale_linetype_manual(
    values = c("Prior  Exp(4)" = "dashed", "Posterior (fake data)" = "solid"),
    name   = NULL
  ) +
  coord_cartesian(xlim = c(0, max(quantile(sg_prior_viz,  0.95),
                                  quantile(sg_fake_draws, 0.999)) * 1.30)) +
  labs(
    x        = "sigma_gamma",
    y        = "Density",
    title    = "Section 3 — Fake Data Recovery: sigma_gamma identifiability",
    subtitle = sprintf(
      "Dashed = prior Exp(4); solid = posterior from single-group fake data\nTrue value (red) inside 90%% CI: %s  [CI = %.4f, %.4f]",
      if (inside_ci) "YES" else "NO", sg_fake_ci90[1], sg_fake_ci90[2]
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")

PLOT_FAKE <- file.path(OUT_DIR, "plot_fake_data_recovery.png")
ggsave(PLOT_FAKE, p_fake, width = 8, height = 5, dpi = 150)
cat("Saved:", PLOT_FAKE, "\n")

tg_photo(PLOT_FAKE, "Workflow check: Section 3 — Fake data recovery (sigma_gamma)")


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 4 — Prior Sensitivity Analysis (Gelman et al. §6.3)
# ══════════════════════════════════════════════════════════════════════════════
cat("\n===== SECTION 4: Prior Sensitivity Analysis (kappa) =====\n")

sensitivity_done <- FALSE
spearman_rho     <- NA_real_
PLOT_SENS        <- file.path(OUT_DIR, "plot_prior_sensitivity.png")

if (!file.exists(FIT_K50_RDS)) {
  cat("Waiting for kappa=50 run — rerun this script after fit_kappa50.rds is available\n")
} else {
  cat("fit_kappa50.rds found. Loading...\n")
  fit_k50 <- readRDS(FIT_K50_RDS)

  sg_k10 <- sigma_gamma_post
  sg_k50 <- rstan::extract(fit_k50, pars = "sigma_gamma")$sigma_gamma
  sb_k10 <- sigma_beta_post
  sb_k50 <- rstan::extract(fit_k50, pars = "sigma_beta")$sigma_beta

  gm_k10 <- rstan::extract(fit,     pars = "gamma_method")$gamma_method  # [S, G, K_max]
  gm_k50 <- rstan::extract(fit_k50, pars = "gamma_method")$gamma_method

  # Posterior means and CI widths per (g, k) — padded slots included but near-zero
  gm10_means <- as.vector(apply(gm_k10, c(2, 3), mean))
  gm50_means <- as.vector(apply(gm_k50, c(2, 3), mean))
  gm10_ciw   <- as.vector(apply(gm_k10, c(2, 3),
                                function(x) diff(quantile(x, c(0.05, 0.95)))))
  gm50_ciw   <- as.vector(apply(gm_k50, c(2, 3),
                                function(x) diff(quantile(x, c(0.05, 0.95)))))

  spearman_rho <- cor(gm10_means, gm50_means, method = "spearman")
  robust       <- spearman_rho > 0.95

  # Top 10 gamma_method by |mean| at kappa=10
  top10_idx <- order(abs(gm10_means), decreasing = TRUE)[seq_len(min(10L, length(gm10_means)))]
  cat("\nTop 10 gamma_method (kappa=10 vs kappa=50):\n")
  top10_df <- data.frame(
    kappa10_mean = gm10_means[top10_idx],
    kappa50_mean = gm50_means[top10_idx]
  )
  print(round(top10_df, 4))

  cat("\nsigma_gamma comparison:\n")
  cat(sprintf("  kappa=10: mean=%.4f  SD=%.4f  90%%CI=[%.4f, %.4f]\n",
              mean(sg_k10), sd(sg_k10),
              quantile(sg_k10, 0.05), quantile(sg_k10, 0.95)))
  cat(sprintf("  kappa=50: mean=%.4f  SD=%.4f  90%%CI=[%.4f, %.4f]\n",
              mean(sg_k50), sd(sg_k50),
              quantile(sg_k50, 0.05), quantile(sg_k50, 0.95)))
  cat(sprintf("gamma_method Spearman rho: %.4f  — results are %s\n",
              spearman_rho, if (robust) "ROBUST" else "SENSITIVE"))

  # ── Four-panel sensitivity plot ───────────────────────────────────────────
  df_sg <- data.frame(
    value = c(sg_k10, sg_k50),
    kappa = rep(c("kappa=10", "kappa=50"), c(length(sg_k10), length(sg_k50)))
  )
  df_sb <- data.frame(
    value = c(sb_k10, sb_k50),
    kappa = rep(c("kappa=10", "kappa=50"), c(length(sb_k10), length(sb_k50)))
  )

  kappa_pal <- c("kappa=10" = "steelblue", "kappa=50" = "darkorange2")

  p1s <- ggplot(df_sg, aes(x = value, fill = kappa)) +
    geom_density(alpha = 0.50, colour = NA) +
    scale_fill_manual(values = kappa_pal, name = NULL) +
    labs(x = "sigma_gamma", y = "Density",
         title = "(1) sigma_gamma posteriors") +
    theme_minimal(base_size = 9) + theme(legend.position = "bottom")

  p2s <- ggplot(df_sb, aes(x = value, fill = kappa)) +
    geom_density(alpha = 0.50, colour = NA) +
    scale_fill_manual(values = kappa_pal, name = NULL) +
    labs(x = "sigma_beta", y = "Density",
         title = "(2) sigma_beta posteriors") +
    theme_minimal(base_size = 9) + theme(legend.position = "bottom")

  p3s <- ggplot(data.frame(x = gm10_means, y = gm50_means),
                aes(x = x, y = y)) +
    geom_point(alpha = 0.20, size = 0.7, colour = "grey30") +
    geom_abline(slope = 1, intercept = 0,
                colour = "firebrick", linewidth = 0.6, linetype = "dashed") +
    labs(x = "gamma mean (kappa=10)", y = "gamma mean (kappa=50)",
         title = sprintf("(3) gamma means  rho=%.3f", spearman_rho)) +
    theme_minimal(base_size = 9)

  p4s <- ggplot(data.frame(x = gm10_ciw, y = gm50_ciw),
                aes(x = x, y = y)) +
    geom_point(alpha = 0.20, size = 0.7, colour = "grey30") +
    geom_abline(slope = 1, intercept = 0,
                colour = "firebrick", linewidth = 0.6, linetype = "dashed") +
    labs(x = "CI width (kappa=10)", y = "CI width (kappa=50)",
         title = "(4) gamma 90% CI widths") +
    theme_minimal(base_size = 9)

  # Combine four panels — try patchwork, fall back to gridExtra, then png+grid
  combined_ok <- FALSE
  if (!combined_ok && requireNamespace("patchwork", quietly = TRUE)) {
    library(patchwork)
    p_sens <- (p1s | p2s) / (p3s | p4s) +
      plot_annotation(
        title    = "Section 4 — Prior Sensitivity: kappa=10 vs kappa=50",
        subtitle = sprintf("Spearman rho = %.4f — %s (threshold 0.95)",
                           spearman_rho, if (robust) "ROBUST" else "SENSITIVE")
      )
    ggsave(PLOT_SENS, p_sens, width = 12, height = 9, dpi = 150)
    combined_ok <- TRUE
  }
  if (!combined_ok && requireNamespace("gridExtra", quietly = TRUE)) {
    grob_title <- sprintf(
      "Section 4 — Prior Sensitivity: kappa=10 vs kappa=50\nSpearman rho = %.4f — %s",
      spearman_rho, if (robust) "ROBUST" else "SENSITIVE"
    )
    png(PLOT_SENS, width = 12, height = 9, units = "in", res = 150)
    gridExtra::grid.arrange(p1s, p2s, p3s, p4s, ncol = 2,
                            top = grob_title)
    dev.off()
    combined_ok <- TRUE
  }
  if (!combined_ok) {
    # Last resort: save panels separately
    for (i in seq_along(list(p1s, p2s, p3s, p4s))) {
      pp <- list(p1s, p2s, p3s, p4s)[[i]]
      out_i <- sub("\\.png$", sprintf("_%d.png", i), PLOT_SENS)
      ggsave(out_i, pp, width = 6, height = 4, dpi = 150)
    }
    PLOT_SENS <- sub("\\.png$", "_1.png", PLOT_SENS)
    cat("Note: patchwork/gridExtra not available — saved 4 individual panels\n")
    combined_ok <- TRUE
  }

  cat("Saved:", PLOT_SENS, "\n")
  tg_photo(PLOT_SENS, "Workflow check: Section 4 — Prior sensitivity kappa=10 vs kappa=50")
  sensitivity_done <- TRUE
}


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 5 — Summary Report
# ══════════════════════════════════════════════════════════════════════════════
cat("\n")
cat("=== BAYESIAN WORKFLOW SUMMARY ===\n")
cat(sprintf("Prior predictive:     [%s] — prior covers plausible inv_simpson range\n",
            ppc1_status))
cat(sprintf("Posterior predictive: %d/%d groups pass at 0.05-0.95 threshold\n",
            n_pass_ppc, n_total_ppc))
cat(sprintf("Fake data recovery:   sigma_gamma recovered [%s] — true value %s 90%% CI\n",
            if (inside_ci) "YES" else "NO",
            if (inside_ci) "inside" else "outside"))
if (sensitivity_done) {
  cat(sprintf("Prior sensitivity (kappa): [DONE] — Spearman rho = %.4f\n", spearman_rho))
} else {
  cat("Prior sensitivity (kappa): [PENDING] — rerun after fit_kappa50.rds is available\n")
}
cat("=== RECOMMENDATION ===\n")

core_pass <- ppc1_pass &&
             n_pass_ppc >= ceiling(n_total_ppc * 0.8) &&
             inside_ci

if (core_pass) {
  cat("Model passes all core workflow checks. Results are credible for inference.\n")
  if (sensitivity_done && spearman_rho > 0.95) {
    cat("Prior sensitivity: gamma rankings ROBUST to kappa choice (rho=",
        round(spearman_rho, 3), ").\n", sep = "")
  } else if (sensitivity_done && spearman_rho <= 0.95) {
    cat("Prior sensitivity: kappa affects gamma rankings (rho=",
        round(spearman_rho, 3), ") — discuss kappa choice in paper.\n", sep = "")
  } else {
    cat("Sensitivity pending: rerun after fit_kappa50.rds is available.\n")
  }
} else {
  issues <- character(0)
  if (!ppc1_pass)
    issues <- c(issues, "prior predictive does not cover observed range")
  if (n_pass_ppc < ceiling(n_total_ppc * 0.8))
    issues <- c(issues, sprintf("%d/%d groups fail PPC",
                                n_total_ppc - n_pass_ppc, n_total_ppc))
  if (!inside_ci)
    issues <- c(issues, "sigma_gamma not recovered in fake-data simulation")
  cat(sprintf("CAUTION: %s\n", paste(issues, collapse = "; ")))
  cat("Review model specification before reporting results.\n")
}
cat("=================================\n")

cat("\n04_workflow_checks.R complete.\n")

# ── Auto-fill workflow_results.md and push to GitHub ─────────────────────────
cat("\nFilling docs/workflow_results.md and pushing to GitHub...\n")

sensitivity_body <- if (sensitivity_done) {
  rho_line <- sprintf("Spearman ρ = %.4f (threshold 0.95) — gamma rankings are %s.",
                      spearman_rho, if (spearman_rho > 0.95) "ROBUST" else "SENSITIVE")
  sg10_line <- sprintf("  kappa=10: mean=%.4f  SD=%.4f  90%%CI=[%.4f, %.4f]",
                       mean(sg_k10), sd(sg_k10),
                       quantile(sg_k10, 0.05), quantile(sg_k10, 0.95))
  sg50_line <- sprintf("  kappa=50: mean=%.4f  SD=%.4f  90%%CI=[%.4f, %.4f]",
                       mean(sg_k50), sd(sg_k50),
                       quantile(sg_k50, 0.05), quantile(sg_k50, 0.95))
  paste0(
    rho_line, "\n\n",
    "**sigma_gamma comparison:**\n\n```\n",
    sg10_line, "\n", sg50_line, "\n```\n\n",
    "![Prior sensitivity](../data/output/workflow/plot_prior_sensitivity.png)"
  )
} else {
  "_fit_kappa50.rds not yet available. Rerun `R/04_workflow_checks.R` after the kappa=50 fit completes._"
}

spearman_line <- if (sensitivity_done) {
  sprintf("Spearman ρ = %.4f", spearman_rho)
} else {
  "pending kappa=50 fit"
}

doc <- readLines("docs/workflow_results.md")
doc <- gsub("{{RUN_DATE}}",          format(Sys.time(), "%Y-%m-%d %H:%M"),  doc, fixed = TRUE)
doc <- gsub("{{PPC1_STATUS}}",       ppc1_status,                            doc, fixed = TRUE)
doc <- gsub("{{PRIOR_Q05}}",         round(prior_q05, 2),                    doc, fixed = TRUE)
doc <- gsub("{{PRIOR_Q95}}",         round(prior_q95, 2),                    doc, fixed = TRUE)
doc <- gsub("{{OBS_MIN}}",           round(obs_range[1], 2),                 doc, fixed = TRUE)
doc <- gsub("{{OBS_MAX}}",           round(obs_range[2], 2),                 doc, fixed = TRUE)
doc <- gsub("{{N_PASS_PPC}}",        n_pass_ppc,                             doc, fixed = TRUE)
doc <- gsub("{{N_TOTAL_PPC}}",       n_total_ppc,                            doc, fixed = TRUE)
doc <- gsub("{{SG_BETA_TRUE}}",      sigma_beta_true,                        doc, fixed = TRUE)
doc <- gsub("{{SG_TRUE}}",           sprintf("%.4f", sigma_gamma_true),      doc, fixed = TRUE)
doc <- gsub("{{SG_MEAN}}",           sprintf("%.4f", sg_fake_mean),          doc, fixed = TRUE)
doc <- gsub("{{SG_CI_LO}}",          sprintf("%.4f", sg_fake_ci90[1]),       doc, fixed = TRUE)
doc <- gsub("{{SG_CI_HI}}",          sprintf("%.4f", sg_fake_ci90[2]),       doc, fixed = TRUE)
doc <- gsub("{{INSIDE_CI}}",         toupper(as.character(inside_ci)),        doc, fixed = TRUE)
doc <- gsub("{{INSIDE_CI_YN}}",      if (inside_ci) "YES" else "NO",         doc, fixed = TRUE)
doc <- gsub("{{INSIDE_CI_PREP}}",    if (inside_ci) "inside" else "outside", doc, fixed = TRUE)
doc <- gsub("{{SENSITIVITY_STATUS}}",if (sensitivity_done) "DONE" else "PENDING", doc, fixed = TRUE)
doc <- gsub("{{SENSITIVITY_BODY}}", sensitivity_body,                         doc, fixed = TRUE)
doc <- gsub("{{SPEARMAN_LINE}}",    spearman_line,                            doc, fixed = TRUE)
doc <- gsub("{{RECOMMENDATION}}",
            if (core_pass)
              "> **Recommendation:** model passes all core checks — results are credible for inference."
            else
              "> **Recommendation:** CAUTION — review model specification before reporting results.",
            doc, fixed = TRUE)

writeLines(doc, "docs/workflow_results.md")
cat("docs/workflow_results.md written.\n")

system(paste(
  "git -C ~/R_projects/Vibe_Coding_Paper add",
  "data/output/workflow/*.png",
  "docs/workflow_results.md &&",
  "git -C ~/R_projects/Vibe_Coding_Paper commit -m 'auto: workflow checks results update' &&",
  "git -C ~/R_projects/Vibe_Coding_Paper push"
))
cat("GitHub push done.\n")
