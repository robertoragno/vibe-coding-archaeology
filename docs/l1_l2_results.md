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
| phi posterior mean | 695.6 |
| phi 90% CI | [306.1, 1434.2] |
| sigma_gamma mean | 0.121 |
| sigma_gamma 90% CI | [0.018, 0.225] |
| sigma_beta mean | 0.206 |
| Rhat (all params) | < 1.001 |
| ESS (sigma_gamma) | 1230 |
| Divergences | 0 |

Rhat < 1.01 and ESS > 400 are the thresholds for acceptable convergence. Zero divergences is required.

## Key result

sigma_gamma = 0.121 [0.018, 0.225] is credibly above zero. phi ≈ 696, again far above the prior median of 100. The directional finding is consistent with the primary L2→L3 analysis: the post-LLM period produced real heterogeneous shifts in sub-discipline shares, over and above the pre-existing trend.

The magnitude is smaller than at L2→L3 (0.121 vs 0.250). This is expected: at the coarser L1→L2 level, the composition of broad families is more stable than the composition of specific techniques within sub-disciplines. The short post-LLM window (2–3 years) is more visible at fine granularity. What matters is that sigma_gamma is credibly above zero at both levels — the signal is not a taxonomic artefact.

The ratio sigma_gamma/sigma_beta (0.121/0.206 ≈ 0.588) is similar to the L2→L3 ratio (0.250/0.215 ≈ 1.16 at phi-free). The post-LLM shift scale is a substantial fraction of the 13-year baseline trend scale, at both taxonomic levels.

## What sigma_gamma means in plain terms

At L1→L2, sigma_gamma = 0.121 means the typical post-2023 gamma for an L2 sub-discipline is moderate. A gamma of +0.121 on a sub-discipline holding 20% share within its L1 family shifts it to approximately 22.5% (multiplicative increase of exp(0.121) − 1 ≈ 13%, before renormalisation). At the L2 level where sub-disciplines can hold 10–30% shares, a shift of 2–3 percentage points is modest but consistent with the primary analysis finding.

## Top sub-disciplines gaining share post-2023

| Sub-discipline | L1 Family | Change |
|---|---|---|
| L2-020: Core Digital Image Processing | L1-06: Digital Image Analysis | +13% |
| L2-038: Ensemble and Tree-Based Methods | L1-11: Probabilistic and Bayesian Methods | +10% |
| L2-014: Spatial Statistical Modeling | L1-04: Spatial Analysis Methods | +8% |
| L2-003: Advanced Analytical & Modeling Methods | L1-01: Spatial and Statistical Analysis | +8% |
| L2-045: Modern NLP Techniques | L1-13: Natural Language Processing | +7% |

## Top sub-disciplines losing share post-2023

| Sub-discipline | L1 Family | Change |
|---|---|---|
| L2-021: Remote Sensing & Photogrammetry | L1-06: Digital Image Analysis | −13% |
| L2-037: Bayesian and Stochastic Methods | L1-11: Probabilistic and Bayesian Methods | −12% |
| L2-044: Text Analysis & Mining | L1-13: Natural Language Processing | −6% |
| L2-016: Geospatial Modeling & Analysis | L1-04: Spatial Analysis Methods | −6% |

Note: change = (exp(gamma) − 1) × 100. At the L1→L2 level, fewer papers per cell means most individual 90% CIs include zero — the global signal (sigma_gamma > 0) is robust, but individual sub-discipline rankings should be interpreted directionally only. See plots for the full picture.

## Plots

![Sigma posteriors](../data/output/l2/phi_free/l2_kf_plot_sigma_posteriors.png)
Three-panel: sigma_beta (left), sigma_gamma (centre) each compared to the phi=10 reference, and phi posterior vs prior (right). Phi concentrating far above 100 confirms near-Multinomial behaviour at this taxonomic level too.

![Diversity by L1 group](../data/output/l2/phi_free/l2_kf_plot_diversity_by_group.png)
Inverse Simpson index within each L1 family over 2010–2025 under the phi-free model. Grey dots = observed annual diversity; ribbon = 50%/90% posterior credible intervals. Dashed line = 2023 LLM adoption boundary.

![Gamma dotplot](../data/output/l2/phi_free/l2_kf_plot_gamma_dotplot.png)
L2 sub-disciplines with posterior mean and 90% CI for gamma. Red = gaining share post-2023, blue = losing share.

![Top gamma trajectories](../data/output/l2/phi_free/l2_kf_plot_top_gamma_trajectories.png)
Fitted share trajectories for the top 15 L2 sub-disciplines by |gamma|. Ribbon = 80%/90% CI from 200 posterior draws.

![Raw counts](../data/output/l2/phi_free/l2_kf_plot_raw_counts.png)
Raw observed paper counts for the same top 15 sub-disciplines. Pure data sanity check — no model involved.
