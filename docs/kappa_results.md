# Kappa Results: Sensitivity Analysis with Free Kappa

## Overview

This document summarises results from fitting `diversity_model_kappa_free.stan`, which extends the primary L3 model by treating kappa (the Dirichlet-Multinomial concentration parameter) as a free parameter estimated from data rather than fixing it at 10. The goal is to test whether the fixed kappa=10 assumption drives the main conclusions.

## The Model

The kappa-free model is identical to `diversity_model.stan` except that kappa appears in the parameters block with a lognormal prior:

```stan
parameters {
  real<lower=0> kappa;
  ...
}

model {
  kappa ~ lognormal(log(100), 1.0);
  sigma_beta  ~ exponential(2);
  sigma_gamma ~ exponential(4);
  ...
}
```

The prior `lognormal(log(100), 1.0)` has median 100 and 90% interval approximately [14, 716], reflecting the empirical distribution of kappa estimated by `R/00b_kappa_exploration.R` across L2 groups. The primary estimand remains `sigma_gamma` — the global scale of post-LLM slope heterogeneity across methods.

## Reference: Fixed-kappa results (kappa = 10)

These are from the primary analysis in [`docs/l3_results.md`](l3_results.md).

| Parameter | kappa = 10 |
|---|---|
| sigma_gamma mean | 0.0563 |
| sigma_gamma 95% CI | [0.0018, 0.1671] |
| sigma_beta mean | 0.0965 |
| Rhat sigma_gamma | 1.0016 |
| ESS sigma_gamma | 1268 |

## Kappa-free results (v2: lognormal(log(100), 1.0))

| Parameter | kappa free v2 (lognormal(log(100), 1.0)) |
|---|---|
| kappa mean | 599.6 |
| kappa 90% CI | [254.1, 1505.7] |
| sigma_gamma mean | 0.25 |
| sigma_gamma 90% CI | [0.0426, 0.3825] |
| sigma_beta mean | 0.2129 |
| Rhat sigma_gamma | 1.0818 |
| ESS sigma_gamma | 67 |
| Runtime | 157.5 min |

### Plots (kappa-free v2)

> ⚠️ **Note**: ESS=67 for sigma_gamma means these results have not converged.
> Treat all plots below as diagnostic only, not as evidence.

#### 1. Parameter posteriors
Left: sigma_beta (baseline linear trend), centre: sigma_gamma (post-LLM shift scale) —
both compared to the kappa=10 reference. Right: kappa posterior (solid purple) vs
lognormal(log(100), 1.0) prior (dashed). Kappa concentrates far above its prior median (100),
suggesting the data favour a near-Multinomial likelihood.

![Sigma and kappa posteriors](../data/output/kappa_free/kf_plot_sigma_posteriors.png)

#### 2. Methodological diversity by L2 group
Posterior median (line) with 50% and 90% credible intervals (ribbon) for inverse Simpson
diversity within each of the 48 L2 groups. Grey dots = observed annual diversity.
Dashed red line = 2023 LLM adoption boundary.

![Diversity by L2 group](../data/output/kappa_free/kf_plot_diversity_by_group.png)

#### 3. Differential post-2023 slopes (gamma_method)
Methods where the 90% posterior CI for gamma excludes zero — i.e., credible post-LLM
slope change. Red = gaining share, blue = losing share. With ESS=67, almost no methods
pass this threshold; the near-empty plot is a convergence symptom, not a scientific finding.

![Gamma dotplot](../data/output/kappa_free/kf_plot_gamma_dotplot.png)

#### 4. Share trajectories: top 15 methods by |gamma|
Model-fitted share trajectories for the 15 methods with the largest absolute posterior mean
gamma. Shows whether the post-2023 trend change is visible in the fitted shares.

![Top gamma trajectories](../data/output/kappa_free/kf_plot_top_gamma_trajectories.png)

#### 5. Raw observed counts: top 15 methods
Observed paper counts (grey dots) with loess smoother (orange). Pure data — no model.
Useful sanity check: does the raw signal match what the model recovers?

![Raw counts](../data/output/kappa_free/kf_plot_raw_counts.png)

## Summary comparison

| Model | kappa | sigma_gamma mean | sigma_gamma 90% CI | Converged? |
|---|---|---|---|---|
| Fixed kappa = 10 | 10 (fixed) | 0.0563 | [0.0018, 0.1671] | YES |
| Kappa free (v2) | 599.6 (estimated) | 0.25 | [0.0426, 0.3825] | PARTIAL (Rhat=1.0818, ESS=67) |
