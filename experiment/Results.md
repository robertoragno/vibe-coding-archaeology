# Step 3 Results — LLM Recommendation vs. Literature Trajectory

Scripts: `R/06–09*.R` | Run date: 2026-05-21

---

## At a glance

| Metric | Qwen3 | Gemma | Pre-2023 lit. | Post-2023 lit. |
|---|---|---|---|---|
| Total recommendations | 6,651 | 5,252 | 8,495 | 6,660 |
| Distinct L3 methods | 194 | 165 | — | — |
| Effective methods (inv. Simpson, overall) | 32 [30.5, 33.4] | 29 [28.0, 30.4] | 88 [85, 91] | 114 [111, 117] |
| Effective methods — novice | 21 [20, 23] | 21 [19, 22] | — | — |
| Effective methods — expert | 61 [57, 65] | 47 [44, 51] | — | — |
| b_pre (corpus prevalence, overall) | +0.658 [+0.50, +0.80] | +0.580 [+0.41, +0.75] | — | — |
| b_gamma (post-2023 trajectory, overall) | +0.083 [-1.47, +1.66] | +0.146 [-1.42, +1.72] | — | — |

Brackets are 90% credible intervals. b_pre is credibly positive in all 8 conditions (P = 1.000). b_gamma is indistinguishable from zero in all conditions (P = 0.518–0.594). Both LLMs are dramatically more concentrated than the literature, and neither tracks post-2023 shifts.

---

## Experiment data

| Metric | Qwen3 | Gemma |
|---|---|---|
| Total recommendations (consistent L3 mappings) | 6,651 | 5,252 |
| Distinct L3 methods covered | 194 | 165 |
| L3 methods with >= 1 rec. | 190 / 242 (78%) | 164 / 242 (68%) |
| L3 mapping consistency rate | 96.2% | 96.5% |

| Profile | Qwen3 total | Qwen3 distinct L3 | Gemma total | Gemma distinct L3 |
|---|---|---|---|---|
| Novice | 2,398 | 128 | 1,716 | 78 |
| Intermediate | 2,127 | 138 | 1,671 | 111 |
| Expert | 2,126 | 165 | 1,865 | 150 |

Responses were classified directly against the v3 L3 taxonomy; no v2-to-v3 remapping was needed. Gemma produces fewer recommendations per response (~7.1 novice vs Qwen3's ~9.9) but preserves the same profile gradient: novice lists more methods per response, expert covers more distinct methods.

---

## Exploratory descriptive analysis

Scripts: `R/06_exploratory_graphs.R`, `R/06b_exploratory_gemma.R`

### Top recommended methods (L4 and L3)

<img src="../data/output/figures/exploratory/plot_top20_l4.png" width="600">

<img src="../data/output/figures/exploratory/plot_top20_l3.png" width="600">

The most-recommended methods tend to have *negative* gamma (declining share post-2023). Agent-Based Simulation (L3-220) and Network Analysis (L3-080) dominate for Qwen3. Gemma's landscape differs: Agent-Based Simulation drops from 1st to 6th place; GIS Modeling (L3-226) and ML Methods (L3-167) rise to the top. Neither model concentrates on methods that gained share post-2023.

### Top 10 L3 methods by model

| L3 method | Qwen3 | Gemma | Mean gamma |
|---|---|---|---|
| L3-220: Discrete and Agent-Based Simulation | 693 | 183 | -0.035 |
| L3-080: Network Analysis and Modeling | 672 | 504 | -0.083 |
| L3-167: Multivariate Stat. & ML Methods | 276 | 464 | +0.028 |
| L3-193: Natural Language Processing | 350 | 228 | -0.033 |
| L3-226: GIS Modeling | 245 | 447 | -0.033 |
| L3-222: Spatial Autocorrelation & Geostatistics | 214 | 141 | +0.038 |
| L3-136: Time Series Stationarity and Causality | 46 | 260 | +0.012 |
| L3-176: Imaging and Photogrammetric Analysis | 78 | 182 | +0.014 |
| L3-019: PCA Variants | 118 | 124 | -0.034 |
| L3-145: Temporal Event and Sequence Analysis | 122 | 50 | -0.010 |

No method reaches sig90 (90% CI for gamma excludes zero). The Spearman rank correlation between Qwen3 and Gemma L3 frequencies is rho = 0.595 — moderate agreement, substantial divergences in which methods dominate.

### L2-level comparison: LLMs vs. literature

<img src="../data/output/figures/exploratory/plot_l2_triple_bar.png" width="700">

<img src="../data/output/figures/exploratory_gemma/plot_l2_triple_bar_gemma.png" width="700">

Both models massively over-recommend a few sub-disciplines (Network Analysis, Agent-Based Modelling, Machine Learning) relative to their share in either period of the literature, and under-recommend empirical sub-disciplines (Archaeometry, Isotope Analysis, Chronological Modelling).

### Pre-existing trend vs. post-2023 excess

<img src="../data/output/figures/exploratory/plot_beta_gamma_scatter.png" width="700">

Neither beta (pre-existing trend) nor gamma (post-2023 excess) predicts which methods either LLM recommends. The most-recommended methods span the full range of both parameters.

### Concentration comparison

The Inverse Simpson index converts a frequency distribution into "effective number of methods" — the number of equally-frequent methods that would produce the same concentration. A distribution spread evenly across 100 methods scores 100; one dominated by a handful scores much lower.

| Distribution | Total recs | Eff. methods (Inv. Simpson) | Methods covering 50% of mass |
|---|---|---|---|
| Pre-2023 literature | 8,495 | 86 | 34 |
| Post-2023 literature | 6,660 | 111 | 41 |
| Qwen3 overall | 6,651 | 30 | 15 |
| Qwen3 — novice | 2,398 | 18 | 7 |
| Qwen3 — intermediate | 2,127 | 26 | 12 |
| Qwen3 — expert | 2,126 | 53 | 22 |
| Gemma overall | 5,252 | 27 | 10 |
| Gemma — novice | 1,716 | 17 | 6 |
| Gemma — intermediate | 1,671 | 24 | 9 |
| Gemma — expert | 1,865 | 40 | 15 |

<img src="../data/output/figures/comparison/plot_concentration_comparison.png" width="700">

Both LLMs produce recommendation distributions dramatically narrower than the literature, and the gap is largest for the novice profile. The published literature has been *diversifying* since 2010 (inv. Simpson rising from ~63 to ~105), and this trend continued uninterrupted through 2023–2026.

### Summary of exploratory findings

1. **Both LLMs are dramatically more concentrated than the literature.** 10–15 methods cover 50% of recommendations vs. 34–41 for the literature. The novice profile is the most concentrated, consistent with the hypothesis that unconstrained LLM advice is the most homogenising.
2. **The literature is diversifying, not converging.** No post-2023 downturn in diversity. The mechanism exists; the effect has not manifested.
3. **Both LLMs recommend popular, established methods** with negative or flat gamma. Neither tracks post-2023 shifts.
4. **The specific methods differ between models** (rho = 0.595), but the structural concentration pattern is identical.

---

## Single-predictor negative-binomial regression: n_rec ~ gamma

Scripts: `R/archive/06_step3_llm_comparison.R (archived, superseded by 08)`, `R/archive/06b_step3_llm_comparison_gemma.R (archived, superseded by 08)`

> **Note:** This regression conflates training-corpus prevalence with post-2023 trajectory. The [two-predictor model below](#two-predictor-nb2-regression-prevalence-vs-trajectory) separates them and resolves the apparent negative direction.

The model is a negative-binomial regression (NB2 parameterisation). The negative-binomial is a generalisation of the Poisson for count data that adds an overdispersion parameter (phi) to handle the fact that recommendation counts are more variable than a Poisson would predict — some methods get recommended far more often than others for reasons beyond their gamma alone (e.g. fame, training-corpus prominence). The NB2 form means the variance scales quadratically with the mean: Var = mu + mu²/phi.

For each L3 method, the model asks whether its post-2023 trajectory (gamma) predicts how often the LLM recommends it:

```
n_rec[i] ~ NegBin2( exp(alpha + beta * gamma_bar_i) , phi )
```

A positive beta would mean the LLM preferentially recommends methods that gained share post-2023. Priors: beta ~ Normal(0, 1), alpha ~ Normal(0, 2), phi ~ Exponential(1). Run separately for each model × profile (8 fits total, 4 chains × 1000 draws each). All fits converged (max Rhat ≤ 1.004, min n_eff ≥ 3288).

### Results

| Profile | Qwen3 beta | Qwen3 90% CI | Qwen3 P(>0) | Gemma beta | Gemma 90% CI | Gemma P(>0) |
|---|---|---|---|---|---|---|
| Overall | -0.861 | [-2.40, +0.68] | 0.178 | -0.426 | [-1.94, +1.13] | 0.323 |
| Novice | -0.729 | [-2.33, +0.88] | 0.220 | -0.179 | [-1.75, +1.39] | 0.429 |
| Intermediate | -0.585 | [-2.15, +0.97] | 0.261 | -0.359 | [-1.96, +1.25] | 0.365 |
| Expert | -0.285 | [-1.87, +1.30] | 0.386 | -0.344 | [-1.93, +1.27] | 0.360 |

All posteriors lean negative and all CIs cross zero. The LLM tends to recommend methods that *lost* share post-2023 — the opposite of mean-collapse. But this negative direction is a confound (see two-predictor section below).

<img src="../data/output/figures/step3/plot_beta_posterior_overall.png" width="520">

<img src="../data/output/figures/step3/plot_beta_posterior_by_profile.png" width="520">

### Interpretation

The negative beta does not mean the LLM tracks post-2023 declines. It reflects the fact that the most prevalent pre-2023 methods (which the LLM favours) happen to have slightly negative gamma (Spearman cor(log1p(n_pre), gamma) = -0.189). They were already large and stable, not post-2023 gainers. The two-predictor model separates prevalence from trajectory and resolves this.

The width of the posteriors reflects two structural limitations: (1) gamma is estimated with substantial noise — 0/242 methods have a 90% CI that excludes zero — so the predictor attenuates the coefficient toward zero; (2) Qwen3 and Gemma are proxies for the LLMs archaeologists actually use (primarily ChatGPT/GPT-4).

---

## Bayesian concentration posteriors

Script: `R/07_experiment_concentration.R`

The point-estimate inverse Simpson indices from the exploratory section are replaced with full posterior distributions via the conjugate Dirichlet update: Dir(1 + n_1, ..., 1 + n_K) over 242 methods, with inv_simpson = 1 / sum(p_k^2) computed on each draw.

**Why conjugate inference rather than Stan.** The Dirichlet distribution is the *conjugate prior* for multinomial count data. Conjugacy means that the posterior belongs to the same distributional family as the prior — adding counts to the prior parameters yields the exact posterior, no approximation needed. This is a closed-form solution: a direct formula, not an iterative algorithm. The hierarchical diversity model (Step 2) cannot use this shortcut because its structure — L2 groups, yearly time steps, trend parameters, hierarchical shrinkage — couples the parameters in ways that have no closed-form posterior. Stan's MCMC sampler is required there to explore the joint posterior numerically. Both approaches are fully Bayesian (prior + likelihood → posterior); the difference is computational, not philosophical. The conjugate approach is exact where MCMC is approximate, but it is only available when the model is simple enough to admit a formula. In practice, the Dirichlet draws here are generated via the gamma-distribution identity: K independent draws g_k ~ Gamma(alpha_k, 1), normalised to sum to one, produce a single Dirichlet(alpha) sample. This is a standard sampling technique equivalent to Stan's `dirichlet` distribution, just without the overhead of a Markov chain.

| Distribution | Median effective methods | 90% CI |
|---|---|---|
| Pre-2023 literature | 88.4 | [85.4, 91.4] |
| Post-2023 literature | 113.6 | [110.5, 116.9] |
| Qwen3 — overall | 32.0 | [30.5, 33.4] |
| Qwen3 — novice | 21.4 | [20.0, 22.9] |
| Qwen3 — intermediate | 30.9 | [28.6, 33.4] |
| Qwen3 — expert | 60.9 | [57.0, 64.9] |
| Gemma — overall | 29.2 | [28.0, 30.4] |
| Gemma — novice | 20.9 | [19.4, 22.4] |
| Gemma — intermediate | 29.8 | [27.6, 32.0] |
| Gemma — expert | 47.2 | [43.7, 50.6] |

<img src="../data/output/figures/concentration/plot_concentration_posteriors.png" width="700">

**Posterior contrasts:**
- **Qwen3 vs Gemma (overall):** Qwen3 credibly more diverse (median diff = +2.8, P = 0.992).
- **Qwen3 vs Gemma (novice):** Not credibly different (median = +0.5, P = 0.657). Both collapse to ~20 effective methods.
- **Literature vs LLMs:** Both LLMs credibly below literature (P = 1.000). Post-2023 literature: ~114 effective methods; most concentrated LLM profile (Gemma novice): ~21.

The profile gradient (novice < intermediate < expert) survives with full posterior uncertainty. The literature's own diversification (88 → 114) is credibly nonzero.

**Note on within-response clustering.** The conjugate model treats each individual method recommendation as an independent multinomial draw. In practice, each LLM response produces ~7–10 recommendations that may be correlated (252 responses per profile), so the effective sample size is closer to 252 than ~2,000. A response-level bootstrap confirms that credible intervals would widen by approximately 1.5–2.5× with proper clustering adjustment. This does not affect any substantive conclusion: the LLM–literature gap (21–32 vs 88–114 effective methods) dwarfs the interval widening, and all posterior contrasts remain credible under the wider intervals. The same caveat applies symmetrically to the literature counts, where individual papers contribute multiple methods to the count array, though paper-level data is not retained in the aggregated Stan inputs and therefore cannot be corrected in the same way.

---

## Two-predictor NB2 regression: prevalence vs trajectory

Script: `R/08_literature_vs_llm.R` | Stan model: `stan/nb2_prevalence_gamma.stan`

### The question

The single-predictor regression conflates two mechanisms: an LLM trained on pre-2023 literature naturally recommends prevalent methods, and if prevalence correlates with gamma, the regression picks up a training-data effect. The two-predictor model separates them:

```
n_rec[i] ~ NB2(exp(alpha + b_pre * log1p(n_pre[i]) + b_gamma * gamma[i]), phi)
```

b_pre measures whether the LLM reflects its training data. b_gamma measures whether, after controlling for prevalence, the LLM additionally tracks post-2023 shifts.

### Results

| Model | Profile | b_pre mean | b_pre 90% CI | P(b_pre > 0) | b_gamma mean | b_gamma 90% CI | P(b_gamma > 0) |
|---|---|---|---|---|---|---|---|
| Qwen3 | overall | +0.658 | [+0.504, +0.803] | 1.000 | +0.083 | [-1.470, +1.656] | 0.537 |
| Qwen3 | novice | +1.048 | [+0.821, +1.281] | 1.000 | +0.107 | [-1.504, +1.684] | 0.547 |
| Qwen3 | intermediate | +0.674 | [+0.490, +0.857] | 1.000 | +0.035 | [-1.470, +1.574] | 0.518 |
| Qwen3 | expert | +0.417 | [+0.262, +0.574] | 1.000 | +0.224 | [-1.359, +1.761] | 0.586 |
| Gemma | overall | +0.580 | [+0.411, +0.754] | 1.000 | +0.146 | [-1.422, +1.724] | 0.556 |
| Gemma | novice | +0.684 | [+0.390, +0.991] | 1.000 | +0.087 | [-1.522, +1.659] | 0.531 |
| Gemma | intermediate | +0.537 | [+0.332, +0.741] | 1.000 | +0.032 | [-1.569, +1.646] | 0.521 |
| Gemma | expert | +0.506 | [+0.339, +0.671] | 1.000 | +0.218 | [-1.340, +1.780] | 0.594 |

<img src="../data/output/figures/prevalence_gamma/plot_bpre_bgamma_posteriors.png" width="700">

<img src="../data/output/figures/prevalence_gamma/plot_bpre_bgamma_by_profile.png" width="700">

### Interpretation

**b_pre is credibly positive in every condition** (P = 1.000). Both LLMs recommend methods in proportion to pre-2023 corpus presence.

**b_gamma is indistinguishable from zero in every condition** (P = 0.518–0.594). The posteriors look nearly identical across all 8 conditions because the gamma predictor carries almost no signal — 0/242 methods have a credible post-2023 shift — so the likelihood is flat on this coefficient and the posteriors are dominated by the prior (Normal(0,1)). The apparent uniformity across models and profiles is the null result visualised. All the meaningful variation shows up in b_pre, not b_gamma.

**The novice profile has the strongest b_pre.** Qwen3 novice: +1.048 vs expert: +0.417. Gemma: novice +0.684 vs expert +0.506. Less guidance = more reliance on corpus frequency = more concentrated recommendations. This is the mechanism behind the concentration gradient.

**The previous single-predictor beta was negative because of a confound.** The most prevalent pre-2023 methods happen to have slightly negative gamma (Spearman cor = -0.189). Once prevalence is separated, the apparent negative relationship disappears.

---

## Overall assessment

The mean-collapse hypothesis has two parts: (1) the LLM recommends a narrow set of methods, and (2) the literature converges toward that set. The evidence supports (1) but not (2).

**The mechanism is present, structural, and model-independent.** Both LLMs recommend methods in direct proportion to pre-2023 corpus prevalence (b_pre credibly positive, P = 1.000 in all conditions). Both produce recommendation distributions roughly a third as diverse as the published literature (29–32 vs 88–114 effective methods). The profile gradient (novice < intermediate < expert) survives with full Bayesian uncertainty. The concentration gap is credible (P = 1.000).

**The literature has not converged.** The inverse Simpson index rose from ~88 (pre-2023) to ~114 (post-2023), continuing uninterrupted through the post-LLM period. sigma_gamma = 0.110 [0.010, 0.222] shows weak evidence of post-2023 reshuffling, but it is smaller than the pre-existing trend (sigma_beta = 0.288), and 0/242 methods show a credible shift.

**Neither LLM tracks post-2023 shifts.** b_gamma is indistinguishable from zero in all 8 conditions. The single-predictor regression's negative beta was a confound: prevalent pre-2023 methods have slightly negative gamma. Once prevalence is controlled, the LLM is indifferent to post-2023 trajectory.

LLMs recommend from training-corpus prominence (the gun is loaded), but 3–4 years after widespread adoption, the field continues to diversify (it has not fired). Whether this reflects low adoption rates, researcher selectivity, or countervailing forces toward specialisation — the current data cannot distinguish.

---

## Sensitivity and robustness notes

### Would a frequentist approach change the result?

Almost certainly not. The null result is driven by noisy gamma predictors, not the inferential framework. A frequentist analysis would face the same structural problem. The Bayesian approach adds expressive precision: posteriors communicate the shape of uncertainty rather than a binary significance threshold.

### Would adjusting the L2 taxonomy groupings change the results?

The headline sigma_gamma would likely survive. Individual gamma estimates could change substantially since each method's gamma is estimated relative to its L2 group. Step 3 (beta, b_gamma) would likely remain null regardless of groupings — the LLM's recommendations are orthogonal to post-2023 trajectories.
