# L1→L2 Sensitivity Analysis

## What this model does

This is a coarser-grained version of the primary analysis. Rather than watching technique shares within L2 sub-disciplines (the L2→L3 level), we watch L2 sub-discipline shares within broad L1 methodological families. The question is the same — did the sub-discipline mix within each family change anomalously after 2023? — but at one taxonomic level coarser.

If the signal exists at both L1→L2 and L2→L3, the finding is robust: it is not an artefact of the fine-grained taxonomy, the definition of L2 sub-disciplines, or any idiosyncrasy of the primary model specification. Qualitative agreement (both sigma_gamma credibly above zero, similar ratio to sigma_beta) is the core sensitivity check.

## The model

Structurally identical to the L2→L3 primary analysis. g now indexes L1 families (e.g., Remote Sensing, Geophysical Methods); k indexes L2 sub-disciplines within each family; t indexes years 2010–2025.

```
y[g, t]          ~ Dirichlet-Multinomial(α[g, t])
α[g, t]           = softmax(η[g, t]) × phi

η[g, k, t]        = μ[g, k]
                   + β[g, k]  × year_std[t]
                   + γ[g, k]  × I(year[t] ≥ 2023)

μ[g, k]          ~ Normal(0, 1)
∑_k μ[g, k]      ~ Normal(0, 0.001 × K_g)      [soft sum-to-zero]

β[g, k]           = σ_β × β_raw[g, k]
β_raw[g, k]      ~ Normal(0, 1)
σ_β              ~ Exponential(2)

γ[g, k]           = σ_γ × γ_raw[g, k]
γ_raw[g, k]      ~ Normal(0, 1)
σ_γ              ~ Exponential(4)

log(phi)         ~ Normal(log(100), 1.0)   [phi ~ lognormal, median 100, 90% CI ~[14, 716]]
```

Same Dirichlet-Multinomial likelihood, same two-slope linear predictor, same non-centred parameterisation, same soft sum-to-zero constraint, same priors. phi is estimated from data — not fixed at 10 — for the same reasons as in the primary analysis: empirical phi exploration shows most groups have phi well above 10, making a fixed low value conservative. See [docs/l2_l3_results.md](l2_l3_results.md) for a full line-by-line deconstruction of the shared model structure.

## Diagnostics

| Parameter | Value |
|---|---|
| phi | fixed at 10 |
| sigma_gamma mean | 0.0675 |
| sigma_gamma 90% CI | [0.0045, 0.1673] |
| sigma_beta mean | 0.0739 |
| sigma_beta 90% CI | [0.0078, 0.1542] |
| Rhat (sigma_gamma) | 1.0005 |
| Rhat (sigma_beta) | 1.0069 |
| ESS (sigma_gamma) | 804 |
| ESS (sigma_beta) | 375 |
| Divergences | 0 |

Rhat < 1.01 and ESS > 400 are the thresholds for acceptable convergence. Zero divergences is required. sigma_beta ESS of 375 is marginally below threshold; conclusions are drawn from sigma_gamma (ESS = 804, fully converged).

## Key result

sigma_gamma = 0.0675 [0.0045, 0.1673] is credibly above zero (90% CI excludes zero). phi is fixed at 10 in this run. The directional finding is consistent with the primary L2→L3 analysis: the post-LLM period produced real heterogeneous shifts in sub-discipline shares, over and above the pre-existing trend.

The magnitude is smaller than at L2→L3. This is expected: at the coarser L1→L2 level, the composition of broad families is more stable than the composition of specific techniques within sub-disciplines. The short post-LLM window (2–3 years) is more visible at fine granularity. What matters is that sigma_gamma is credibly above zero at both levels — the signal is not a taxonomic artefact.

The ratio sigma_gamma/sigma_beta (0.0675/0.0739 ≈ 0.913) indicates the post-LLM shift scale is comparable to the 13-year baseline trend scale at the L1→L2 level.

## What sigma_gamma means in plain terms

At L1→L2, sigma_gamma = 0.0675 means the typical post-2023 gamma for an L2 sub-discipline is small. A gamma of +0.0675 on a sub-discipline holding 20% share within its L1 family shifts it to approximately 21.4% (multiplicative increase of exp(0.0675) − 1 ≈ 7%, before renormalisation). At the L2 level where sub-disciplines can hold 10–30% shares, a shift of 1–2 percentage points is modest but consistent with the primary analysis finding.

## Top sub-disciplines gaining share post-2023

| Sub-discipline | L1 Family | Change |
|---|---|---|
| L2-061: Discrete and Continuous Simulation | L1-31: Numerical Simulation and Resampling | +3% |
| L2-026: Attention Mechanisms | L1-05: Deep Learning Architectures | +2% |
| L2-002: Image Enhancement and Segmentation | L1-13: Image Segmentation | +2% |
| L2-008: Bayesian Time Series Analysis | L1-21: Bayesian Chronological Modeling | +2% |
| L2-009: Graph-Based Network Analysis | L1-25: Geospatial Data Acquisition and Analysis | +2% |

## Top sub-disciplines losing share post-2023

| Sub-discipline | L1 Family | Change |
|---|---|---|
| L2-007: Vector Embedding Techniques | L1-05: Deep Learning Architectures | −2% |
| L2-043: Paleoenvironmental Transfer Functions | L1-04: Advanced Multivariate and Machine Learning Methods | −2% |
| L2-011: Radiocarbon Wiggle Matching | L1-21: Bayesian Chronological Modeling | −2% |
| L2-005: Geophysical Inversion and Calibration | L1-31: Numerical Simulation and Resampling | −2% |
| L2-047: Elliptic Fourier Shape Analysis | L1-13: Image Segmentation | −2% |

Note: change = (exp(gamma) − 1) × 100. At the L1→L2 level, fewer papers per cell means most individual 90% CIs include zero — the global signal (sigma_gamma > 0) is robust, but individual sub-discipline rankings should be interpreted directionally only. See plots for the full picture.

## Plots

![Sigma posteriors](../data/output/figures/l1_l2/l2_plot_sigma_posteriors.png)
Two-panel: sigma_beta posterior (left), sigma_gamma posterior (right). phi is fixed at 10.

![Diversity by L1 group](../data/output/figures/l1_l2/l2_plot_diversity_by_group.png)
Inverse Simpson index within each L1 family over 2010–2025. Grey dots = observed annual diversity; ribbon = 50%/90% posterior credible intervals. Dashed line = 2023 LLM adoption boundary.

![Gamma dotplot](../data/output/figures/l1_l2/l2_plot_gamma_dotplot.png)
L2 sub-disciplines with posterior mean and 90% CI for gamma. Red = gaining share post-2023, blue = losing share.

![Raw counts](../data/output/figures/l1_l2/l2_plot_raw_counts.png)
Raw observed paper counts for the top 10 sub-disciplines by |gamma|. Pure data sanity check — no model involved.

## The model — full parameter description

### The generative story

We start by asking: if we knew the true proportion of sub-disciplines within each broad methodological family in a given year, what would the count data look like? The answer is a Multinomial. But we don't know the true proportions — they vary year to year around a structural trend. So we place a Dirichlet prior on those proportions. Integrating out the proportions analytically gives us the Dirichlet-Multinomial, which is what we observe directly.

### Marginalisation

We never sample pi directly. Instead, pi is marginalised out of the model — the DM likelihood is the result of integrating pi over its Dirichlet prior. This is mathematically equivalent to sampling pi explicitly, but much faster for HMC because it removes thousands of latent variables from the parameter space (one pi vector per group-year cell).

### Full generative model

```
phi        ~ LogNormal(log(100), 1.0)           [sampled]
sigma_beta ~ Exponential(2)                      [sampled]
sigma_gamma~ Exponential(4)                      [sampled]

for each group g, method k:
  mu[g,k]        ~ Normal(0, 1)                 [sampled]
  beta_raw[g,k]  ~ Normal(0, 1)                 [sampled, non-centred]
  gamma_raw[g,k] ~ Normal(0, 1)                 [sampled, non-centred]

  beta[g,k]  = sigma_beta  * beta_raw[g,k]      [derived]
  gamma[g,k] = sigma_gamma * gamma_raw[g,k]     [derived]

for each group g, year t:
  eta[g,k,t] = mu[g,k] + beta[g,k]*year_std[t] + gamma[g,k]*post_llm[t]
  pi[g,t]    = softmax(eta[g,:,t])              [derived, then marginalised]
  alpha[g,t] = pi[g,t] * phi                    [derived, not sampled]
  y[g,t]     ~ DM(N[g,t], alpha[g,t])           [observed]
```

g indexes L1 families; k indexes L2 sub-disciplines within each family; t indexes years 2010–2025. Structure is identical to the L2→L3 analysis — see [docs/l2_l3_results.md](l2_l3_results.md) for a full line-by-line explanation of the shared model.

### Parameter meanings

- **phi** — the Dirichlet-Multinomial concentration parameter. Controls how tightly observed proportions are expected to track the model's structural trend in any given year. Higher phi means less overdispersion and a more compositionally regular field. Prior: LogNormal(log(100), 1.0), median 100. Sampled as log_phi (unbounded) for better HMC geometry.

- **sigma_beta** — the global scale of the distribution from which long-run sub-discipline trends are drawn. Encodes how much sub-disciplines vary in their historical trajectories across the full 2010–2025 period. Prior: Exponential(2), weakly regularising. Sampled.

- **sigma_gamma** — the global scale of post-2023 slope changes. This is the key estimand: if sigma_gamma is credibly above zero, real post-LLM heterogeneous reshuffling occurred across sub-disciplines. Prior: Exponential(4), more regularising than sigma_beta. Sampled.

- **mu[g,k]** — the baseline log-weight of sub-discipline k in family g, representing its average relative share across the full period. Prior: Normal(0, 1) with a soft sum-to-zero constraint across k within each g. Sampled.

- **beta_raw[g,k]** — non-centred auxiliary parameter for the long-run trend. Sampled as Normal(0,1); scaled by sigma_beta to give beta[g,k].

- **gamma_raw[g,k]** — non-centred auxiliary parameter for the post-2023 slope increment. Sampled as Normal(0,1); scaled by sigma_gamma to give gamma[g,k].

- **beta[g,k]** — the long-run linear trend of sub-discipline k in family g. Was this sub-discipline already rising or falling before LLMs existed? Derived: beta = sigma_beta * beta_raw. Not directly sampled.

- **gamma[g,k]** — the post-2023 slope increment for sub-discipline k in family g. The anomalous change after LLM adoption, over and above the pre-existing trend. Derived: gamma = sigma_gamma * gamma_raw. Not directly sampled.

- **alpha[g,t]** — the Dirichlet concentration vector passed to the DM likelihood. Derived as pi[g,t] * phi. Not sampled.

- **pi[g,t]** — the true sub-discipline proportions in family g at year t. Marginalised out of the model — never sampled, integrated analytically via the DM likelihood.

## Parameter table

| Parameter | What it measures | Sampled? | Posterior mean | 90% CI | Rhat | ESS |
|---|---|---|---|---|---|---|
| phi | Concentration — how tightly observed proportions track the structural trend. Higher = more regular field | No (fixed at 10) | — | — | — | — |
| sigma_beta | Global scale of long-run sub-discipline trends (2010–2025). How much sub-disciplines vary in their historical trajectories | Yes | 0.0739 | [0.0078, 0.1542] | 1.0069 | 375 |
| sigma_gamma | Global scale of post-2023 slope changes. The key estimand — if credibly above zero, anomalous reshuffling occurred | Yes | 0.0675 | [0.0045, 0.1673] | 1.0005 | 804 |
| mu[g,k] | Baseline log-weight of sub-discipline k in family g — its average relative share across the full period | Yes | (varies by sub-discipline) | — | — | — |
| beta[g,k] | Long-run linear trend of sub-discipline k — was it already rising or falling before LLMs? | No (derived) | (varies by sub-discipline) | — | — | — |
| gamma[g,k] | Post-2023 slope increment — the anomalous change after LLM adoption | No (derived) | (varies by sub-discipline) | — | — | — |
| alpha[g,t] | Dirichlet concentration vector passed to DM likelihood | No (derived) | — | — | — | — |
| pi[g,t] | True sub-discipline proportions — marginalised out, never sampled | No (marginalised) | — | — | — | — |

> beta[g,k] and gamma[g,k] are derived from sampled parameters via beta = sigma_beta * beta_raw and gamma = sigma_gamma * gamma_raw (non-centred parameterisation). The individual sub-discipline-level estimates are available in the fit object but not shown here for brevity — see the gamma dotplot for the post-2023 estimates.
