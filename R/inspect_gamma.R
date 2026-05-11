#!/usr/bin/env Rscript
# inspect_gamma.R  —  extract gamma_method posteriors from fit_phi_free.rds
# Usage: Rscript R/inspect_gamma.R
# Output: data/output/phi_free/gamma_results.csv

library(dplyr, quietly = TRUE)

OUTPUT_DIR <- "data/output"
FIT_PATH   <- file.path(OUTPUT_DIR, "fit_phi_free.rds")
VOCAB_PATH <- file.path(OUTPUT_DIR, "vocab.rds")
SD_PATH    <- file.path(OUTPUT_DIR, "stan_data.rds")
OUT_CSV    <- file.path(OUTPUT_DIR, "phi_free", "gamma_results.csv")

for (p in c(FIT_PATH, VOCAB_PATH, SD_PATH)) {
  if (!file.exists(p)) stop("Missing file: ", p)
}

cat("Loading fit, vocab, stan_data...\n")
fit       <- readRDS(FIT_PATH)
vocab     <- readRDS(VOCAB_PATH)
stan_data <- readRDS(SD_PATH)

l2_levels   <- vocab$l2_levels
year_levels <- vocab$year_levels
N_groups    <- length(l2_levels)
K_g_vec     <- vocab$K_g

draws <- fit$draws(format = "draws_matrix")
S     <- nrow(draws)

cat("\n--- sigma_gamma (KEY ESTIMAND) ---\n")
print(fit$summary(variables = "sigma_gamma"))
cat("\n--- sigma_beta ---\n")
print(fit$summary(variables = "sigma_beta"))
cat("\n--- phi ---\n")
print(fit$summary(variables = "phi"))

get_gamma_matrix <- function(grp, K) {
  gm_g <- matrix(NA_real_, nrow = S, ncol = K)
  for (k in seq_len(K))
    gm_g[, k] <- draws[, sprintf("gamma_method[%d,%d]", grp, k)]
  gm_g
}

cat("Draws S =", S, ", N_groups =", N_groups, "\n")

# ── Extract gamma_method draws ─────────────────────────────────────────────────
cat("\nExtracting gamma_method draws...\n")

gamma_list <- vector("list", N_groups)
for (grp in seq_len(N_groups)) {
  K    <- K_g_vec[grp]
  gm_g <- get_gamma_matrix(grp, K)

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
    sd_gamma     = apply(gm_g, 2, sd),
    lo90         = apply(gm_g, 2, quantile, 0.05),
    hi90         = apply(gm_g, 2, quantile, 0.95),
    lo95         = apply(gm_g, 2, quantile, 0.025),
    hi95         = apply(gm_g, 2, quantile, 0.975),
    stringsAsFactors = FALSE
  )
}

gamma_df <- bind_rows(gamma_list) |>
  mutate(
    sig90       = (lo90 > 0 | hi90 < 0),
    sig95       = (lo95 > 0 | hi95 < 0),
    group_label = sub("^L2-\\d+: ", "", l2),
    method_id   = paste0(group_label, ": ", l3)
  )

cat("\nMethods with 90% CI excluding zero:", sum(gamma_df$sig90, na.rm = TRUE), "\n")
cat("Methods with 95% CI excluding zero:", sum(gamma_df$sig95, na.rm = TRUE), "\n")

# ── Top 20 by |mean_gamma| ────────────────────────────────────────────────────
top20 <- gamma_df |>
  mutate(abs_gamma = abs(mean_gamma)) |>
  arrange(desc(abs_gamma)) |>
  slice_head(n = 20)

cat("\nTop 20 methods by |mean_gamma|:\n")
print(top20 |> select(l2, l3, mean_gamma, sd_gamma, lo90, hi90, sig90))

# ── Save full results ─────────────────────────────────────────────────────────
dir.create(dirname(OUT_CSV), recursive = TRUE, showWarnings = FALSE)
write.csv(gamma_df, OUT_CSV, row.names = FALSE)
cat("\nFull gamma results saved to:", OUT_CSV, "\n")
cat("Rows:", nrow(gamma_df), "\n")
