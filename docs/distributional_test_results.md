# Distributional Test — LLM Recommendations vs. Pre/Post-2023 Literature

Script: `R/sensitivity/09_distributional_test.R`  
Run date: 2026-05-11

---

## Design

Instead of regressing recommendation counts on noisy individual gammas (Step 3),
this test compares whole frequency distributions. For each of the 242 L3 methods,
we compute three vectors:

- **Pre-2023 literature** — total paper counts 2010–2022 (8495 papers)
- **Post-2023 literature** — total paper counts 2023–2026 (6660 papers)
- **LLM recommendations** — Qwen3 recommendation counts from the prompting experiment (6284 recommendations, remapped to v3 taxonomy)

If LLMs are driving convergence, their recommendation distribution should resemble
the post-2023 literature more than the pre-2023 literature. We measure similarity
using cosine similarity, Hellinger distance, and KL divergence.

---

## Results

### Overall similarity (observed data)

| Metric | LLM vs Pre-2023 | LLM vs Post-2023 | Delta | Direction |
|---|---|---|---|---|
| Cosine similarity | 0.4103 | 0.4803 | +0.0700 | post-2023 (supports mean-collapse) |
| Hellinger distance | 0.5181 | 0.4936 | -0.0245 | Closer to post |
| KL divergence | 1.1808 | 0.9637 | -0.2171 | Closer to post |

*For cosine: higher = more similar. For Hellinger/KL: lower = more similar.*

### By expertise profile

| Profile | Cosine(LLM, Pre) | Cosine(LLM, Post) | Delta |
|---|---|---|---|
| Overall | 0.4103 | 0.4803 | +0.0700 |
| Novice | 0.2965 | 0.3770 | +0.0805 |
| Intermediate | 0.3449 | 0.4142 | +0.0693 |
| Expert | 0.5400 | 0.5526 | +0.0125 |

### Bayesian posterior predictive (primary inference)

For each of 500 posterior draws from the main model, we reconstruct the predicted
method proportions for all group-year cells using the sampled parameters
(mu, beta, gamma, sigma_beta, sigma_gamma). We then aggregate to pre/post frequency
vectors and compute delta cosine against the LLM recommendation vector. The resulting
distribution propagates full parameter uncertainty from the main model.

- **Posterior mean delta cosine:** +0.0713
- **90% credible interval:** [+0.0581, +0.0848]
- **P(delta > 0):** 1.000

- **Posterior mean delta Hellinger:** +0.0241
- **90% CI:** [+0.0191, +0.0291]

### Frequentist permutation test (backup, N = 10,000)

Under the null hypothesis, the LLM recommendation vector is unrelated to the
pre/post-2023 distinction. We randomly shuffle which years are assigned to
'post' (keeping the same number of post years = 4) and recompute the
delta cosine similarity each time.

- **Observed delta cosine:** +0.0700
- **Permutation p-value:** 0.0013
- **Observed delta Hellinger:** +0.0245
- **Permutation p-value:** 0.0004

---

## Plots

### Posterior predictive distribution (primary)

![Posterior predictive](../data/output/figures/distributional/plot_posterior_predictive_delta.png)

### Permutation distribution (backup)

![Permutation](../data/output/figures/distributional/plot_permutation_cosine.png)

### Cosine similarity comparison

![Cosine](../data/output/figures/distributional/plot_cosine_comparison.png)

### By-profile comparison

![Profile](../data/output/figures/distributional/plot_cosine_by_profile.png)

---

## Interpretation

**The LLM recommendation distribution is credibly closer to the post-2023 literature than the pre-2023 literature.** The posterior predictive 90% CI for delta cosine is [+0.058, +0.085] — entirely above zero, with P(delta > 0) = 1.000. Every posterior draw from the main model, after propagating full parameter uncertainty through the predicted proportions, shows the LLM closer to the post-2023 method mix. The frequentist permutation test agrees (p = 0.0013).

**The profile gradient matches the mean-collapse prediction.** Novice recommendations show the largest shift toward the post-2023 distribution (delta cosine = +0.080), intermediate is in between (+0.069), and expert shows the smallest shift (+0.013). This ordering — less expert guidance produces more alignment with post-2023 trends — is exactly what the mean-collapse hypothesis predicts.

**Why this test succeeds where the regression failed.** The Step 3 regression asked whether *individual* methods' gammas predicted recommendation counts — but all 242 gammas are noisy (0/242 reach sig90), so the predictor was dominated by measurement error. The distributional test sidesteps this by comparing *whole frequency vectors* — it doesn't need any individual method's gamma to be well-estimated, only the overall distribution shape to differ between periods.

**Caveats.** The pre- and post-2023 literature distributions are themselves very similar (cosine = 0.896), so both are reasonably close to the LLM. The delta is real but modest in absolute terms. More importantly, this test establishes distributional similarity, not causation. The LLM's recommendations could resemble the post-2023 literature because: (a) the LLM influenced which methods researchers adopted (the mean-collapse mechanism), (b) the LLM was trained on more recent data and mirrors whatever trends were already happening, or (c) both. Distinguishing (a) from (b) would require a design that identifies LLM usage at the paper level — which this study cannot do.

**Bottom line.** The distributional test recovers the positive signal that the regression could not detect. LLM recommendations credibly align with the post-2023 method mix, especially under novice guidance. This is necessary — but not sufficient — evidence for the mean-collapse hypothesis.
