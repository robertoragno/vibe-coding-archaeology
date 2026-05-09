cat("=== 00b_phi_exploration.R ===\n")
cat("Empirical phi estimation before any modelling.\n")

library(readxl)
library(dplyr)
library(tidyr)
library(ggplot2)
library(httr)

token   <- "TELEGRAM_BOT_TOKEN_REDACTED"
chat_id <- Sys.getenv("TELEGRAM_CHAT_ID")

STAN_DATA_RDS <- "data/output/stan_data.rds"
VOCAB_RDS     <- "data/output/vocab.rds"
INPUT_FILE    <- "data/input/qwen_dataset.xlsx"

dir.create("data/output", recursive = TRUE, showWarnings = FALSE)

# ── Load L3 model data (L2 groups with L3 methods) ───────────────────────────
cat("Loading stan_data and vocab for L3 model (L2 groups)...\n")
stan_data   <- readRDS(STAN_DATA_RDS)
vocab       <- readRDS(VOCAB_RDS)

l2_levels   <- vocab$l2_levels
year_levels <- vocab$year_levels
N_groups_l3 <- length(l2_levels)
N_years     <- length(year_levels)
K_g_l3      <- vocab$K_g
counts_l3   <- stan_data$counts   # [N_groups, N_years, K_max]

# ── Load L2 model data (L1 groups with L2 methods) ───────────────────────────
cat("Loading raw data for L2 model (L1 groups)...\n")
raw <- read_excel(INPUT_FILE) |>
  filter(Year >= 2010, Year <= 2025)

df_l2 <- raw |>
  distinct(abstract_id, Year, level_1_macro, level_2_mid)

l1_levels   <- sort(unique(df_l2$level_1_macro))
N_groups_l2 <- length(l1_levels)

l2_vocab <- df_l2 |>
  distinct(level_1_macro, level_2_mid) |>
  arrange(level_1_macro, level_2_mid) |>
  group_by(level_1_macro) |>
  mutate(k_local = row_number(), K_g = n()) |>
  ungroup() |>
  mutate(g = match(level_1_macro, l1_levels))

K_g_l2 <- l2_vocab |> group_by(g) |> summarise(K = first(K_g)) |> pull(K)
K_max_l2 <- max(K_g_l2)

counts_long_l2 <- df_l2 |>
  mutate(
    g = match(level_1_macro, l1_levels),
    t = match(Year, year_levels)
  ) |>
  left_join(l2_vocab |> select(level_1_macro, level_2_mid, k_local),
            by = c("level_1_macro", "level_2_mid")) |>
  count(g, t, k_local, name = "n_papers")

counts_l2 <- array(0L, dim = c(N_groups_l2, N_years, K_max_l2))
for (i in seq_len(nrow(counts_long_l2))) {
  counts_l2[counts_long_l2$g[i], counts_long_l2$t[i], counts_long_l2$k_local[i]] <-
    counts_long_l2$n_papers[i]
}

# ── MoM phi estimator ───────────────────────────────────────────────────────
# For group g, method k: across years with N >= 5, compute var(p_{k,t}).
# Under DM: Var(p_k) = p_bar_k*(1-p_bar_k)*(phi+N_bar)/(N_bar*(phi+1))
# MoM solve: f = var_obs * N_bar / (p_bar*(1-p_bar)); phi = (N_bar - f)/(f - 1)
#
# For overdispersion ratio per (group, year):
#   obs = sum_k (p_{k,t} - p_bar_k)^2
#   mult = sum_k p_bar_k*(1-p_bar_k)/N_t
#   ratio = obs / mult (1 = pure multinomial)

estimate_phi <- function(counts_arr, K_g_vec, group_labels, year_labels,
                           min_total = 5, level_label = "group") {
  N_g <- length(group_labels)
  N_t <- length(year_labels)

  phi_records  <- list()
  overdisp_records <- list()

  for (g in seq_len(N_g)) {
    K <- K_g_vec[g]
    glabel <- group_labels[g]

    # Qualifying years
    totals <- sapply(seq_len(N_t), function(t) sum(counts_arr[g, t, 1:K]))
    ok_t   <- which(totals >= min_total)
    if (length(ok_t) < 2) next

    # Proportions matrix: rows = years, cols = methods
    prop_mat <- do.call(rbind, lapply(ok_t, function(t) {
      cts <- counts_arr[g, t, 1:K]
      cts / sum(cts)
    }))   # [length(ok_t), K]

    N_ok   <- totals[ok_t]
    N_bar  <- mean(N_ok)
    p_bar  <- colMeans(prop_mat)  # mean proportion per method

    # MoM phi estimate per method k
    for (k in seq_len(K)) {
      if (p_bar[k] <= 0 || p_bar[k] >= 1) next
      pk_vals <- prop_mat[, k]
      if (length(pk_vals) < 2) next
      var_obs <- var(pk_vals)
      if (var_obs <= 0) next
      f <- var_obs * N_bar / (p_bar[k] * (1 - p_bar[k]))
      if (f <= 1) next
      phi_k <- (N_bar - f) / (f - 1)
      if (phi_k > 0 && is.finite(phi_k)) {
        phi_records[[length(phi_records) + 1]] <- data.frame(
          group = glabel, method_k = k, phi_est = phi_k,
          stringsAsFactors = FALSE
        )
      }
    }

    # Overdispersion ratio per (group, year)
    for (i in seq_along(ok_t)) {
      t   <- ok_t[i]
      Nt  <- N_ok[i]
      p_t <- prop_mat[i, ]
      obs_var  <- mean((p_t - p_bar)^2)
      mult_var <- mean(p_bar * (1 - p_bar) / Nt)
      if (mult_var > 0) {
        overdisp_records[[length(overdisp_records) + 1]] <- data.frame(
          group = glabel, year = year_labels[t],
          overdisp = obs_var / mult_var,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  list(
    phi    = bind_rows(phi_records),
    overdisp = bind_rows(overdisp_records)
  )
}

cat("Estimating phi for L2 groups (L3 model data)...\n")
res_l3 <- estimate_phi(counts_l3, K_g_l3, l2_levels, year_levels)

cat("Estimating phi for L1 groups (L2 model data)...\n")
res_l2 <- estimate_phi(counts_l2, K_g_l2, l1_levels, year_levels)

# ── Summary table ─────────────────────────────────────────────────────────────
phi_summary_l3 <- res_l3$phi |>
  group_by(group) |>
  summarise(
    n_methods    = n(),
    phi_median = median(phi_est),
    phi_q25    = quantile(phi_est, 0.25),
    phi_q75    = quantile(phi_est, 0.75),
    phi_iqr    = phi_q75 - phi_q25,
    .groups      = "drop"
  ) |>
  arrange(phi_median)

phi_summary_l2 <- res_l2$phi |>
  group_by(group) |>
  summarise(
    n_methods    = n(),
    phi_median = median(phi_est),
    phi_q25    = quantile(phi_est, 0.25),
    phi_q75    = quantile(phi_est, 0.75),
    phi_iqr    = phi_q75 - phi_q25,
    .groups      = "drop"
  ) |>
  arrange(phi_median)

cat("\n=== L2 group phi summary (L3 model) ===\n")
print(phi_summary_l3, n = Inf)

cat("\n=== L1 group phi summary (L2 model) ===\n")
print(phi_summary_l2, n = Inf)

# ── Plot 1: phi boxplot per L2 group ────────────────────────────────────────
cat("\nPlotting phi distribution per L2 group...\n")

phi_l3_aug <- res_l3$phi |>
  left_join(phi_summary_l3 |> select(group, phi_median, phi_q25, phi_q75),
            by = "group") |>
  mutate(
    group        = factor(group, levels = phi_summary_l3$group),
    fill_colour  = case_when(
      phi_q75 < 10  ~ "underdispersed",
      phi_q25 > 10  ~ "overdispersed",
      TRUE            ~ "neutral"
    )
  )

fill_vals <- c(
  "underdispersed" = "darkorange",
  "overdispersed"  = "firebrick",
  "neutral"        = "steelblue"
)

# Shorten group labels
phi_l3_aug <- phi_l3_aug |>
  mutate(group_short = sub("^L2-\\d+: ", "", as.character(group)),
         group_short = factor(group_short,
                              levels = sub("^L2-\\d+: ", "", levels(group))))

p_phi <- ggplot(phi_l3_aug,
                  aes(x = group_short, y = phi_est, fill = fill_colour)) +
  geom_boxplot(outlier.size = 0.6, outlier.alpha = 0.4, linewidth = 0.3) +
  geom_hline(yintercept = 10, linetype = "dashed", colour = "black", linewidth = 0.5) +
  scale_fill_manual(
    values = fill_vals,
    labels = c("underdispersed" = "75th pctile < 10 (underdispersed)",
               "overdispersed"  = "25th pctile > 10 (overdispersed)",
               "neutral"        = "straddles 10"),
    name   = NULL
  ) +
  scale_y_log10() +
  coord_flip() +
  labs(
    x        = NULL,
    y        = "Estimated phi (log scale)",
    title    = "Empirical phi by L2 group",
    subtitle = "Dashed line = phi = 10 (model assumption); orange = under-dispersed, red = over-dispersed"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    legend.position  = "bottom",
    panel.grid.minor = element_blank()
  )

out_phi <- "data/output/plot_phi_empirical.png"
ggsave(out_phi, p_phi, width = 14, height = 10, units = "in", dpi = 150)
cat("Saved:", out_phi, "\n")

# ── Plot 2: overdispersion heatmap ────────────────────────────────────────────
cat("Plotting overdispersion heatmap...\n")

overdisp_l3 <- res_l3$overdisp |>
  mutate(group_short = sub("^L2-\\d+: ", "", group),
         log_ratio   = log(overdisp))

p_overdisp <- ggplot(overdisp_l3, aes(x = year, y = group_short, fill = log_ratio)) +
  geom_tile(colour = "white", linewidth = 0.15) +
  scale_fill_gradient2(
    low      = "steelblue",
    mid      = "white",
    high     = "firebrick",
    midpoint = 0,
    name     = "log(obs/multinomial)"
  ) +
  scale_x_continuous(breaks = seq(2010, 2025, by = 2)) +
  labs(
    x        = "Year",
    y        = NULL,
    title    = "Overdispersion ratio per L2 group × year",
    subtitle = "White = matches multinomial; red = more overdispersed; blue = less (phi >> 10)"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    axis.text.y      = element_text(size = 6),
    panel.grid       = element_blank(),
    legend.position  = "right"
  )

out_overdisp <- "data/output/plot_overdispersion.png"
ggsave(out_overdisp, p_overdisp, width = 16, height = 14, units = "in", dpi = 150)
cat("Saved:", out_overdisp, "\n")

# ── Send both plots via Telegram ──────────────────────────────────────────────
cat("Sending plots via Telegram...\n")
for (plot_path in c(out_phi, out_overdisp)) {
  tryCatch({
    resp <- httr::POST(
      url  = paste0("https://api.telegram.org/bot", token, "/sendPhoto"),
      body = list(
        chat_id = chat_id,
        photo   = httr::upload_file(plot_path),
        caption = "Phi exploration"
      ),
      encode = "multipart"
    )
    status <- httr::status_code(resp)
    cat("Sent", basename(plot_path), "— HTTP", status, "\n")
  }, error = function(e) {
    cat("WARNING: Telegram failed for", basename(plot_path), ":", conditionMessage(e), "\n")
  })
}

# ── Overall IQR check ─────────────────────────────────────────────────────────
overall_iqr <- IQR(res_l3$phi$phi_est, na.rm = TRUE)
cat("\nOverall IQR of phi estimates (L2 groups):", round(overall_iqr, 2), "\n")

# RECOMMENDATION: phi varies substantially across groups (IQR > 5).
# Consider replacing fixed phi with group-specific phi_g ~ lognormal(mu_phi, sigma_phi)
# with mu_phi ~ normal(log(10), 1) and sigma_phi ~ exponential(1).
# This is identifiable because phi_g is estimated within-group, not competing with mu.
# Expected runtime increase: moderate (not the 33hr issue which was global phi vs mu).

cat("=== 00b_phi_exploration.R DONE ===\n")
