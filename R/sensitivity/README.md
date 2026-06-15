# Sensitivity and supplementary analyses

These scripts sit outside the main numbered pipeline (`R/bibliometric/00`–`05`,
`R/experiment/06`–`07`). Each is standalone and runs after the main pipeline has
produced `data/output/`. Run from the project root, e.g.
`Rscript R/sensitivity/concentration_cluster_bootstrap.R`.

They fall into two kinds.

## Robustness check — does a main result hold under a different choice?

**`concentration_cluster_bootstrap.R`**
Tests whether the concentration intervals from `06_concentration.R` are too
narrow because counts are not independent (an LLM response lists ~7–10 methods
at once; a paper contributes several). Holds the estimator fixed and changes
only the resampling unit — individual recommendations vs whole responses (LLMs)
or whole papers (literature) — and reports the widening factor. The effect is
heterogeneous: up to ~2.9× for Qwen3 under low guidance, but ~1× for Gemma and
the literature, where each cluster carries few methods. The LLM–literature gap
survives either way.
Reads experiment CSVs, `vocab.rds`, and the two `taxonomy_v3` files.
Writes `data/output/sensitivity/concentration_cluster_bootstrap.csv`.

## Complementary analyses — a second route to the same question

**`distributional_similarity.R`**
Compares the whole LLM recommendation distribution against the pre- and
post-2023 literature using cosine similarity, Hellinger distance, and KL
divergence, with a Bayesian posterior-predictive test as the primary inference
and a permutation test as backup. Writes figures to
`data/output/figures/distributional/` and a summary to
`docs/distributional_test_results.md`.

**`diversity_trajectory_model.R`**
Models the inverse Simpson diversity index directly at the L2 group level (with
a measurement-error likelihood carrying the main fit's uncertainty), rather than
working on individual method shares. Estimates a group-level post-2023 shift and
its hierarchical SD. Uses `stan/sensitivity/diversity_trajectory.stan`; writes
`data/output/fit_diversity_trajectory.rds` and a plot to
`data/output/figures/sensitivity/`.

## Archived

Two earlier robustness checks — `rare_method_threshold.R` (drop rarely-used
methods) and `taxonomy_version_remap.R` (v2→v3 fuzzy remap) — moved to
`R/archive/`. Both ran on the single-predictor NB regression that the
two-predictor model in `R/experiment/07_literature_vs_llm.R` superseded, so they
probe an estimand the analysis no longer headlines. Revive and re-point them at
`stan/experiment_prevalence_nb.stan` if these checks are wanted for the
current model.
