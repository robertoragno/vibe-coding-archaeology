# Vibe Coding Paper — Project Context

## What this project is
Scientometric study testing whether LLMs cause methodological convergence
in computational archaeology. Bayesian Dirichlet-Multinomial model estimates
methodological diversity (Inverse Simpson) within 25 L2 sub-disciplines
over time (2010–2026), with a post-2023 level-shift component (gamma).

## Repository
Private GitHub repo: https://github.com/robertoragno/vibe-coding-archaeology

## Key technical facts
- cmdstanr (not rstan) for all MCMC
- Primary model: diversity_model_phi_free.stan — phi estimated from data via log_phi parameterisation
- Posterior: phi ≈ 1133 [605, 2088], sigma_gamma = 0.110 [0.010, 0.222]
- Two-slope structure: beta_method (baseline 2010–2026 trend) + gamma_method (post-2023 shift)
- Padding slots pinned with normal(0, 0.001) — removing this causes multi-hour fits
- Per-method slopes have sum-to-zero soft constraint
- Run all scripts with `Rscript R/scriptname.R` from the project root
- vocab.rds and stan_data.rds are in data/output/ — load from there, never reconstruct

## Python preprocessing pipeline
- `Python/1_dataset/`: Scopus API download + cleaning → df_cleaned.xlsx
- `Python/2_methods_extractions/`: Qwen GGUF extracts computational methods from abstracts
- `Python/3_classification/`: EVoC clustering + LLM labeling builds L2→L3 taxonomy
  - Critical output: `taxonomy_abstract_join.csv` (columns: eid, canonical, is_garbage, l2, l2_description, l3, l3_description)
  - Copy to `data/input/taxonomy_v3/` before running R pipeline
- `Python/4_experiment/`: LLM recommendation simulation (3 profiles × 28 questions × 2 models)
- All local LLM scripts expect a .gguf model in `Python/` or set via `GGUF_MODEL_PATH`

## Experiment
- Two LLMs tested: Qwen3 (Alibaba) and Gemma (Google DeepMind), both local GGUF models
- Three researcher profiles: expert, intermediate, novice
- 28 archaeological research questions × L2 methods × vague families
- Results classified against v3 L3 taxonomy (242 methods)
- Key finding: b_pre (corpus prevalence) credibly positive in all conditions;
  b_gamma (post-2023 trajectory) indistinguishable from zero in all conditions

## Naming conventions
- phi = Dirichlet-Multinomial concentration parameter (never kappa or k)
- gamma = post-2023 excess slope; beta = pre-existing linear trend
- L2 = sub-discipline (25 groups); L3 = specific technique (242 methods); L4 = raw LLM output
