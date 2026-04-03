# Vibe Coding Paper — Project Context

## What this project is
Scientometric study testing whether LLMs cause methodological convergence 
in computational archaeology. Stan model estimates methodological diversity 
(Inverse Simpson) within L2 method groups over time (2010-2025).

## Repository
Private GitHub repo: https://github.com/robertoragno/vibe-coding-archaeology
Created 2026-04-03. Auto-push implemented in R/02_extract_plot.R (L3) and R/03_l2_analysis.R (L2).

## File structure
- R/00_data_prep.R    → reads qwen_dataset.xlsx, saves stan_data.rds + vocab.rds
- R/01_fit_model.R    → fits Stan model, saves fit.rds (guarded), sends Telegram notification
- R/02_extract_plot.R → extracts draws, saves plots to data/output/l3/, auto-pushes docs/l3_results.md
- R/03_l2_analysis.R  → L1->L2 complementary analysis; saves fit_l2.rds (guarded); auto-pushes docs/l2_results.md
- stan/diversity_model.stan → the Stan model (L3-level, source of truth)
- data/output/l3/     → L3 PNGs
- data/output/l2/     → L2 PNGs
- data/output/stan_data.rds + vocab.rds → committed
- data/output/fit.rds + l2/fit_l2.rds  → gitignored (too large)
- docs/l3_results.md  → auto-filled and pushed by R/02_extract_plot.R
- docs/l2_results.md  → auto-filled and pushed by R/03_l2_analysis.R
- experiment/prompts/, experiment/responses/, experiment/analysis/ → LLM experiment scaffold

## Key technical facts
- rstan 2.32.2 — use hand-rolled dm_log(), NOT built-in dirichlet_multinomial
- kappa fixed at 10 as data input (non-identified if estimated)
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
- R/01_fit_model.R: skips sampling if data/output/fit.rds exists
- R/03_l2_analysis.R: skips sampling if data/output/l2/fit_l2.rds exists
- Delete the relevant .rds file to force a refit

## Runtime
- Two-slope model: ~166 min (expected, based on previous linear model)
- Spline model (abandoned): ~1093 min

## Current status
- Spline model abandoned: over-parameterised, produced uninformative CIs
- Two-slope model implemented and run; results in docs/l3_results.md
- Key scientific result: sigma_gamma mean=0.056, 97.5%=0.167, credibly above zero
- sigma_beta Rhat=1.011, consider iter=4000 before final submission

## Next steps
1. Compare sigma_gamma posteriors at L3 (fit.rds) vs L2 (fit_l2.rds)
2. Run prompting experiment (see experiment/README.md)
3. Correlate LLM recommendation frequencies with posterior mean gamma per L3 method
4. Consider iter=4000 refit if sigma_beta Rhat remains > 1.01
