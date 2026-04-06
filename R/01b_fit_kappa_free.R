# 01b_fit_kappa_free.R
# Fits diversity_model_kappa_free.stan with kappa ~ LogNormal(log(25), 0.8)
# This is the principled solution to kappa sensitivity found in 04_workflow_checks.R
# Runtime target: under 8 hours. If exceeded, fall back to kappa=10/50 bracket.

library(rstan)
library(httr)
options(mc.cores = parallel::detectCores())
rstan_options(auto_write = TRUE)

STAN_FILE <- "stan/diversity_model_kappa_free.stan"
FIT_RDS   <- "data/output/fit_kappa_free.rds"
token     <- Sys.getenv("TELEGRAM_TOKEN")
chat_id   <- Sys.getenv("TELEGRAM_CHAT_ID")

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

# ── Load data (kappa removed — it is now a parameter) ─────────────────────────
cat("Loading stan_data...\n")
stan_data        <- readRDS("data/output/stan_data.rds")
stan_data$kappa  <- NULL  # kappa is now a parameter, not data

cat("N_groups:", stan_data$N_groups, "\n")
cat("N_years: ", stan_data$N_years,  "\n")
cat("K_max:   ", stan_data$K_max,    "\n")

# ── Fit (guarded) ─────────────────────────────────────────────────────────────
if (!file.exists(FIT_RDS)) {
  cat("Compiling and sampling kappa-free model...\n")
  cat("Prior: kappa ~ LogNormal(log(25), 0.8)  [5th pct ~5, 95th pct ~130]\n")
  t_start <- proc.time()

  fit <- suppressWarnings(stan(
    file    = STAN_FILE,
    data    = stan_data,
    chains  = 4,
    iter    = 2000,
    warmup  = 1000,
    cores   = 4,
    seed    = 42,
    control = list(
      adapt_delta   = 0.95,
      max_treedepth = 12
    ),
    refresh = 100
  ))

  t_elapsed   <- proc.time() - t_start
  elapsed_min <- round(t_elapsed["elapsed"] / 60, 1)
  cat("Sampling done. Elapsed:", elapsed_min, "minutes\n")

  saveRDS(fit, FIT_RDS)
  cat("Fit saved to:", FIT_RDS, "\n")

  # ── HMC diagnostics ────────────────────────────────────────────────────────
  cat("\n--- HMC diagnostics ---\n")
  check_hmc_diagnostics(fit)

  cat("\n--- sigma_beta summary ---\n")
  print(summary(fit, pars = "sigma_beta")$summary)

  cat("\n--- sigma_gamma summary ---\n")
  print(summary(fit, pars = "sigma_gamma")$summary)

  cat("\n--- kappa summary ---\n")
  print(summary(fit, pars = "kappa")$summary)

  # ── Telegram diagnostics ──────────────────────────────────────────────────
  n_div    <- sum(rstan::get_divergent_iterations(fit))
  div_flag <- if (n_div == 0) "Divergences: 0" else paste0("Divergences: ", n_div, " !!!")

  sm <- rstan::summary(fit, pars = c("sigma_beta", "sigma_gamma", "kappa"))$summary

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

  runtime_flag <- if (elapsed_min > 480)
    "RUNTIME EXCEEDED TARGET — consider kappa bracket instead"
  else
    sprintf("Runtime: %.1f min (target: <480 min)", elapsed_min)

  msg <- paste(
    "kappa-free model diagnostics",
    div_flag,
    fmt_par("sigma_beta"),
    fmt_par("sigma_gamma"),
    fmt_par("kappa"),
    paste("Reference: kappa=10 sigma_gamma~0.054; kappa=50 sigma_gamma~0.095"),
    runtime_flag,
    sep = "\n"
  )

  tg_msg(msg)

} else {
  message("fit_kappa_free.rds exists — skipping. Delete it to refit.")
}

cat("\n01b_fit_kappa_free.R complete.\n")
