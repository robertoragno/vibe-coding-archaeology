# Vibe Coding Paper — Project Context

## What this project is
Scientometric study testing whether LLMs cause methodological convergence 
in computational archaeology. Stan model estimates methodological diversity 
(Inverse Simpson) within L2 method groups over time (2010-2025).

## Repository
Private GitHub repo: https://github.com/robertoragno/vibe-coding-archaeology
Created 2026-04-03. Auto-push implemented in R/02_extract_plot.R (L3) and R/03_l2_analysis.R (L2).

## File structure
- R/00_data_prep.R         → reads qwen_dataset.xlsx, saves stan_data.rds + vocab.rds
- R/01_fit_model.R         → fits Stan model (phi=10), saves fit.rds (guarded), sends Telegram
- R/01b_fit_phi_free.R   → phi-free sensitivity fit; saves fit_phi_free.rds; auto-pushes docs/phi_results.md
- R/02_extract_plot.R      → extracts draws, saves plots to data/output/l3/, auto-pushes docs/l3_results.md
- R/03_l2_analysis.R       → L1->L2 complementary analysis; saves fit_l2.rds (guarded); auto-pushes docs/l2_results.md
- R/04_workflow_checks.R   → automated diagnostics and workflow validation
- R/00b_phi_exploration.R → empirical phi estimation across L2 groups
- stan/diversity_model.stan          → primary Stan model (L3-level, phi=10 fixed)
- stan/diversity_model_phi_free.stan → phi-free variant
- data/output/l3/          → L3 PNGs
- data/output/l2/          → L2 PNGs
- data/output/phi_free/  → phi-free sensitivity PNGs
- data/output/stan_data.rds + vocab.rds → committed
- data/output/fit.rds + l2/fit_l2.rds + fit_phi_free.rds → gitignored (too large)
- docs/l3_results.md       → auto-filled and pushed by R/02_extract_plot.R
- docs/l2_results.md       → auto-filled and pushed by R/03_l2_analysis.R
- docs/phi_results.md    → auto-filled and pushed by R/01b_fit_phi_free.R
- experiment/prompts/, experiment/responses/, experiment/analysis/ → LLM experiment scaffold

## Key technical facts
- rstan 2.32.2 — use hand-rolled dm_log(), NOT built-in dirichlet_multinomial
- Primary model: phi fixed at 10 as data input. phi = Dirichlet-Multinomial precision; higher phi = tighter shares, less overdispersion.
- Sensitivity model (01b) estimates phi freely. phi sampled as log_phi (unbounded) for HMC geometry; phi = exp(log_phi) in transformed parameters. Prior: log_phi ~ N(log(100), 1.0).
- Padding slots pinned with normal(0, 0.001) or HMC takes 33 hours
- Per-method slopes have sum-to-zero constraint (implemented and working)
- Two-slope model: beta_method = baseline linear trend (2010-2025), gamma_method = differential post-2023 shift
- post_llm indicator (1 for year >= 2023, 0 otherwise) and year_std stored in stan_data.rds
- Year filter: 2010-2025 only (raw data goes back to 1967)
- paper_id column is called abstract_id in qwen_dataset.xlsx
- rstan extract() drops dimensions of length 1: when K_g[g] == 1, indexing
  a 3D array [S, K, N_years] with eta[,,t] collapses K -> plain vector. Fix:
  always use matrix(eta[,,t], nrow = S, ncol = K) before apply() or rowSums()
- Run all scripts with Rscript R/scriptname.R from the project root

## Fit guards
- R/01_fit_model.R:       skips sampling if data/output/fit.rds exists
- R/01b_fit_phi_free.R: skips sampling if data/output/fit_phi_free_v3.done exists (v3 = log_phi reparameterisation)
- R/03_l2_analysis.R:     skips sampling if data/output/l2/fit_l2.rds exists
- Delete the guard file to force a refit

## Runtime
- Primary L3 model (phi=10): ~166 min
- Phi-free model v2 (01b, old): ~157 min
- Phi-free model v3 (01b, log_phi): estimated ~300-400 min (4000 iter, warmup 2000)
- Spline model (abandoned): ~1093 min

## Current status (2026-04-07)
- Primary L3 fit (phi=10): sigma_gamma mean=0.056, 95%CI [0.0018, 0.167]; Rhat OK
- Phi-free v2 fit (fit_phi_free.rds, Apr 6) — PARTIAL CONVERGENCE ONLY:
  - phi posterior: mean~600, median~510 (much larger than prior median of 100)
  - sigma_gamma: mean=0.25, 90%CI [0.043, 0.383] — Rhat=1.082, ESS=67; DO NOT USE
  - 28% iterations hit max_treedepth=12; root cause: phi sampled on constrained positive reals
- Phi-free v3 (log_phi parameterisation): PENDING — run R/01b_fit_phi_free.R to fit

## Changelog
- 2026-04-07: kappa renamed to phi throughout (precision parameter; higher phi = less overdispersion)
- 2026-04-07: phi-free model v3: log_phi parameterisation for HMC geometry; warmup=2000, iter=4000, max_treedepth=14; done flag is fit_phi_free_v3.done
- 2026-04-07: 01b_fit_phi_free.R restructured so post-processing runs even when done flag exists; Telegram token hardcoded; git add no longer tries to add gitignored .rds
- 2026-04-04: generated quantities now uses conjugate Dirichlet posterior for diversity metrics. For each posterior draw, pi[g,t] ~ Dirichlet(softmax(eta)*phi + y) rather than softmax(eta) directly. This is in both stan/diversity_model.stan and R/03_l2_analysis.R. fit.rds does NOT need to be regenerated.
- 2026-04-04: 03_l2_analysis.R — removed softmax share trajectory plot; raw counts plot renumbered to p4, loess smoother updated.
- 2026-04-04: 02_extract_plot.R — removed softmax trajectory plot; Telegram diagnostics section added.

## Next steps
1. Run phi-free v3: Rscript R/01b_fit_phi_free.R (log_phi parameterisation; target ESS>400, Rhat<1.01)
2. Compare sigma_gamma posteriors at L3 (fit.rds) vs L2 (fit_l2.rds)
3. Run prompting experiment (see experiment/README.md)
4. Correlate LLM recommendation frequencies with posterior mean gamma per L3 method

## Hard constraints (read before editing scripts)
- vocab.rds and stan_data.rds are in data/output/ — always load from there, never reconstruct inline
- TOKEN and CHAT_ID are already hardcoded near the top of each script — do not add Sys.getenv() or redefine
- No Co-authored-by in git commits
- No sudo
- Show full diff to user before writing any file
