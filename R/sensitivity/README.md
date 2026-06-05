# Sensitivity analyses

These scripts are supplementary checks, not part of the main analysis pipeline.

## A_count_threshold.R

Variant of `R/06_step3_llm_comparison.R` that restricts the Step 3
Bayesian NB regression to L3 methods with at least 50 papers in
2023-2025 (controlled by `MIN_COUNT` at the top of the script). This
tests whether the LLM trend-chasing result is driven by rarely-used
methods with noisy gamma estimates. Outputs go to
`data/output/sensitivity/` and `data/output/figures/sensitivity/`.

## D_diversity_trajectory.R + stan/diversity_trajectory.stan

Fits a second-level normal model with measurement error to the
posterior inv_simpson (effective number of L3 methods) from the
phi-free Dirichlet-multinomial fit. Estimates a group-level post-LLM
shift (gamma) and its hierarchical SD (sigma_gamma), providing a
complementary test of methodological convergence that operates on the
diversity index directly rather than on individual method shares.
