# 01b_fit_phi_free.R
# Fits diversity_model_phi_free.stan — phi (precision parameter) estimated from data.
# phi controls Dirichlet-Multinomial concentration: higher phi = tighter shares (less overdispersion).
# Parameterised on log scale (log_phi) for better HMC geometry.
# Prior: log_phi ~ N(log(100), 1.0)  <=>  phi ~ lognormal(log(100), 1.0)  [median=100, 90%CI ~14-716]
# Runtime target: under 12 hours.

library(rstan)
library(httr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(gridExtra)
options(mc.cores = parallel::detectCores())
rstan_options(auto_write = TRUE)

STAN_FILE  <- "stan/diversity_model_phi_free.stan"
FIT_RDS    <- "data/output/fit_phi_free.rds"
DONE_FLAG  <- "data/output/fit_phi_free_v3.done"  # v3: log_phi reparameterisation + warmup=2000 + iter=4000
token      <- "TELEGRAM_BOT_TOKEN_REDACTED"
chat_id    <- "252243317"

tg_msg <- function(text) {
  tryCatch({
    resp <- httr::POST(
      url    = paste0("https://api.telegram.org/bot", token, "/sendMessage"),
      body   = list(chat_id = chat_id, text = text),
      encode = "form"
    )
    cat("Telegram sent (HTTP", httr::status_code(resp), ")\n")
  }, error = function(e) cat("WARNING Telegram:", conditionMessage(e), "\n"))
}

# ── Load data (phi removed — it is now a parameter) ─────────────────────────
cat("Loading stan_data...\n")
stan_data        <- readRDS("data/output/stan_data.rds")
stan_data$phi  <- NULL  # phi is now a parameter, not data

cat("N_groups:", stan_data$N_groups, "\n")
cat("N_years: ", stan_data$N_years,  "\n")
cat("K_max:   ", stan_data$K_max,    "\n")

# ── Fit (guarded) ─────────────────────────────────────────────────────────────
if (!file.exists(DONE_FLAG)) {
  cat("Compiling and sampling phi-free model (log_phi parameterisation)...\n")
  cat("Prior: log_phi ~ N(log(100), 1.0)  [phi median=100, 90% CI ~14-716]\n")
  cat("Settings: warmup=2000, iter=4000, max_treedepth=14\n")
  t_start <- proc.time()

  fit <- suppressWarnings(stan(
    file    = STAN_FILE,
    data    = stan_data,
    chains  = 4,
    iter    = 4000,
    warmup  = 2000,
    cores   = 4,
    seed    = 42,
    control = list(
      adapt_delta   = 0.95,
      max_treedepth = 14
    ),
    refresh = 200
  ))

  t_elapsed   <- proc.time() - t_start
  elapsed_min <- round(t_elapsed["elapsed"] / 60, 1)
  cat("Sampling done. Elapsed:", elapsed_min, "minutes\n")

  saveRDS(fit, FIT_RDS)
  writeLines(as.character(Sys.time()), DONE_FLAG)
  cat("Fit saved to:", FIT_RDS, "\n")
} else {
  elapsed_min <- NA_real_
  cat("Fit already complete; loading from", FIT_RDS, "\n")
}

{  # ── Post-processing (always runs) ───────────────────────────────────────────
  fit <- readRDS(FIT_RDS)

  # ── HMC diagnostics ────────────────────────────────────────────────────────
  cat("\n--- HMC diagnostics ---\n")
  check_hmc_diagnostics(fit)

  cat("\n--- sigma_beta summary ---\n")
  print(summary(fit, pars = "sigma_beta")$summary)

  cat("\n--- sigma_gamma summary ---\n")
  print(summary(fit, pars = "sigma_gamma")$summary)

  cat("\n--- phi summary ---\n")
  print(summary(fit, pars = "phi")$summary)

  # ── Telegram diagnostics ──────────────────────────────────────────────────
  n_div    <- sum(rstan::get_divergent_iterations(fit))
  div_flag <- if (n_div == 0) "Divergences: 0" else paste0("Divergences: ", n_div, " !!!")

  sm <- rstan::summary(fit, pars = c("sigma_beta", "sigma_gamma", "phi"),
                       probs = c(0.05, 0.95))$summary

  fmt_par <- function(par) {
    rhat <- round(sm[par, "Rhat"],  3)
    ess  <- round(sm[par, "n_eff"])
    mean <- round(sm[par, "mean"],  4)
    lo   <- round(sm[par, "5%"],    4)
    hi   <- round(sm[par, "95%"],   4)
    rhat_flag <- if (rhat > 1.01) "[BAD > 1.01]" else "[OK]"
    ess_flag  <- if (ess  < 400)  "[BAD < 400]"  else "[OK]"
    sprintf("%s: mean=%.4f 90%%CI=[%.4f,%.4f]  Rhat=%.3f%s  ESS=%d%s",
            par, mean, lo, hi, rhat, rhat_flag, ess, ess_flag)
  }

  runtime_flag <- if (is.na(elapsed_min))
    "Runtime: N/A (loaded from saved fit)"
  else if (elapsed_min > 720)
    "RUNTIME EXCEEDED TARGET (>12h)"
  else
    sprintf("Runtime: %.1f min (target: <720 min)", elapsed_min)

  msg <- paste(
    "phi-free v3 model diagnostics",
    div_flag,
    fmt_par("sigma_beta"),
    fmt_par("sigma_gamma"),
    fmt_par("phi"),
    paste("Reference (fixed-phi): sigma_gamma_ref~0.054"),
    runtime_flag,
    sep = "\n"
  )

  tg_msg(msg)

  # ── Plots ──────────────────────────────────────────────────────────────────
  message("Producing phi-free plots...")
  dir.create("data/output/phi_free", recursive = TRUE, showWarnings = FALSE)

  KF_PLOT_SIGMA     <- "data/output/phi_free/kf_plot_sigma_posteriors.png"
  KF_PLOT_DIVERSITY <- "data/output/phi_free/kf_plot_diversity_by_group.png"
  KF_PLOT_GAMMA_DOT <- "data/output/phi_free/kf_plot_gamma_dotplot.png"
  KF_PLOT_TOP_GAMMA <- "data/output/phi_free/kf_plot_top_gamma_trajectories.png"
  KF_PLOT_RAW       <- "data/output/phi_free/kf_plot_raw_counts.png"

  vocab       <- readRDS("data/output/vocab.rds")
  l2_levels   <- vocab$l2_levels
  year_levels <- vocab$year_levels
  N_groups    <- length(l2_levels)
  N_years     <- length(year_levels)
  K_g_vec     <- vocab$K_g
  year_std    <- stan_data$year_std
  post_llm    <- stan_data$post_llm

  mu_raw_arr       <- rstan::extract(fit, pars = "mu_raw")$mu_raw
  beta_method_arr  <- rstan::extract(fit, pars = "beta_method")$beta_method
  gamma_method_arr <- rstan::extract(fit, pars = "gamma_method")$gamma_method
  S     <- dim(mu_raw_arr)[1]
  K_max <- dim(mu_raw_arr)[3]

  # ── Plot 1: sigma posteriors — 3 panels ─────────────────────────────────────
  sigma_beta_draws_kf  <- rstan::extract(fit, pars = "sigma_beta")$sigma_beta
  sigma_gamma_draws_kf <- rstan::extract(fit, pars = "sigma_gamma")$sigma_gamma
  phi_draws_kf       <- rstan::extract(fit, pars = "phi")$phi

  fit_ref <- readRDS("data/output/fit.rds")
  sigma_beta_draws_ref  <- rstan::extract(fit_ref, pars = "sigma_beta")$sigma_beta
  sigma_gamma_draws_ref <- rstan::extract(fit_ref, pars = "sigma_gamma")$sigma_gamma
  rm(fit_ref)

  sigma_df <- data.frame(
    value     = c(sigma_beta_draws_kf,  sigma_beta_draws_ref,
                  sigma_gamma_draws_kf, sigma_gamma_draws_ref),
    parameter = c(rep("sigma_beta",  length(sigma_beta_draws_kf)),
                  rep("sigma_beta",  length(sigma_beta_draws_ref)),
                  rep("sigma_gamma", length(sigma_gamma_draws_kf)),
                  rep("sigma_gamma", length(sigma_gamma_draws_ref))),
    model     = c(rep("phi free v3",      length(sigma_beta_draws_kf)),
                  rep("fixed-phi ref",   length(sigma_beta_draws_ref)),
                  rep("phi free v3",      length(sigma_gamma_draws_kf)),
                  rep("fixed-phi ref",   length(sigma_gamma_draws_ref)))
  )

  x_phi_max    <- quantile(phi_draws_kf, 0.999)
  x_phi_seq    <- seq(0.1, x_phi_max * 1.5, length.out = 500)
  phi_prior_df <- data.frame(
    value   = x_phi_seq,
    density = dlnorm(x_phi_seq, log(100), 1.0)
  )

  p_sb <- ggplot(sigma_df |> filter(parameter == "sigma_beta"),
                 aes(x = value, colour = model, linetype = model)) +
    geom_density(fill = NA) +
    scale_colour_manual(values = c("phi free v3" = "steelblue", "fixed-phi ref" = "steelblue4")) +
    scale_linetype_manual(values = c("phi free v3" = "solid", "fixed-phi ref" = "dashed")) +
    labs(x = "sigma_beta", y = "Density",
         title = "sigma_beta (baseline trend)",
         colour = "Model", linetype = "Model") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")

  p_sg <- ggplot(sigma_df |> filter(parameter == "sigma_gamma"),
                 aes(x = value, colour = model, linetype = model)) +
    geom_density(fill = NA) +
    scale_colour_manual(values = c("phi free v3" = "firebrick", "fixed-phi ref" = "firebrick4")) +
    scale_linetype_manual(values = c("phi free v3" = "solid", "fixed-phi ref" = "dashed")) +
    labs(x = "sigma_gamma", y = "Density",
         title = "sigma_gamma (post-LLM shift)",
         colour = "Model", linetype = "Model") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")

  p_phi <- ggplot(data.frame(value = phi_draws_kf), aes(x = value)) +
    geom_density(colour = "darkorchid", fill = "darkorchid", alpha = 0.3) +
    geom_line(data = phi_prior_df, aes(x = value, y = density),
              linetype = "dashed", colour = "grey40", inherit.aes = FALSE) +
    coord_cartesian(xlim = c(0, x_phi_max * 1.2)) +
    labs(x = "phi (precision: higher = less overdispersion)", y = "Density",
         title = "phi: posterior (solid) vs prior (dashed)",
         subtitle = "phi ~ lognormal(log(100), 1.0); sampled as log_phi") +
    theme_minimal(base_size = 11)

  p2 <- gridExtra::arrangeGrob(
    p_sb, p_sg, p_phi, nrow = 1,
    top = "Sigma posteriors: phi-free model (solid) vs fixed-phi reference (dashed)"
  )
  ggsave(KF_PLOT_SIGMA, p2, width = 10, height = 5, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_SIGMA, "\n")

  # ── Plot 2: diversity by group ────────────────────────────────────────────
  cat("Extracting inv_simpson draws...\n")
  inv_simp_arr <- rstan::extract(fit, pars = "inv_simpson")$inv_simpson

  inv_simp_tidy <- expand.grid(
    draw = seq_len(S),
    g    = seq_len(N_groups),
    t    = seq_len(N_years)
  ) |>
    mutate(
      inv_simpson = mapply(function(d, g, t) inv_simp_arr[d, g, t], draw, g, t),
      level_2_mid = l2_levels[g],
      year        = year_levels[t]
    )

  inv_simp_summary_kf <- inv_simp_tidy |>
    group_by(level_2_mid, year) |>
    summarise(
      median = median(inv_simpson),
      lo90   = quantile(inv_simpson, 0.05),
      hi90   = quantile(inv_simpson, 0.95),
      lo50   = quantile(inv_simpson, 0.25),
      hi50   = quantile(inv_simpson, 0.75),
      .groups = "drop"
    )

  emp_diversity <- do.call(rbind, lapply(seq_len(N_groups), function(g) {
    K <- K_g_vec[g]
    do.call(rbind, lapply(seq_len(N_years), function(t) {
      cts   <- stan_data$counts[g, t, 1:K]
      total <- sum(cts)
      if (total == 0) return(NULL)
      p <- cts / total
      p <- p[p > 0]
      data.frame(
        level_2_mid  = l2_levels[g],
        year         = year_levels[t],
        inv_simp_emp = 1 / sum(p^2),
        stringsAsFactors = FALSE
      )
    }))
  })) |>
    mutate(label = sub("^L2-\\d+: ", "", level_2_mid))

  conj_summary_kf <- inv_simp_summary_kf |>
    mutate(label = sub("^L2-\\d+: ", "", level_2_mid))

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
      title    = "Methodological diversity within L2 groups over time (phi-free v3)",
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
    K    <- K_g_vec[grp]
    gm_g <- matrix(gamma_method_arr[, grp, 1:K], nrow = S, ncol = K)

    method_labels <- vocab$l3_vocab |>
      filter(g == grp) |>
      arrange(k_local) |>
      pull(level_3_fine)

    gamma_list[[grp]] <- data.frame(
      g            = grp,
      level_2_mid  = l2_levels[grp],
      k            = seq_len(K),
      level_3_fine = method_labels,
      mean_gamma   = colMeans(gm_g),
      lo90         = apply(gm_g, 2, quantile, 0.05),
      hi90         = apply(gm_g, 2, quantile, 0.95),
      stringsAsFactors = FALSE
    )
  }

  gamma_df <- bind_rows(gamma_list) |>
    mutate(
      sig         = (lo90 > 0 | hi90 < 0),
      group_label = sub("^L2-\\d+: ", "", level_2_mid),
      method_id   = paste0(group_label, ": ", level_3_fine)
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

  # Shared x-axis limits so both panels are visually comparable
  all_xlim <- bind_rows(sig_gamma, top20_gamma)
  x_lo <- min(all_xlim$lo90, na.rm = TRUE) * 1.05
  x_hi <- max(all_xlim$hi90, na.rm = TRUE) * 1.05

  plot_title_grob <- grid::textGrob(
    paste0(
      "Differential post-2023 method slopes \u2014 phi-free v3\n",
      "Note: wide CIs are expected when phi is estimated from data (~604). ",
      "Only the strongest signals survive the 90% threshold. ",
      "Panel B shows directional evidence without the strict CI filter."
    ),
    gp   = grid::gpar(fontsize = 9),
    just = "left", x = 0.01
  )

  # Panel B (always shown)
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
      title = "Panel B: Top 20 methods by |posterior mean gamma| (wider CI expected with phi estimated)"
    ) +
    theme_minimal(base_size = 8) +
    theme(axis.text.y = element_text(size = 6), panel.grid.major.y = element_blank())

  if (n_sig < 3) {
    # Panel A: small section with note
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
          subtitle = paste0("(", n_sig, " method", ifelse(n_sig == 1, "", "s"),
                            " \u2014 very strict threshold when phi is estimated)")
        ) +
        theme_minimal(base_size = 9) +
        theme(axis.text.y = element_text(size = 7), panel.grid.major.y = element_blank())
    } else {
      pA <- ggplot() +
        annotate("text", x = 0.5, y = 0.5,
                 label = "No methods survive the 90% CI filter with phi estimated",
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

  # ── Top 15 methods by |gamma| ─────────────────────────────────────────────
  top15 <- gamma_df |>
    mutate(abs_gamma = abs(mean_gamma)) |>
    arrange(desc(abs_gamma)) |>
    slice_head(n = 15)

  cat("\nTop 15 methods by |mean_gamma|:\n")
  print(top15 |> select(level_2_mid, level_3_fine, mean_gamma, lo90, hi90))

  # ── Plot 4: fitted share trajectories for top 15 ─────────────────────────
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
        eta_vec          <- mu_raw_arr[s, g_i, 1:K] +
                            beta_method_arr[s, g_i, 1:K] * year_std[t] +
                            gamma_method_arr[s, g_i, 1:K] * post_llm[t]
        p_vec            <- exp(eta_vec - max(eta_vec))
        p_vec            <- p_vec / sum(p_vec)
        share_mat[di, t] <- p_vec[k_i]
      }
    }

    method_label <- paste0(sub("^L2-\\d+: ", "", l2_levels[g_i]), ": ", top15$level_3_fine[i])
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
      title    = "Top 15 methods by |gamma|: fitted share trajectories (phi-free v3)",
      subtitle = "Ribbon = 80%/90% CI from 200 posterior draws; dashed = 2023"
    ) +
    theme_minimal(base_size = 7) +
    theme(strip.text = element_text(size = 5), panel.grid.minor = element_blank())

  ggsave(KF_PLOT_TOP_GAMMA, p4, width = 18, height = 12, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_TOP_GAMMA, "\n")

  # ── Plot 5: raw counts for top 15 ────────────────────────────────────────
  raw_counts_list <- vector("list", nrow(top15))
  for (i in seq_len(nrow(top15))) {
    g_i <- top15$g[i]
    k_i <- top15$k[i]
    raw_df <- data.frame(
      year     = year_levels,
      n_papers = as.integer(stan_data$counts[g_i, , k_i])
    )
    method_label <- paste0(sub("^L2-\\d+: ", "", l2_levels[g_i]), ": ", top15$level_3_fine[i])
    raw_df$method_id <- method_label
    raw_counts_list[[i]] <- raw_df
  }

  raw_all <- bind_rows(raw_counts_list) |>
    mutate(method_id = factor(
      method_id,
      levels = paste0(sub("^L2-\\d+: ", "", l2_levels[top15$g]), ": ", top15$level_3_fine)
    ))

  p5 <- ggplot(raw_all, aes(x = year, y = n_papers)) +
    geom_point(size = 1, colour = "grey40") +
    geom_smooth(method = "loess", formula = y ~ x, se = TRUE,
                colour = "darkorange3", fill = "darkorange", alpha = 0.2,
                linewidth = 1.2, span = 0.75) +
    geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
    annotate("text", x = 2023, y = Inf, label = "LLM adoption",
             hjust = -0.05, vjust = 1.5, size = 2, colour = "firebrick") +
    facet_wrap(~ method_id, scales = "free_y", ncol = 3) +
    labs(
      x        = "Year",
      y        = "Observed paper count",
      title    = "Top 15 methods: raw observed counts (phi-free v3)",
      subtitle = "Orange = loess smoother; dashed = 2023"
    ) +
    theme_minimal(base_size = 7) +
    theme(strip.text = element_text(size = 5), panel.grid.minor = element_blank())

  ggsave(KF_PLOT_RAW, p5, width = 18, height = 12, units = "in", dpi = 150)
  cat("Plot saved:", KF_PLOT_RAW, "\n")

  # ── Send plots via Telegram ───────────────────────────────────────────────
  kf_plots <- c(KF_PLOT_SIGMA, KF_PLOT_DIVERSITY, KF_PLOT_GAMMA_DOT,
                KF_PLOT_TOP_GAMMA, KF_PLOT_RAW)
  cat("\nSending plots via Telegram...\n")
  for (plot_path in kf_plots) {
    tryCatch({
      resp <- httr::POST(
        url  = paste0("https://api.telegram.org/bot", token, "/sendPhoto"),
        body = list(
          chat_id = chat_id,
          photo   = httr::upload_file(plot_path),
          caption = paste0("phi-free v3: ", basename(plot_path))
        ),
        encode = "multipart"
      )
      cat("Telegram photo HTTP", httr::status_code(resp), ":", basename(plot_path), "\n")
    }, error = function(e) {
      cat("WARNING: Telegram photo failed:", basename(plot_path), ":", conditionMessage(e), "\n")
    })
  }

  # ── Auto-fill phi_results.md and push to GitHub ─────────────────────────
  message("Filling phi_results.md placeholders...")

  sm <- rstan::summary(fit, pars = c("phi", "sigma_beta", "sigma_gamma"))$summary

  phi_mean    <- round(sm["phi",       "mean"],  1)
  phi_ci      <- paste0("[", round(sm["phi",       "2.5%"], 1),
                           ", ", round(sm["phi",       "97.5%"], 1), "]")
  sg_mean       <- round(sm["sigma_gamma", "mean"],  4)
  sg_ci         <- paste0("[", round(sm["sigma_gamma", "2.5%"], 4),
                           ", ", round(sm["sigma_gamma", "97.5%"], 4), "]")
  sb_mean       <- round(sm["sigma_beta",  "mean"],  4)
  sg_rhat       <- round(sm["sigma_gamma", "Rhat"],  4)
  sg_ess        <- round(sm["sigma_gamma", "n_eff"])
  converged_str <- ifelse(sg_rhat < 1.01 & sg_ess > 400,
                          "YES (Rhat OK, ESS OK)",
                          paste0("PARTIAL (Rhat=", sg_rhat,
                                 ", ESS=", sg_ess, ")"))

  phi_results <- readLines("docs/phi_results.md")
  phi_results <- gsub("{{PHI_FREE_PHI_MEAN}}",        phi_mean,    phi_results, fixed=TRUE)
  phi_results <- gsub("{{PHI_FREE_PHI_CI}}",          phi_ci,      phi_results, fixed=TRUE)
  phi_results <- gsub("{{PHI_FREE_SIGMA_GAMMA_MEAN}}", sg_mean,       phi_results, fixed=TRUE)
  phi_results <- gsub("{{PHI_FREE_SIGMA_GAMMA_CI}}",   sg_ci,         phi_results, fixed=TRUE)
  phi_results <- gsub("{{PHI_FREE_SIGMA_BETA_MEAN}}",  sb_mean,       phi_results, fixed=TRUE)
  phi_results <- gsub("{{PHI_FREE_RHAT}}",             sg_rhat,       phi_results, fixed=TRUE)
  phi_results <- gsub("{{PHI_FREE_ESS}}",              sg_ess,        phi_results, fixed=TRUE)
  phi_results <- gsub("{{PHI_FREE_RUNTIME}}",          elapsed_min,   phi_results, fixed=TRUE)
  phi_results <- gsub("{{PHI_FREE_CONVERGED}}",        converged_str, phi_results, fixed=TRUE)
  phi_results <- gsub("{{PHI_FREE_SUMMARY_PHI}}",
                      paste0(phi_mean, " (estimated)"), phi_results, fixed=TRUE)
  writeLines(phi_results, "docs/phi_results.md")

  system(paste0(
    "cd ~/R_projects/Vibe_Coding_Paper && ",
    "git add docs/phi_results.md data/output/phi_free/*.png && ",
    "git commit -m 'auto: phi-free v3 results and plots' && ",
    "git push"
  ))
  message("GitHub push complete.")

}  # end post-processing block

cat("\n01b_fit_phi_free.R complete.\n")
