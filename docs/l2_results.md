# L2 Results: L1 to L2 Sensitivity Analysis

## The Model

This is a sensitivity check running the same model at one taxonomic level coarser. Rather than watching technique shares within L2 sub-disciplines, we watch L2 sub-discipline shares within broad L1 methodological families. The generative model is:

```
y[g, t]          ~ Dirichlet-Multinomial(α[g, t])
α[g, t]           = softmax(η[g, t]) × κ

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

κ = 10            [fixed concentration]
```

Here g indexes L1 families (e.g., Remote Sensing, Geophysical Methods) and k indexes L2 sub-disciplines within each family. Everything else is identical to the L3 analysis: same Dirichlet-Multinomial likelihood, same two-slope linear predictor, same non-centred parameterisation, same soft sum-to-zero constraint, same priors. See [docs/l3_results.md](l3_results.md) for a full line-by-line deconstruction of the model.

The inline Stan code in `R/03_l2_analysis.R` is structurally identical to `stan/diversity_model.stan`. Any changes to the model specification should be applied to both.

**σ_γ is again the primary estimand**, now measuring the global scale of post-2023 sub-discipline-level variation within L1 families. Comparing it to σ_γ from the L3 analysis is the core sensitivity check: qualitative agreement (both credibly above zero, similar ratio to σ_β) supports robustness of the main finding across taxonomic levels.

## Diagnostics

| Quantity | Value |
|---|---|
| Divergent transitions | {{DIVERGENCES_L2}} |
| sigma_beta Rhat | {{RHAT_SIGMA_BETA_L2}} |
| sigma_gamma Rhat | {{RHAT_SIGMA_GAMMA_L2}} |
| sigma_beta ESS | {{ESS_SIGMA_BETA_L2}} |
| sigma_gamma ESS | {{ESS_SIGMA_GAMMA_L2}} |
| Runtime (minutes) | {{RUNTIME_MIN_L2}} |

Rhat < 1.01 and ESS > 400 are the thresholds for acceptable convergence. Zero divergences is required.

## Key Results

| Parameter | Posterior mean | 95% CI |
|---|---|---|
| sigma_beta | {{SIGMA_BETA_MEAN_L2}} | {{SIGMA_BETA_CI_L2}} |
| sigma_gamma | {{SIGMA_GAMMA_MEAN_L2}} | {{SIGMA_GAMMA_CI_L2}} |
| ratio gamma/beta | {{RATIO_L2}} | — |

Interpretation: the post-LLM shift scale at L2 (sigma_gamma = {{SIGMA_GAMMA_MEAN_L2}}, 95% CI {{SIGMA_GAMMA_CI_L2}}) is {{RATIO_L2}} times the baseline trend scale (sigma_beta = {{SIGMA_BETA_MEAN_L2}}, 95% CI {{SIGMA_BETA_CI_L2}}). Compare these values with the L3 analysis in docs/l3_results.md to assess whether the post-LLM signal is consistent across taxonomic levels. Qualitative agreement (both sigma_gamma credibly above zero, similar ratio) supports robustness of the main finding.

## Plots

![Diversity by group](../data/output/l2/l2_plot_diversity_by_group.png)
Inverse Simpson index (effective number of L2 sub-disciplines) within each L1 family over 2010-2025. Ribbon = 50% and 90% posterior credible intervals. Dashed line = 2023 LLM adoption boundary.

![Sigma posteriors](../data/output/l2/l2_plot_sigma_posteriors.png)
Posterior densities of sigma_beta (baseline trend scale, blue) and sigma_gamma (post-LLM shift scale, red) at the L1-to-L2 level.

![Gamma dotplot](../data/output/l2/l2_plot_gamma_dotplot.png)
Posterior mean and 90% CI for gamma_method for each L2 sub-discipline whose CI excludes zero. Red = gaining share post-2023, blue = losing share.

![Raw counts](../data/output/l2/l2_plot_raw_counts.png)
Observed paper counts for the same top 10 sub-disciplines. Loess smoother overlaid as a sanity check.
