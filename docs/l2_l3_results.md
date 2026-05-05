# L2→L3 Primary Analysis

## What this model does

We watch the fine-grained technique mix within each L2 sub-discipline evolve year by year. The model asks whether any method changed its share anomalously after 2023, over and above its historical trend.

Think of each sub-discipline as a menu: from 2010 to 2022, some techniques were growing, others shrinking. The model fits a linear trend to that history for every method simultaneously. Then it asks — did 2023 and 2024 bring changes that cannot be explained by the pre-existing trend? If so, sigma_gamma captures the global scale of that reshuffling. A small sigma_gamma means post-2023 was business as usual. A large sigma_gamma means the method landscape moved — some techniques accelerating, others declining — in a way that the prior trend cannot account for.

Crucially, the model does not ask "did overall diversity increase or decrease?" It asks "did the mix of methods within sub-disciplines change heterogeneously?" A large sigma_gamma is consistent with convergence (many methods declining, a few rising) or fragmentation (many methods rising from obscurity) — the direction is determined by the individual gamma estimates, not sigma_gamma itself.

## The model

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

g indexes L2 sub-disciplines; k indexes L3 techniques within each sub-discipline; t indexes years 2010–2026.

**Why phi is estimated, not fixed.** The empirical phi exploration (`R/00b_phi_exploration.R`) estimates the Dirichlet-Multinomial concentration parameter from the data before any modelling, using a method-of-moments estimator applied across years within each L2 group. Most groups have empirical phi well above 10 — many above 100 — meaning the observed proportions track the structural trend closely year to year. Fixing phi=10 was therefore conservative: it attributed too much observed variation to within-year noise, leaving less for the structural β and γ parameters to explain. The principled Bayesian alternative is a weakly informative lognormal prior that lets the data speak. The posterior concentrates at phi ≈ 604, confirming that the data favour a near-Multinomial likelihood.

**phi is sampled as log_phi (unbounded) for better HMC geometry.** `log_phi ~ Normal(log(100), 1.0)` is equivalent to `phi ~ lognormal(log(100), 1.0)`. The `phi = exp(log_phi)` transformation is applied in the `transformed parameters` block.

## Diagnostics

| Parameter | Value |
|---|---|
| phi posterior mean | 591 |
| phi 90% CI | [297, 1164] |
| sigma_gamma mean | 0.138 |
| sigma_gamma 90% CI | [0.021, 0.250] |
| sigma_beta mean | 0.204 |
| Rhat (all params) | < 1.003 |
| ESS (sigma_gamma) | 862 |
| Divergences | 0 |

Rhat < 1.01 and ESS > 400 are the thresholds for acceptable convergence. Zero divergences is required.

## Key result

sigma_gamma = 0.138 [0.021, 0.250] is above zero but with wider uncertainty than earlier estimates — the lower bound of the 90% CI is close to zero, indicating weaker evidence for post-LLM reshuffling than previously found. phi ≈ 591 — the field remains compositionally regular. The post-LLM reshuffling is now estimated to be smaller in magnitude than the long-run baseline trend: sigma_gamma < sigma_beta (0.138 vs 0.204). No individual methods clear the 90% CI threshold for a credible post-LLM slope change.

## What sigma_gamma means in plain terms

sigma_gamma is the standard deviation of the distribution from which individual method gammas are drawn. In the non-centred parameterisation, `gamma_method[g,k] = sigma_gamma × gamma_raw[g,k]` where `gamma_raw ~ Normal(0, 1)`, so sigma_gamma controls how spread out the post-2023 slopes are across methods. A sigma_gamma of 0.250 means roughly 68% of methods have |gamma| < 0.250, and about 16% have gamma > 0.250 or gamma < −0.250.

What does gamma = +0.250 look like in practice? The gamma operates on the log-share scale inside softmax. A rough translation: a method holding 20% share of its sub-discipline would shift to approximately 25% (a multiplicative increase of exp(0.250) − 1 ≈ 28%, applied before renormalisation). In a field where specialised methods typically hold 5–15% shares, a shift of 4–5 percentage points is substantial — it can move a method from marginal to dominant within its niche.

## Top methods gaining share post-2023

No methods have a 90% CI for gamma that fully excludes zero. The estimates below are the top 5 by posterior mean but all carry wide uncertainty intervals that cross zero.

| Method | mean gamma | 90% CI |
|---|---|---|
| L3-024: Bayesian Panel Data Methods | +0.146 | [−0.064, +0.501] |
| L3-009: Real-Time Object Detection | +0.131 | [−0.067, +0.440] |
| L3-101: Information-Theoretic Entropy Measures | +0.130 | [−0.072, +0.451] |
| L3-006: Partial Least Squares Variants | +0.125 | [−0.053, +0.396] |
| L3-123: Generalized Linear Modeling | +0.125 | [−0.060, +0.404] |

## Top methods losing share post-2023

| Method | mean gamma | 90% CI |
|---|---|---|
| L3-134: Logistic Regression Variants | −0.131 | [−0.417, +0.055] |
| L3-103: Ecological Diversity Metrics | −0.117 | [−0.404, +0.071] |
| L3-017: Kernel Methods and Matrix Factorization | −0.110 | [−0.402, +0.086] |
| L3-109: Categorical Data Analysis | −0.106 | [−0.376, +0.073] |
| L3-118: Hypothesis Testing Procedures | −0.103 | [−0.357, +0.077] |

Note: change = (exp(gamma) − 1) × 100. No individual estimates are credible at the 90% level — all CIs cross zero.

## Plots

![Sigma posteriors](../data/output/phi_free/kf_plot_sigma_posteriors.png)
Three-panel: sigma_beta posterior (left), sigma_gamma posterior (centre), phi posterior vs prior (right). Phi concentrating far above its prior median (100) confirms the data favour near-Multinomial behaviour.

![Diversity by group](../data/output/phi_free/kf_plot_diversity_by_group.png)
Inverse Simpson index (effective number of L3 techniques) within each L2 sub-discipline over 2010–2026. Ribbon = 50%/90% posterior credible intervals. Dashed line = 2023 LLM adoption boundary.

![Gamma dotplot](../data/output/phi_free/kf_plot_gamma_dotplot.png)
Posterior mean and 90% CI for gamma_method for each L3 technique. Red = gaining share post-2023, blue = losing share. Methods where the 90% CI excludes zero are credible evidence of a post-LLM slope change.

![Top trajectories](../data/output/phi_free/kf_plot_top_gamma_trajectories.png)
Fitted share trajectories for the top 15 L3 techniques by |gamma|. Each panel is one method; the y-axis is that method's estimated proportion of papers within its L2 sub-discipline. Ribbon = 80%/90% CI from 200 posterior draws.

![Raw counts](../data/output/phi_free/kf_plot_raw_counts.png)
Observed paper counts (grey dots) with loess smoother (orange). Pure data — no model. Sanity check that the raw signal matches what the model recovers.

## The model — full parameter description

### The generative story

We start by asking: if we knew the true proportion of papers using each method in a given year and sub-discipline, what would the count data look like? The answer is a Multinomial. But we don't know the true proportions — they vary year to year around a structural trend. So we place a Dirichlet prior on those proportions. Integrating out the proportions analytically gives us the Dirichlet-Multinomial, which is what we observe directly.

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

g indexes L2 sub-disciplines; k indexes L3 techniques within each sub-discipline; t indexes years 2010–2026.

### Parameter meanings

- **phi** — the Dirichlet-Multinomial concentration parameter. Controls how tightly observed proportions are expected to track the model's structural trend in any given year. Higher phi means less overdispersion and a more compositionally regular field. Prior: LogNormal(log(100), 1.0), median 100. Sampled as log_phi (unbounded) for better HMC geometry.

- **sigma_beta** — the global scale of the distribution from which long-run method trends are drawn. Encodes how much methods vary in their historical trajectories across the full 2010–2026 period. Prior: Exponential(2), weakly regularising. Sampled.

- **sigma_gamma** — the global scale of post-2023 slope changes. This is the key estimand: if sigma_gamma is credibly above zero, real post-LLM heterogeneous reshuffling occurred across methods. Prior: Exponential(4), more regularising than sigma_beta because we expect the post-LLM change (2–3 years) to be smaller than the cumulative 13-year trend. Sampled.

- **mu[g,k]** — the baseline log-weight of method k in group g, representing its average relative share across the full period. Prior: Normal(0, 1) with a soft sum-to-zero constraint across k within each g. Sampled.

- **beta_raw[g,k]** — non-centred auxiliary parameter for the long-run trend. Sampled as Normal(0,1); scaled by sigma_beta to give beta[g,k]. The non-centred form improves HMC mixing when sigma is small.

- **gamma_raw[g,k]** — non-centred auxiliary parameter for the post-2023 slope increment. Sampled as Normal(0,1); scaled by sigma_gamma to give gamma[g,k].

- **beta[g,k]** — the long-run linear trend of method k in group g. Was this method already rising or falling before LLMs existed? Derived: beta = sigma_beta * beta_raw. Not directly sampled.

- **gamma[g,k]** — the post-2023 slope increment for method k in group g. The anomalous change after LLM adoption, over and above the pre-existing trend. Derived: gamma = sigma_gamma * gamma_raw. Not directly sampled.

- **alpha[g,t]** — the Dirichlet concentration vector passed to the DM likelihood. Derived as pi[g,t] * phi. Not sampled.

- **pi[g,t]** — the true method proportions in group g at year t. Marginalised out of the model — never sampled, integrated analytically via the DM likelihood.

## Parameter table

| Parameter | What it measures | Sampled? | Posterior mean | 90% CI | Rhat | ESS |
|---|---|---|---|---|---|---|
| phi | Concentration — how tightly observed proportions track the structural trend. Higher = more regular field | Yes | 591 | [297, 1164] | 1.0000 | 5293 |
| sigma_beta | Global scale of long-run method trends (2010–2026). How much methods vary in their historical trajectories | Yes | 0.204 | [0.157, 0.251] | 1.0016 | 2154 |
| sigma_gamma | Global scale of post-2023 slope changes. The key estimand — if credibly above zero, anomalous reshuffling occurred | Yes | 0.138 | [0.021, 0.250] | 1.0022 | 862 |
| mu[g,k] | Baseline log-weight of method k in group g — its average relative share across the full period | Yes | (varies by method) | — | — | — |
| beta[g,k] | Long-run linear trend of method k — was it already rising or falling before LLMs? | No (derived) | (varies by method) | — | — | — |
| gamma[g,k] | Post-2023 slope increment — the anomalous change after LLM adoption | No (derived) | (varies by method) | — | — | — |
| alpha[g,t] | Dirichlet concentration vector passed to DM likelihood | No (derived) | — | — | — | — |
| pi[g,t] | True method proportions — marginalised out, never sampled | No (marginalised) | — | — | — | — |

> beta[g,k] and gamma[g,k] are derived from sampled parameters via beta = sigma_beta * beta_raw and gamma = sigma_gamma * gamma_raw (non-centred parameterisation). The individual method-level estimates are available in the fit object but not shown here for brevity — see the gamma dotplot for the post-2023 estimates.
