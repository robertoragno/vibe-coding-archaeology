cat("=== 01_fit_model.R ===\n")

library(rstan)

options(mc.cores = parallel::detectCores())
rstan_options(auto_write = TRUE)

# ── Paths ─────────────────────────────────────────────────────────────────────
STAN_DATA_RDS <- "data/output/stan_data.rds"
VOCAB_RDS     <- "data/output/vocab.rds"
STAN_FILE     <- "stan/diversity_model.stan"
FIT_RDS       <- "data/output/fit.rds"
FIT_RDS_K50   <- "data/output/fit_kappa50.rds"

# ── Load data ─────────────────────────────────────────────────────────────────
cat("Loading stan_data...\n")
stan_data <- readRDS(STAN_DATA_RDS)
vocab     <- readRDS(VOCAB_RDS)

cat("N_groups:", stan_data$N_groups, "\n")
cat("N_years: ", stan_data$N_years,  "\n")
cat("K_max:   ", stan_data$K_max,    "\n")
cat("post_llm:", stan_data$post_llm, "\n")

# ── Fit (guarded) ─────────────────────────────────────────────────────────────
if (!file.exists(FIT_RDS)) {
  cat("Compiling and sampling (this will take a while)...\n")
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
      max_treedepth = 15
    ),
    refresh = 100
  ))

  t_elapsed   <- proc.time() - t_start
  elapsed_min <- round(t_elapsed["elapsed"] / 60, 1)
  cat("Sampling done. Elapsed:", elapsed_min, "minutes\n")

  # ── HMC diagnostics (console) ───────────────────────────────────────────────
  cat("\n--- HMC diagnostics ---\n")
  check_hmc_diagnostics(fit)

  cat("\n--- sigma_beta summary ---\n")
  print(summary(fit, pars = "sigma_beta")$summary)

  cat("\n--- sigma_gamma summary ---\n")
  print(summary(fit, pars = "sigma_gamma")$summary)

  saveRDS(fit, FIT_RDS)
  cat("Fit saved to:", FIT_RDS, "\n")

} else {
  message("fit.rds already exists — skipping Stan run. Delete it to refit.")
  fit <- readRDS(FIT_RDS)
}

# ── Telegram diagnostics ──────────────────────────────────────────────────────
token   <- "TELEGRAM_BOT_TOKEN_REDACTED"
chat_id <- Sys.getenv("TELEGRAM_CHAT_ID")

tryCatch({
  library(httr)

  # Divergences
  n_div    <- sum(rstan::get_divergent_iterations(fit))
  div_flag <- if (n_div == 0) "Divergences: 0" else paste0("Divergences: ", n_div, " !!!")

  # Rhat and ESS for sigma_beta and sigma_gamma
  sm <- rstan::summary(fit, pars = c("sigma_beta", "sigma_gamma"))$summary

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

  # sigma_gamma: key scientific quantity
  sg_mean <- round(sm["sigma_gamma", "mean"], 4)
  sg_lo   <- round(sm["sigma_gamma", "5%"],   4)
  sg_hi   <- round(sm["sigma_gamma", "95%"],  4)
  sg_line <- paste0("sigma_gamma (KEY - post-LLM shift scale): mean = ", sg_mean,
                    ", 90% CI [", sg_lo, ", ", sg_hi, "]")

  msg <- paste(
    "Stan diagnostics: diversity_model (two-slope)",
    div_flag,
    rhat_sb_flag,
    rhat_sg_flag,
    ess_sb_flag,
    ess_sg_flag,
    sg_line,
    sep = "\n"
  )

  print("Sending Telegram diagnostics...")
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

# ── kappa=50 robustness fit (guarded) ─────────────────────────────────────────
if (!file.exists(FIT_RDS_K50)) {
  cat("\nFitting kappa=50 robustness check...\n")
  stan_data_k50       <- stan_data
  stan_data_k50$kappa <- 50.0

  t_start50 <- proc.time()

  fit_k50 <- suppressWarnings(stan(
    file    = STAN_FILE,
    data    = stan_data_k50,
    chains  = 4,
    iter    = 2000,
    warmup  = 1000,
    cores   = 4,
    seed    = 42,
    control = list(
      adapt_delta   = 0.95,
      max_treedepth = 15
    ),
    refresh = 100
  ))

  t_elapsed50   <- proc.time() - t_start50
  elapsed_min50 <- round(t_elapsed50["elapsed"] / 60, 1)
  cat("kappa=50 sampling done. Elapsed:", elapsed_min50, "minutes\n")

  cat("\n--- kappa=50 HMC diagnostics ---\n")
  check_hmc_diagnostics(fit_k50)

  saveRDS(fit_k50, FIT_RDS_K50)
  cat("kappa=50 fit saved to:", FIT_RDS_K50, "\n")

  # ── Telegram: kappa=50 robustness check ──────────────────────────────────────
  tryCatch({
    library(httr)

    n_div50    <- sum(rstan::get_divergent_iterations(fit_k50))
    div_flag50 <- if (n_div50 == 0) "Divergences: 0" else paste0("Divergences: ", n_div50, " !!!")

    sm50 <- rstan::summary(fit_k50, pars = c("sigma_beta", "sigma_gamma"))$summary

    rhat_sb50 <- round(sm50["sigma_beta",  "Rhat"],  3)
    rhat_sg50 <- round(sm50["sigma_gamma", "Rhat"],  3)
    ess_sb50  <- round(sm50["sigma_beta",  "n_eff"])
    ess_sg50  <- round(sm50["sigma_gamma", "n_eff"])

    sg50_mean <- round(sm50["sigma_gamma", "mean"], 4)
    sg50_lo   <- round(sm50["sigma_gamma", "5%"],   4)
    sg50_hi   <- round(sm50["sigma_gamma", "95%"],  4)

    msg50 <- paste(
      "kappa=50 robustness check",
      div_flag50,
      paste0("sigma_beta Rhat = ",  rhat_sb50),
      paste0("sigma_gamma Rhat = ", rhat_sg50),
      paste0("sigma_beta ESS = ",   ess_sb50),
      paste0("sigma_gamma ESS = ",  ess_sg50),
      paste0("sigma_gamma (KEY): mean = ", sg50_mean, ", 90% CI [", sg50_lo, ", ", sg50_hi, "]"),
      paste0("Elapsed: ", elapsed_min50, " min"),
      sep = "\n"
    )

    resp50 <- httr::POST(
      url    = paste0("https://api.telegram.org/bot", token, "/sendMessage"),
      body   = list(chat_id = chat_id, text = msg50),
      encode = "form"
    )
    cat("Telegram kappa=50 status:", httr::status_code(resp50), "\n")
  }, error = function(e) {
    message("Telegram kappa=50 error: ", conditionMessage(e))
  })

} else {
  message("fit_kappa50.rds already exists — skipping kappa=50 fit.")
  fit_k50 <- readRDS(FIT_RDS_K50)
}

# ── Robustness comparison: kappa=10 vs kappa=50 ───────────────────────────────
sm10 <- rstan::summary(fit,     pars = "sigma_gamma")$summary
sm50 <- rstan::summary(fit_k50, pars = "sigma_gamma")$summary

sg10_mean <- round(sm10["sigma_gamma", "mean"], 4)
sg10_lo   <- round(sm10["sigma_gamma", "5%"],   4)
sg10_hi   <- round(sm10["sigma_gamma", "95%"],  4)
sg50_mean <- round(sm50["sigma_gamma", "mean"], 4)
sg50_lo   <- round(sm50["sigma_gamma", "5%"],   4)
sg50_hi   <- round(sm50["sigma_gamma", "95%"],  4)

cat("=== ROBUSTNESS CHECK: kappa=10 vs kappa=50 ===\n")
cat("sigma_gamma kappa=10: mean=", sg10_mean, "90% CI [", sg10_lo, ",", sg10_hi, "]\n")
cat("sigma_gamma kappa=50: mean=", sg50_mean, "90% CI [", sg50_lo, ",", sg50_hi, "]\n")
cat("Ratio of means:", round(sg50_mean/sg10_mean, 3), "\n")

cat("=== 01_fit_model.R DONE ===\n")
