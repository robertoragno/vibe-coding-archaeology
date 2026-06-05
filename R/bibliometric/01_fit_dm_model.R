# 01_fit_dm_model.R
# Fits bibliometric_dirichlet_multinomial.stan using cmdstanr.
# Workflow: optimize → pathfinder → sample (full MCMC).
# Optimize and pathfinder run in seconds for quick sanity checks.
# phi (precision) estimated from data on log scale.

library(cmdstanr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(gridExtra)
library(posterior)

STAN_FILE  <- "stan/bibliometric_dirichlet_multinomial.stan"
FIT_DIR    <- "data/output"
FIT_RDS    <- file.path(FIT_DIR, "fit_phi_free.rds")
DONE_FLAG  <- file.path(FIT_DIR, "fit_phi_free_v4.done")

# ── Load data ─────────────────────────────────────────────────────────────────
cat("Loading stan_data...\n")
stan_data <- readRDS("data/output/stan_data.rds")
stan_data$phi       <- NULL
stan_data$years_vec <- NULL
stan_data$post_llm  <- as.integer(stan_data$post_llm)

cat("N_groups:", stan_data$N_groups, "\n")
cat("N_years: ", stan_data$N_years,  "\n")
cat("K_max:   ", stan_data$K_max,    "\n")

# ── Compile model ─────────────────────────────────────────────────────────────
cat("Compiling model...\n")
model <- cmdstan_model(STAN_FILE)

# ── Step 1: Optimize (MAP) — seconds ─────────────────────────────────────────
cat("\n=== OPTIMIZE (MAP point estimate) ===\n")
fit_opt <- model$optimize(data = stan_data, seed = 42, algorithm = "lbfgs")

cat("\nMAP estimates for key parameters:\n")
opt_draws <- fit_opt$draws()
for (par in c("sigma_beta", "sigma_gamma", "log_phi")) {
  val <- as.numeric(subset(opt_draws, variable = par))
  if (par == "log_phi") {
    cat(sprintf("  phi = %.1f (log_phi = %.3f)\n", exp(val), val))
  } else {
    cat(sprintf("  %s = %.4f\n", par, val))
  }
}

# ── Step 2: Pathfinder — fast approximate posterior ──────────────────────────
cat("\n=== PATHFINDER (approximate posterior) ===\n")
fit_pf <- model$pathfinder(data = stan_data, seed = 42, num_paths = 4, draws = 4000,
                           psis_resample = FALSE)

cat("\nPathfinder summary for key parameters:\n")
pf_summary <- fit_pf$summary(variables = c("sigma_beta", "sigma_gamma", "phi"))
print(pf_summary)

cat("\nPathfinder gamma diagnostics:\n")
pf_draws <- fit_pf$draws(format = "draws_matrix")
vocab <- readRDS("data/output/vocab.rds")
N_groups <- length(vocab$l2_levels)
K_g_vec  <- vocab$K_g

gamma_vars <- grep("^gamma_method\\[", colnames(pf_draws), value = TRUE)
gamma_mat  <- pf_draws[, gamma_vars]
gamma_means <- colMeans(gamma_mat)
cat("  Pathfinder max |gamma|:", round(max(abs(gamma_means)), 4), "\n")
cat("  Pathfinder mean |gamma|:", round(mean(abs(gamma_means)), 4), "\n")
n_sig_pf <- sum(apply(gamma_mat, 2, function(x) {
  q <- quantile(x, c(0.05, 0.95))
  q[1] > 0 | q[2] < 0
}))
cat("  Pathfinder methods with 90% CI excl. zero:", n_sig_pf, "\n")

# ── Step 3: Full MCMC ────────────────────────────────────────────────────────
if (!file.exists(DONE_FLAG)) {
  cat("\n=== FULL MCMC SAMPLING ===\n")
  cat("Settings: warmup=2000, iter=4000, max_treedepth=14\n")

  t_start <- proc.time()

  fit <- model$sample(
    data            = stan_data,
    seed            = 42,
    chains          = 4,
    parallel_chains = 4,
    iter_warmup     = 2000,
    iter_sampling   = 2000,
    adapt_delta     = 0.95,
    max_treedepth   = 14,
    refresh         = 200,
    init            = fit_pf
  )

  t_elapsed   <- proc.time() - t_start
  elapsed_min <- round(t_elapsed["elapsed"] / 60, 1)
  cat("Sampling done. Elapsed:", elapsed_min, "minutes\n")

  fit$save_object(FIT_RDS)
  writeLines(as.character(Sys.time()), DONE_FLAG)
  cat("Fit saved to:", FIT_RDS, "\n")
} else {
  elapsed_min <- NA_real_
  cat("\nFit already complete; loading from", FIT_RDS, "\n")
}

# ── Post-processing ──────────────────────────────────────────────────────────
{
  fit <- readRDS(FIT_RDS)

  cat("\n--- MCMC diagnostics ---\n")
  tryCatch(
    fit$cmdstan_diagnose(),
    error = function(e) {
      cat("cmdstan_diagnose() unavailable (CSV files from original fit no longer exist).\n")
      cat("Skipping — diagnostics were checked at fit time.\n")
    }
  )

  cat("\n--- Key parameter summaries ---\n")
  key_summary <- fit$summary(variables = c("sigma_beta", "sigma_gamma", "phi"))
  print(key_summary)

  # ── Plots ──────────────────────────────────────────────────────────────────
  message("Producing phi-free plots...")
  dir.create("data/output/phi_free", recursive = TRUE, showWarnings = FALSE)
  dir.create("data/output/figures/l2_l3", recursive = TRUE, showWarnings = FALSE)

  KF_PLOT_SIGMA     <- "data/output/figures/l2_l3/kf_plot_sigma_posteriors.png"
  KF_PLOT_DIVERSITY <- "data/output/figures/l2_l3/kf_plot_diversity_by_group.png"
  KF_PLOT_GAMMA_DOT <- "data/output/figures/l2_l3/kf_plot_gamma_dotplot.png"
  KF_PLOT_TOP_GAMMA <- "data/output/figures/l2_l3/kf_plot_top_gamma_trajectories.png"
  KF_PLOT_RAW       <- "data/output/figures/l2_l3/kf_plot_raw_counts.png"

  vocab       <- readRDS("data/output/vocab.rds")
  l2_levels   <- vocab$l2_levels
  year_levels <- vocab$year_levels
  N_groups    <- length(l2_levels)
  N_years     <- length(year_levels)
  K_g_vec     <- vocab$K_g
  stan_data_pp <- readRDS("data/output/stan_data.rds")
  year_std    <- stan_data_pp$year_std
  post_llm    <- stan_data_pp$post_llm

  draws <- fit$draws(format = "draws_matrix")

  mu_raw_vars       <- grep("^mu_raw\\[", colnames(draws), value = TRUE)
  beta_method_vars  <- grep("^beta_method\\[", colnames(draws), value = TRUE)
  gamma_method_vars <- grep("^gamma_method\\[", colnames(draws), value = TRUE)
  S <- nrow(draws)

  # Helper to extract [g,k] from draws matrix
  get_par <- function(draws, prefix, g, k) {
    vname <- sprintf("%s[%d,%d]", prefix, g, k)
    draws[, vname]
  }

  # ── Plot 1: sigma posteriors — 3 panels ───────────────────────────────────
  sigma_beta_draws  <- as.numeric(draws[, "sigma_beta"])
  sigma_gamma_draws <- as.numeric(draws[, "sigma_gamma"])
  phi_draws_kf      <- as.numeric(draws[, "phi"])

  x_phi_max    <- quantile(phi_draws_kf, 0.999)
  x_phi_seq    <- seq(0.1, x_phi_max * 1.5, length.out = 500)
  phi_prior_df <- data.frame(
    value   = x_phi_seq,
    density = dlnorm(x_phi_seq, log(100), 1.0)
  )

  p_sb <- ggplot(data.frame(value = sigma_beta_draws), aes(x = value)) +
    geom_density(fill = "steelblue", colour = "steelblue", alpha = 0.4) +
    labs(x = "sigma_beta", y = "Density",
         title = "sigma_beta (baseline trend)") +
    theme_minimal(base_size = 11)

  p_sg <- ggplot(data.frame(value = sigma_gamma_draws), aes(x = value)) +
    geom_density(fill = "firebrick", colour = "firebrick", alpha = 0.4) +
    labs(x = "sigma_gamma", y = "Density",
         title = "sigma_gamma (post-LLM shift)") +
    theme_minimal(base_size = 11)

  p_phi <- ggplot(data.frame(value = phi_draws_kf), aes(x = value)) +
    geom_density(colour = "darkorchid", fill = "darkorchid", alpha = 0.3) +
    geom_line(data = phi_prior_df, aes(x = value, y = density),
              linetype = "dashed", colour = "grey40", inherit.aes = FALSE) +
    coord_cartesian(xlim = c(0, x_phi_max * 1.2)) +
    labs(x = "phi (precision: higher = less overdispersion)", y = "Density",
         title = "phi: posterior (solid) vs prior (dashed)",
         subtitle = "phi ~ lognormal(log(100), 1.0)") +
    theme_minimal(base_size = 11)

  p2 <- gridExtra::arrangeGrob(
    p_sb, p_sg, p_phi, nrow = 1,
    top = "Sigma posteriors — phi-free model v4 (no singletons)"
  )
  ggsave(KF_PLOT_SIGMA, p2, width = 16, height = 5, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_SIGMA, "\n")

  # ── Plot 2: diversity by group ────────────────────────────────────────────
  cat("Extracting inv_simpson draws...\n")
  inv_simp_vars <- grep("^inv_simpson\\[", colnames(draws), value = TRUE)

  inv_simp_summary_kf <- do.call(rbind, lapply(seq_len(N_groups), function(g) {
    do.call(rbind, lapply(seq_len(N_years), function(t) {
      vname <- sprintf("inv_simpson[%d,%d]", g, t)
      vals <- as.numeric(draws[, vname])
      data.frame(
        l2 = l2_levels[g],
        year        = year_levels[t],
        median      = median(vals),
        lo90        = quantile(vals, 0.05),
        hi90        = quantile(vals, 0.95),
        lo50        = quantile(vals, 0.25),
        hi50        = quantile(vals, 0.75)
      )
    }))
  }))

  emp_diversity <- do.call(rbind, lapply(seq_len(N_groups), function(g) {
    K <- K_g_vec[g]
    do.call(rbind, lapply(seq_len(N_years), function(t) {
      cts   <- stan_data_pp$counts[g, t, 1:K]
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

  conj_summary_kf <- inv_simp_summary_kf |>
    mutate(label = sub("^L2-\\d+: ", "", l2))

  p1 <- ggplot(conj_summary_kf, aes(x = year)) +
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
      title    = "Methodological diversity within L2 groups over time (v4, no singletons)",
      subtitle = "Grey dots = observed annual diversity; ribbon = 50%/90% posterior credible intervals"
    ) +
    theme_minimal(base_size = 8) +
    theme(
      strip.text       = element_text(size = 6),
      panel.grid.minor = element_blank(),
      legend.position  = "bottom"
    )

  ggsave(KF_PLOT_DIVERSITY, p1, width = 20, height = 16, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_DIVERSITY, "\n")

  # ── Extract gamma posteriors ──────────────────────────────────────────────
  cat("Extracting gamma_method posteriors...\n")
  gamma_list <- vector("list", N_groups)
  for (grp in seq_len(N_groups)) {
    K <- K_g_vec[grp]
    gm_g <- matrix(NA_real_, nrow = S, ncol = K)
    for (k in seq_len(K)) {
      gm_g[, k] <- get_par(draws, "gamma_method", grp, k)
    }

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

  cat("Methods with 90% CI excluding zero:", sum(gamma_df$sig, na.rm = TRUE), "\n")

  # ── Plot 3: gamma dotplot (two-panel) ────────────────────────────────────
  sig_gamma  <- gamma_df |> filter(sig)
  n_sig      <- nrow(sig_gamma)

  top20_gamma <- gamma_df |>
    mutate(abs_gamma = abs(mean_gamma)) |>
    arrange(desc(abs_gamma)) |>
    slice_head(n = 20) |>
    arrange(mean_gamma) |>
    mutate(
      method_id = factor(method_id, levels = unique(method_id)),
      direction = ifelse(mean_gamma > 0, "positive", "negative")
    )

  all_xlim <- bind_rows(sig_gamma, top20_gamma)
  x_lo <- min(all_xlim$lo90, na.rm = TRUE) * 1.05
  x_hi <- max(all_xlim$hi90, na.rm = TRUE) * 1.05

  plot_title_grob <- grid::textGrob(
    paste0(
      "Differential post-2023 method slopes — v4 (no singletons)\n",
      "Panel B shows directional evidence without the strict CI filter."
    ),
    gp   = grid::gpar(fontsize = 9),
    just = "left", x = 0.01
  )

  pB <- ggplot(top20_gamma, aes(x = mean_gamma, y = method_id, colour = direction)) +
    geom_point(size = 1.5) +
    geom_errorbarh(aes(xmin = lo90, xmax = hi90), height = 0.3, linewidth = 0.35) +
    scale_colour_manual(values = c("positive" = "firebrick", "negative" = "steelblue"),
                        guide = "none") +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
    coord_cartesian(xlim = c(x_lo, x_hi)) +
    labs(
      x     = "Posterior mean gamma (post-LLM differential slope)",
      y     = NULL,
      title = "Panel B: Top 20 methods by |posterior mean gamma|"
    ) +
    theme_minimal(base_size = 8) +
    theme(axis.text.y = element_text(size = 6), panel.grid.major.y = element_blank())

  if (n_sig < 3) {
    if (n_sig > 0) {
      sig_plot <- sig_gamma |>
        arrange(mean_gamma) |>
        mutate(
          method_id = factor(method_id, levels = unique(method_id)),
          direction = ifelse(mean_gamma > 0, "positive", "negative")
        )
      pA <- ggplot(sig_plot, aes(x = mean_gamma, y = method_id, colour = direction)) +
        geom_point(size = 2) +
        geom_errorbarh(aes(xmin = lo90, xmax = hi90), height = 0.3, linewidth = 0.4) +
        scale_colour_manual(values = c("positive" = "firebrick", "negative" = "steelblue"),
                            guide = "none") +
        geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
        coord_cartesian(xlim = c(x_lo, x_hi)) +
        labs(
          x        = NULL,
          y        = NULL,
          title    = "Panel A: Methods with 90% CI excluding zero",
          subtitle = paste0("(", n_sig, " method", ifelse(n_sig == 1, "", "s"), ")")
        ) +
        theme_minimal(base_size = 9) +
        theme(axis.text.y = element_text(size = 7), panel.grid.major.y = element_blank())
    } else {
      pA <- ggplot() +
        annotate("text", x = 0.5, y = 0.5,
                 label = "No methods survive the 90% CI filter",
                 size = 4, colour = "grey50") +
        theme_void() +
        labs(title = "Panel A: Methods with 90% CI excluding zero")
    }
    p3 <- gridExtra::arrangeGrob(pA, pB, nrow = 2, heights = c(1, 4), top = plot_title_grob)
  } else {
    sig_plot <- sig_gamma |>
      arrange(mean_gamma) |>
      mutate(
        method_id = factor(method_id, levels = unique(method_id)),
        direction = ifelse(mean_gamma > 0, "positive", "negative")
      )
    pA <- ggplot(sig_plot, aes(x = mean_gamma, y = method_id, colour = direction)) +
      geom_point(size = 1.5) +
      geom_errorbarh(aes(xmin = lo90, xmax = hi90), height = 0.3, linewidth = 0.35) +
      scale_colour_manual(values = c("positive" = "firebrick", "negative" = "steelblue"),
                          guide = "none") +
      geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
      coord_cartesian(xlim = c(x_lo, x_hi)) +
      labs(x = NULL, y = NULL, title = "Panel A: Methods with 90% CI excluding zero") +
      theme_minimal(base_size = 8) +
      theme(axis.text.y = element_text(size = 6), panel.grid.major.y = element_blank())
    p3 <- gridExtra::arrangeGrob(pA, pB, nrow = 2, top = plot_title_grob)
  }

  ggsave(KF_PLOT_GAMMA_DOT, p3, width = 14, height = 12, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_GAMMA_DOT, "\n")

  # ── Top 15 methods by |gamma| ───────────────────────────────────────────
  top15 <- gamma_df |>
    mutate(abs_gamma = abs(mean_gamma)) |>
    arrange(desc(abs_gamma)) |>
    slice_head(n = 15)

  cat("\nTop 15 methods by |mean_gamma|:\n")
  print(top15 |> select(l2, l3, mean_gamma, lo90, hi90))

  # ── Plot 4: fitted share trajectories for top 15 ───────────────────────
  cat("Computing fitted share trajectories for top 15 methods...\n")
  n_draws_traj <- min(200, S)
  draw_idx     <- sample(S, n_draws_traj)

  traj_list <- vector("list", nrow(top15))
  for (i in seq_len(nrow(top15))) {
    g_i <- top15$g[i]
    k_i <- top15$k[i]
    K   <- K_g_vec[g_i]

    share_mat <- matrix(0, nrow = n_draws_traj, ncol = N_years)
    for (di in seq_len(n_draws_traj)) {
      s <- draw_idx[di]
      for (t in seq_len(N_years)) {
        eta_vec <- numeric(K)
        for (kk in seq_len(K)) {
          eta_vec[kk] <- get_par(draws, "mu_raw", g_i, kk)[s] +
                         get_par(draws, "beta_method", g_i, kk)[s] * year_std[t] +
                         get_par(draws, "gamma_method", g_i, kk)[s] * post_llm[t]
        }
        p_vec            <- exp(eta_vec - max(eta_vec))
        p_vec            <- p_vec / sum(p_vec)
        share_mat[di, t] <- p_vec[k_i]
      }
    }

    method_label <- paste0(sub("^L2-\\d+: ", "", l2_levels[g_i]), ": ", top15$l3[i])
    traj_list[[i]] <- data.frame(
      year      = year_levels,
      mean      = colMeans(share_mat),
      lo80      = apply(share_mat, 2, quantile, 0.10),
      hi80      = apply(share_mat, 2, quantile, 0.90),
      lo90      = apply(share_mat, 2, quantile, 0.05),
      hi90      = apply(share_mat, 2, quantile, 0.95),
      method_id = method_label
    )
  }

  traj_all <- bind_rows(traj_list) |>
    mutate(method_id = factor(method_id, levels = unique(method_id)))

  p4 <- ggplot(traj_all, aes(x = year)) +
    geom_ribbon(aes(ymin = lo90, ymax = hi90), alpha = 0.15, fill = "steelblue") +
    geom_ribbon(aes(ymin = lo80, ymax = hi80), alpha = 0.25, fill = "steelblue") +
    geom_line(aes(y = mean), colour = "steelblue4", linewidth = 0.7) +
    geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
    annotate("text", x = 2023, y = Inf, label = "LLM adoption",
             hjust = -0.05, vjust = 1.5, size = 2, colour = "firebrick") +
    facet_wrap(~ method_id, scales = "free_y", ncol = 3) +
    labs(
      x        = "Year",
      y        = "Fitted method share",
      title    = "Top 15 methods by |gamma|: fitted share trajectories (v4, no singletons)",
      subtitle = "Ribbon = 80%/90% CI from 200 posterior draws; dashed = 2023"
    ) +
    theme_minimal(base_size = 7) +
    theme(strip.text = element_text(size = 5), panel.grid.minor = element_blank())

  ggsave(KF_PLOT_TOP_GAMMA, p4, width = 18, height = 12, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_TOP_GAMMA, "\n")

  # ── Plot 5: raw counts for top 15 ──────────────────────────────────────
  raw_counts_list <- vector("list", nrow(top15))
  for (i in seq_len(nrow(top15))) {
    g_i <- top15$g[i]
    k_i <- top15$k[i]
    raw_df <- data.frame(
      year     = year_levels,
      n_papers = as.integer(stan_data_pp$counts[g_i, , k_i])
    )
    method_label <- paste0(sub("^L2-\\d+: ", "", l2_levels[g_i]), ": ", top15$l3[i])
    raw_df$method_id <- method_label
    raw_counts_list[[i]] <- raw_df
  }

  raw_all <- bind_rows(raw_counts_list) |>
    mutate(method_id = factor(
      method_id,
      levels = paste0(sub("^L2-\\d+: ", "", l2_levels[top15$g]), ": ", top15$l3)
    ))

  p5 <- ggplot(raw_all, aes(x = year, y = n_papers)) +
    geom_col(fill = "grey70", width = 0.7) +
    geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
    annotate("text", x = 2023, y = Inf, label = "LLM adoption",
             hjust = -0.05, vjust = 1.5, size = 2, colour = "firebrick") +
    facet_wrap(~ method_id, scales = "free_y", ncol = 3) +
    labs(
      x        = "Year",
      y        = "Observed paper count",
      title    = "Top 15 methods: raw observed counts (v4, no singletons)",
      subtitle = "Dashed = 2023"
    ) +
    theme_minimal(base_size = 7) +
    theme(strip.text = element_text(size = 5), panel.grid.minor = element_blank())

  ggsave(KF_PLOT_RAW, p5, width = 18, height = 12, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_RAW, "\n")

}

cat("\n01_fit_dm_model.R complete.\n")
