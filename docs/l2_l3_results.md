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

g indexes L2 sub-disciplines; k indexes L3 techniques within each sub-discipline; t indexes years 2010–2025.

**Why phi is estimated, not fixed.** The empirical phi exploration (`R/00b_phi_exploration.R`) estimates the Dirichlet-Multinomial concentration parameter from the data before any modelling, using a method-of-moments estimator applied across years within each L2 group. Most groups have empirical phi well above 10 — many above 100 — meaning the observed proportions track the structural trend closely year to year. Fixing phi=10 was therefore conservative: it attributed too much observed variation to within-year noise, leaving less for the structural β and γ parameters to explain. The principled Bayesian alternative is a weakly informative lognormal prior that lets the data speak. The posterior concentrates at phi ≈ 604, confirming that the data favour a near-Multinomial likelihood.

**phi is sampled as log_phi (unbounded) for better HMC geometry.** `log_phi ~ Normal(log(100), 1.0)` is equivalent to `phi ~ lognormal(log(100), 1.0)`. The `phi = exp(log_phi)` transformation is applied in the `transformed parameters` block.

## Diagnostics

| Parameter | Value |
|---|---|
| phi posterior mean | 604 |
| phi 90% CI | [280, 1210] |
| sigma_gamma mean | 0.250 |
| sigma_gamma 90% CI | [0.125, 0.365] |
| sigma_beta mean | 0.215 |
| Rhat (all params) | < 1.002 |
| ESS (sigma_gamma) | 1824 |
| Divergences | 0 |

Rhat < 1.01 and ESS > 400 are the thresholds for acceptable convergence. Zero divergences is required.

## Key result

sigma_gamma = 0.250 [0.125, 0.365] is credibly above zero. phi ≈ 604 — the field is compositionally regular, meaning observed proportions track the structural trend closely year to year. The post-LLM reshuffling in 2–3 years is comparable in magnitude to 13 years of gradual evolution: sigma_gamma ≈ sigma_beta (0.250 vs 0.215).

## What sigma_gamma means in plain terms

sigma_gamma is the standard deviation of the distribution from which individual method gammas are drawn. In the non-centred parameterisation, `gamma_method[g,k] = sigma_gamma × gamma_raw[g,k]` where `gamma_raw ~ Normal(0, 1)`, so sigma_gamma controls how spread out the post-2023 slopes are across methods. A sigma_gamma of 0.250 means roughly 68% of methods have |gamma| < 0.250, and about 16% have gamma > 0.250 or gamma < −0.250.

What does gamma = +0.250 look like in practice? The gamma operates on the log-share scale inside softmax. A rough translation: a method holding 20% share of its sub-discipline would shift to approximately 25% (a multiplicative increase of exp(0.250) − 1 ≈ 28%, applied before renormalisation). In a field where specialised methods typically hold 5–15% shares, a shift of 4–5 percentage points is substantial — it can move a method from marginal to dominant within its niche.

## Top methods gaining share post-2023

| Method | Description | Change |
|---|---|---|
| L3-021: Spatial Pattern & Suitability Analysis | Generic GIS pattern analysis | +39% |
| L3-067: Visual Perception & Saliency | What stands out in images | +36% |
| L3-059: Generative Image Restoration | AI for damaged images | +34% |
| L3-066: Attention Mechanism Architectures | Transformers — LLMs suggest by default | +31% |
| L3-064: Multimodal Fusion and Alignment | Combining multiple data types | +26% |

## Top methods losing share post-2023

| Method | Description | Change |
|---|---|---|
| L3-178: Computational Analytical Methods | Specialised statistical techniques | −38% |
| L3-107: Deep Learning Architectural Patterns | Specialised (not generic) architectures | −20% |
| L3-044: Bootstrap and Jackknife Methods | Classical resampling — requires expertise | −20% |
| L3-149: Principal Component Analysis | Dimensionality reduction — bypassed for newer methods | −17% |

Note: change = (exp(gamma) − 1) × 100. Individual estimates are sensitive to phi — rankings may shift; directional pattern is consistent.

## Plots

![Sigma posteriors](../data/output/phi_free/kf_plot_sigma_posteriors.png)
Three-panel: sigma_beta (left), sigma_gamma (centre) each compared to the phi=10 reference, and phi posterior vs prior (right). Phi concentrating far above its prior median (100) confirms the data favour near-Multinomial behaviour.

![Diversity by group](../data/output/phi_free/kf_plot_diversity_by_group.png)
Inverse Simpson index (effective number of L3 techniques) within each L2 sub-discipline over 2010–2025. Ribbon = 50%/90% posterior credible intervals. Dashed line = 2023 LLM adoption boundary.

![Gamma dotplot](../data/output/phi_free/kf_plot_gamma_dotplot.png)
Posterior mean and 90% CI for gamma_method for each L3 technique. Red = gaining share post-2023, blue = losing share. Methods where the 90% CI excludes zero are credible evidence of a post-LLM slope change.

![Top trajectories](../data/output/phi_free/kf_plot_top_gamma_trajectories.png)
Fitted share trajectories for the top 15 L3 techniques by |gamma|. Each panel is one method; the y-axis is that method's estimated proportion of papers within its L2 sub-discipline. Ribbon = 80%/90% CI from 200 posterior draws.

![Raw counts](../data/output/phi_free/kf_plot_raw_counts.png)
Observed paper counts (grey dots) with loess smoother (orange). Pure data — no model. Sanity check that the raw signal matches what the model recovers.
