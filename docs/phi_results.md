# Phi Results: Sensitivity Analysis with Free Phi

## Overview

This document summarises results from fitting `diversity_model_phi_free.stan`, which extends the primary L3 model by treating phi (the Dirichlet-Multinomial precision/concentration parameter) as a free parameter estimated from data rather than fixing it at 10. The goal is to test whether the fixed phi=10 assumption drives the main conclusions.

**phi interpretation:** phi controls how tightly method shares concentrate around their mean. Higher phi = tighter concentration (less overdispersion, shares vary less year to year); at phi → ∞ the model becomes Multinomial. Fixing phi at a single value is equivalent to a Dirac-delta prior — not properly Bayesian. This model is the principled alternative.

## The Model

The phi-free model is identical to `diversity_model.stan` except that phi is estimated from data. To improve HMC geometry, phi is parameterised on the log scale (`log_phi` is sampled; `phi = exp(log_phi)`):

```stan
parameters {
  real log_phi;  // phi = exp(log_phi); unbounded — better HMC geometry than constrained phi
  ...
}
transformed parameters {
  real<lower=0> phi = exp(log_phi);
  ...
}
model {
  // Equivalent to phi ~ lognormal(log(100), 1.0): median=100, 90% CI ~[14, 716]
  log_phi ~ normal(log(100), 1.0);
  sigma_beta  ~ exponential(2);
  sigma_gamma ~ exponential(4);
  ...
}
```

The prior has median phi=100 and 90% interval approximately [14, 716], reflecting the empirical distribution of phi estimated by `R/00b_phi_exploration.R` across L2 groups. The primary estimand remains `sigma_gamma` — the global scale of post-LLM slope heterogeneity across methods.

## Reference: Fixed-phi results (phi = 10)

These are from the primary analysis in [`docs/l3_results.md`](l3_results.md).

| Parameter | phi = 10 |
|---|---|
| sigma_gamma mean | 0.0563 |
| sigma_gamma 95% CI | [0.0018, 0.1671] |
| sigma_beta mean | 0.0965 |
| Rhat sigma_gamma | 1.0016 |
| ESS sigma_gamma | 1268 |

## Phi-free results (v3: log_phi parameterisation, warmup=2000, iter=4000)

_v3 key change: phi sampled as log_phi (unbounded) for better HMC geometry; warmup doubled; max_treedepth raised to 14._

| Parameter | phi free v3 |
|---|---|
| phi mean | — |
| phi 90% CI | — |
| sigma_gamma mean | — |
| sigma_gamma 90% CI | — |
| sigma_beta mean | — |
| Rhat sigma_gamma | — |
| ESS sigma_gamma | — |
| Runtime | — |

### Phi-free results (v2, unconverged — for reference only)

| Parameter | phi free v2 |
|---|---|
| phi mean | 599.6 |
| phi 90% CI | [254.1, 1505.7] |
| sigma_gamma mean | 0.25 |
| sigma_gamma 90% CI | [0.0426, 0.3825] |
| sigma_beta mean | 0.2129 |
| Rhat sigma_gamma | 1.0818 |
| ESS sigma_gamma | 67 |
| Runtime | 157.5 min |

### Plots (phi-free v3)

> Plots will be updated when v3 fit completes.

#### 1. Parameter posteriors
Left: sigma_beta (baseline linear trend), centre: sigma_gamma (post-LLM shift scale) —
both compared to the phi=10 reference. Right: phi posterior (solid purple) vs
lognormal(log(100), 1.0) prior (dashed). Phi concentrates far above its prior median (100),
suggesting the data favour a near-Multinomial likelihood.

![Sigma and phi posteriors](../data/output/phi_free/kf_plot_sigma_posteriors.png)

#### 2. Methodological diversity by L2 group
Posterior median (line) with 50% and 90% credible intervals (ribbon) for inverse Simpson
diversity within each of the 48 L2 groups. Grey dots = observed annual diversity.
Dashed red line = 2023 LLM adoption boundary.

![Diversity by L2 group](../data/output/phi_free/kf_plot_diversity_by_group.png)

#### 3. Differential post-2023 slopes (gamma_method)
Methods where the 90% posterior CI for gamma excludes zero — i.e., credible post-LLM
slope change. Red = gaining share, blue = losing share. With ESS=67, almost no methods
pass this threshold; the near-empty plot is a convergence symptom, not a scientific finding.

![Gamma dotplot](../data/output/phi_free/kf_plot_gamma_dotplot.png)

#### 4. Share trajectories: top 15 methods by |gamma|
Model-fitted share trajectories for the 15 methods with the largest absolute posterior mean
gamma. Shows whether the post-2023 trend change is visible in the fitted shares.

![Top gamma trajectories](../data/output/phi_free/kf_plot_top_gamma_trajectories.png)

#### 5. Raw observed counts: top 15 methods
Observed paper counts (grey dots) with loess smoother (orange). Pure data — no model.
Useful sanity check: does the raw signal match what the model recovers?

![Raw counts](../data/output/phi_free/kf_plot_raw_counts.png)

## Summary comparison

| Model | phi | sigma_gamma mean | sigma_gamma 90% CI | Converged? | Notes |
|---|---|---|---|---|---|
| Fixed phi = 10 | 10 (fixed) | 0.0563 | [0.0018, 0.1671] | YES | Primary model; phi is a Dirac-delta prior |
| Fixed phi = 50 | 50 (fixed) | ~0.095 | — | YES | Sensitivity check; not Bayesian |
| Phi free (v2) | 599.6 (estimated) | 0.25 | [0.0426, 0.3825] | PARTIAL (ESS=67) | phi ~ lognormal, direct parameterisation |
| Phi free (v3) | — | — | — | PENDING | log_phi parameterisation; genuinely Bayesian |
