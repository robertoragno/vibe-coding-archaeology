cat("=== 02_extract_plot.R ===\n")

library(rstan)
library(dplyr)
library(tidyr)
library(ggplot2)
library(httr)

FIT_RDS        <- "data/output/fit.rds"
VOCAB_RDS      <- "data/output/vocab.rds"
STAN_DATA_RDS  <- "data/output/stan_data.rds"
SUMMARY_CSV    <- "data/output/inv_simpson_summary.csv"
PLOT_DIVERSITY <- "data/output/l3/plot_diversity_by_group.png"
PLOT_SIGMA     <- "data/output/l3/plot_sigma_posteriors.png"
PLOT_GAMMA_DOT <- "data/output/l3/plot_gamma_dotplot.png"
PLOT_RAW       <- "data/output/l3/plot_raw_counts.png"
DRAWS_RDS      <- "data/output/inv_simpson_draws.rds"

token   <- "TELEGRAM_BOT_TOKEN_REDACTED"
chat_id <- Sys.getenv("TELEGRAM_CHAT_ID")

dir.create("data/output/l3", recursive = TRUE, showWarnings = FALSE)

cat("Loading fit, vocab, stan_data...\n")
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

# ── Diagnostic: print array shapes immediately ────────────────────────────────
cat("\n--- Array shape diagnostics ---\n")
mu_raw_arr      <- rstan::extract(fit, pars = "mu_raw")$mu_raw
beta_method_arr <- rstan::extract(fit, pars = "beta_method")$beta_method
gamma_method_arr <- rstan::extract(fit, pars = "gamma_method")$gamma_method
cat("mu_raw dims:       ", paste(dim(mu_raw_arr),       collapse = " x "), "\n")
cat("beta_method dims:  ", paste(dim(beta_method_arr),  collapse = " x "), "\n")
cat("gamma_method dims: ", paste(dim(gamma_method_arr), collapse = " x "), "\n")
cat("K_g range: min =", min(K_g_vec), ", max =", max(K_g_vec), "\n")

zero_K <- which(K_g_vec == 0)
if (length(zero_K) > 0) {
  stop("K_g == 0 for groups: ", paste(zero_K, collapse = ", "),
       " — data prep must have failed for these groups.")
}

S     <- dim(mu_raw_arr)[1]
K_max <- dim(mu_raw_arr)[3]
cat("Posterior draws S =", S, ", K_max =", K_max, "\n")

# ── Plot 1: Diversity by group (inv_simpson) ──────────────────────────────────
cat("\nExtracting inv_simpson draws...\n")
inv_simp_arr <- rstan::extract(fit, pars = "inv_simpson")$inv_simpson  # [S, N_groups, N_years]
cat("inv_simpson dims:", paste(dim(inv_simp_arr), collapse = " x "), "\n")

cat("Reshaping to tidy format...\n")
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

saveRDS(inv_simp_tidy, DRAWS_RDS)
cat("Raw draws saved to:", DRAWS_RDS, "\n")

cat("Summarising...\n")
inv_simp_summary <- inv_simp_tidy |>
  group_by(level_2_mid, year) |>
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

cat("Plotting diversity by group...\n")
inv_simp_summary <- inv_simp_summary |>
  mutate(label = sub("^L2-\\d+: ", "", level_2_mid))

p1 <- ggplot(inv_simp_summary, aes(x = year, y = median)) +
  geom_ribbon(aes(ymin = lo90, ymax = hi90), alpha = 0.15, fill = "steelblue") +
  geom_ribbon(aes(ymin = lo50, ymax = hi50), alpha = 0.30, fill = "steelblue") +
  geom_line(colour = "steelblue4", linewidth = 0.6) +
  geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick", linewidth = 0.4) +
  annotate("text", x = 2023, y = Inf, label = "LLM adoption",
           hjust = -0.05, vjust = 1.5, size = 2, colour = "firebrick") +
  facet_wrap(~ label, scales = "free_y", ncol = 6) +
  labs(
    x = "Year", y = "Inverse Simpson (effective N of L3 methods)",
    title    = "Methodological diversity within L2 groups over time",
    subtitle = "Ribbon = 50% and 90% posterior credible intervals"
  ) +
  theme_minimal(base_size = 8) +
  theme(strip.text = element_text(size = 6), panel.grid.minor = element_blank())

ggsave(PLOT_DIVERSITY, p1, width = 20, height = 16, units = "in", dpi = 150)
cat("Plot saved to:", PLOT_DIVERSITY, "\n")

# ── Plot 2: sigma_beta and sigma_gamma side-by-side ───────────────────────────
cat("Plotting sigma posteriors (sigma_beta and sigma_gamma)...\n")
sigma_beta_draws  <- rstan::extract(fit, pars = "sigma_beta")$sigma_beta
sigma_gamma_draws <- rstan::extract(fit, pars = "sigma_gamma")$sigma_gamma

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
print(summary(fit, pars = "sigma_beta")$summary)
cat("\n--- sigma_gamma summary (KEY SCIENTIFIC QUANTITY) ---\n")
print(summary(fit, pars = "sigma_gamma")$summary)

# ── Extract diagnostic values for doc auto-fill ───────────────────────────────
n_divergences    <- sum(rstan::get_divergent_iterations(fit))
sm_diag          <- rstan::summary(fit, pars = c("sigma_beta", "sigma_gamma"))$summary
rhat_sigma_beta  <- sm_diag["sigma_beta",  "Rhat"]
rhat_sigma_gamma <- sm_diag["sigma_gamma", "Rhat"]
ess_sigma_beta   <- sm_diag["sigma_beta",  "n_eff"]
ess_sigma_gamma  <- sm_diag["sigma_gamma", "n_eff"]
sigma_beta_mean  <- sm_diag["sigma_beta",  "mean"]
sigma_gamma_mean <- sm_diag["sigma_gamma", "mean"]
sigma_beta_ci_str  <- paste0("[", round(sm_diag["sigma_beta",  "2.5%"],  4),
                              ", ", round(sm_diag["sigma_beta",  "97.5%"], 4), "]")
sigma_gamma_ci_str <- paste0("[", round(sm_diag["sigma_gamma", "2.5%"],  4),
                              ", ", round(sm_diag["sigma_gamma", "97.5%"], 4), "]")

# ── Telegram: send diagnostics text ──────────────────────────────────────────
tryCatch({
  div_flag    <- if (n_divergences == 0) "Divergences: 0 [OK]" else paste0("Divergences: ", n_divergences, " [!!!]")
  rhat_sb_flag <- if (rhat_sigma_beta  > 1.01) paste0("sigma_beta Rhat = ",  round(rhat_sigma_beta,  3), " [BAD]") else paste0("sigma_beta Rhat = ",  round(rhat_sigma_beta,  3), " [OK]")
  rhat_sg_flag <- if (rhat_sigma_gamma > 1.01) paste0("sigma_gamma Rhat = ", round(rhat_sigma_gamma, 3), " [BAD]") else paste0("sigma_gamma Rhat = ", round(rhat_sigma_gamma, 3), " [OK]")
  ess_sb_flag  <- if (ess_sigma_beta   < 400)  paste0("sigma_beta ESS = ",   round(ess_sigma_beta),        " [BAD]") else paste0("sigma_beta ESS = ",  round(ess_sigma_beta),        " [OK]")
  ess_sg_flag  <- if (ess_sigma_gamma  < 400)  paste0("sigma_gamma ESS = ",  round(ess_sigma_gamma),       " [BAD]") else paste0("sigma_gamma ESS = ", round(ess_sigma_gamma),       " [OK]")
  sg_line <- paste0("sigma_gamma (post-LLM shift): mean = ", round(sigma_gamma_mean, 4),
                    ", 95% CI ", sigma_gamma_ci_str)
  sb_line <- paste0("sigma_beta  (baseline trend): mean = ", round(sigma_beta_mean,  4),
                    ", 95% CI ", sigma_beta_ci_str)
  n_sig_methods <- sum(gamma_df$sig, na.rm = TRUE)

  msg <- paste(
    "L3 Stan diagnostics (diversity_model)",
    div_flag, rhat_sb_flag, rhat_sg_flag, ess_sb_flag, ess_sg_flag,
    sg_line, sb_line,
    paste0("Methods with credible post-LLM shift: ", n_sig_methods),
    sep = "\n"
  )

  httr::POST(
    url    = paste0("https://api.telegram.org/bot", token, "/sendMessage"),
    body   = list(chat_id = chat_id, text = msg),
    encode = "form"
  )
  cat("Telegram diagnostics sent.\n")
}, error = function(e) {
  cat("WARNING: Telegram diagnostics failed:", conditionMessage(e), "\n")
})

# ── Extract gamma_method posteriors ───────────────────────────────────────────
# gamma_method_arr shape: [S, N_groups, K_max]
# Use matrix(..., nrow=S, ncol=K) to guard against K==1 dimension drop.
cat("\nExtracting gamma_method posteriors per method...\n")

gamma_list <- vector("list", N_groups)

for (grp in seq_len(N_groups)) {
  K <- K_g_vec[grp]

  # matrix() prevents dim-drop when K == 1
  gm_g <- matrix(gamma_method_arr[, grp, 1:K], nrow = S, ncol = K)  # [S, K]

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

cat("Methods with 90% CI excluding zero (credible post-LLM shift):",
    sum(gamma_df$sig, na.rm = TRUE), "\n")

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
  geom_errorbarh(aes(xmin = lo90, xmax = hi90),
                 height = 0.3, linewidth = 0.35) +
  scale_colour_manual(values = c("positive" = "firebrick", "negative" = "steelblue"),
                      guide = "none") +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  labs(
    x        = "Posterior mean gamma (post-LLM differential slope)",
    y        = NULL,
    title    = "Differential post-2023 method slopes (gamma_method)",
    subtitle = "Only methods where 90% CI excludes zero; red = gaining share, blue = losing share"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    axis.text.y        = element_text(size = 5),
    panel.grid.major.y = element_blank()
  )

plot_h <- max(8, 0.15 * nrow(sig_gamma))
ggsave(PLOT_GAMMA_DOT, p3, width = 14, height = plot_h, units = "in", dpi = 150, limitsize = FALSE)
cat("Plot saved to:", PLOT_GAMMA_DOT, "\n")

# ── Top 15 methods by |gamma| ─────────────────────────────────────────────────
top15 <- gamma_df |>
  mutate(abs_gamma = abs(mean_gamma)) |>
  arrange(desc(abs_gamma)) |>
  slice_head(n = 15)

cat("\nTop 15 methods by |mean_gamma|:\n")
print(top15 |> select(level_2_mid, level_3_fine, mean_gamma, lo90, hi90))

# ── Plot 4: raw observed counts for top 15 ────────────────────────────────────
cat("Plotting raw counts for top 15 methods...\n")

raw_counts_list <- vector("list", nrow(top15))

for (i in seq_len(nrow(top15))) {
  g_i <- top15$g[i]
  k_i <- top15$k[i]

  raw_df <- data.frame(
    year    = year_levels,
    n_papers = as.integer(stan_data$counts[g_i, , k_i])
  )

  method_label <- paste0(
    sub("^L2-\\d+: ", "", l2_levels[g_i]), ": ", top15$level_3_fine[i]
  )
  raw_df$method_id <- method_label
  raw_counts_list[[i]] <- raw_df
}

raw_all <- bind_rows(raw_counts_list) |>
  mutate(method_id = factor(
    method_id,
    levels = paste0(
      sub("^L2-\\d+: ", "", l2_levels[top15$g]),
      ": ", top15$level_3_fine
    )
  ))

p5 <- ggplot(raw_all, aes(x = year, y = n_papers)) +
  geom_point(size = 1, colour = "grey40") +
  geom_smooth(method = "loess", se = TRUE, colour = "firebrick",
              fill = "firebrick", alpha = 0.15,
              linewidth = 1.2, span = 0.75) +
  geom_vline(xintercept = 2023, linetype = "dashed", colour = "firebrick",
             linewidth = 0.4) +
  annotate("text", x = 2023, y = Inf, label = "LLM adoption",
           hjust = -0.05, vjust = 1.5, size = 2, colour = "firebrick") +
  facet_wrap(~ method_id, scales = "free_y", ncol = 3) +
  labs(
    x = "Year", y = "Observed paper count",
    title    = "Top 15 methods: raw observed paper counts 2010-2025",
    subtitle = "Loess smoother; dashed = 2023; sanity check that model tracks real signal"
  ) +
  theme_minimal(base_size = 7) +
  theme(strip.text = element_text(size = 5), panel.grid.minor = element_blank())

ggsave(PLOT_RAW, p5, width = 18, height = 12, units = "in", dpi = 150)
cat("Plot saved to:", PLOT_RAW, "\n")

# ── Telegram: send all plots ───────────────────────────────────────────────────
all_plots <- c(PLOT_DIVERSITY, PLOT_SIGMA, PLOT_GAMMA_DOT, PLOT_RAW)

cat("\nSending plots via Telegram...\n")
for (plot_path in all_plots) {
  cat("Sending:", basename(plot_path), "\n")
  tryCatch({
    resp <- httr::POST(
      url  = paste0("https://api.telegram.org/bot", token, "/sendPhoto"),
      body = list(
        chat_id = chat_id,
        photo   = httr::upload_file(plot_path),
        caption = basename(plot_path)
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

# ── Auto-push L3 results to GitHub ────────────────────────────────────────────
message("Pushing L3 results to GitHub...")
results_text <- readLines("docs/l3_results.md")
results_text <- gsub("{{DIVERGENCES}}",     n_divergences,                                 results_text, fixed = TRUE)
results_text <- gsub("{{RHAT_SIGMA_BETA}}",  round(rhat_sigma_beta,  4),                   results_text, fixed = TRUE)
results_text <- gsub("{{RHAT_SIGMA_GAMMA}}", round(rhat_sigma_gamma, 4),                   results_text, fixed = TRUE)
results_text <- gsub("{{ESS_SIGMA_BETA}}",   round(ess_sigma_beta),                        results_text, fixed = TRUE)
results_text <- gsub("{{ESS_SIGMA_GAMMA}}",  round(ess_sigma_gamma),                       results_text, fixed = TRUE)
results_text <- gsub("{{SIGMA_BETA_MEAN}}",  round(sigma_beta_mean,  4),                   results_text, fixed = TRUE)
results_text <- gsub("{{SIGMA_BETA_CI}}",    sigma_beta_ci_str,                            results_text, fixed = TRUE)
results_text <- gsub("{{SIGMA_GAMMA_MEAN}}", round(sigma_gamma_mean, 4),                   results_text, fixed = TRUE)
results_text <- gsub("{{SIGMA_GAMMA_CI}}",   sigma_gamma_ci_str,                           results_text, fixed = TRUE)
results_text <- gsub("{{RATIO}}",            round(sigma_gamma_mean / sigma_beta_mean, 3), results_text, fixed = TRUE)
writeLines(results_text, "docs/l3_results.md")
system("git -C ~/R_projects/Vibe_Coding_Paper add data/output/l3/*.png docs/l3_results.md && git -C ~/R_projects/Vibe_Coding_Paper commit -m 'auto: L3 model results update' && git -C ~/R_projects/Vibe_Coding_Paper push")

cat("=== 02_extract_plot.R DONE ===\n")
