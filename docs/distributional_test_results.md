# Distributional Test — LLM Recommendations vs. Pre/Post-2023 Literature

Script: `R/sensitivity/C_distributional_test.R`  
Run date: 2026-06-06

---

## Design

Instead of regressing recommendation counts on noisy individual gammas (Step 3),
this test compares whole frequency distributions. For each of the 242 L3 methods,
we compute three vectors:

- **Pre-2023 literature** — total paper counts 2010–2022 (8495 papers)
- **Post-2023 literature** — total paper counts 2023–2025 (5749 papers)
- **LLM recommendations** — Qwen3 recommendation counts from the prompting experiment (6284 recommendations, remapped to v3 taxonomy)

If LLMs are driving convergence, their recommendation distribution should resemble
the post-2023 literature more than the pre-2023 literature. We measure similarity
using cosine similarity, Hellinger distance, and KL divergence.

---

## Results

### Overall similarity (observed data)

| Metric | LLM vs Pre-2023 | LLM vs Post-2023 | Delta | Direction |
|---|---|---|---|---|
| Cosine similarity | 0.4103 | 0.4759 | +0.0657 | post-2023 (supports mean-collapse) |
| Hellinger distance | 0.5181 | 0.4958 | -0.0223 | Closer to post |
| KL divergence | 1.1808 | 0.9721 | -0.2087 | Closer to post |

*For cosine: higher = more similar. For Hellinger/KL: lower = more similar.*

### By expertise profile

| Profile | Cosine(LLM, Pre) | Cosine(LLM, Post) | Delta |
|---|---|---|---|
| Overall | 0.4103 | 0.4759 | +0.0657 |
| Novice | 0.2965 | 0.3735 | +0.0770 |
| Intermediate | 0.3449 | 0.4112 | +0.0663 |
| Expert | 0.5400 | 0.5467 | +0.0067 |

### Bayesian posterior predictive (primary inference)

For each of 500 posterior draws from the main model, we reconstruct the predicted
method proportions for all group-year cells using the sampled parameters
(mu, beta, gamma, sigma_beta, sigma_gamma). We then aggregate to pre/post frequency
vectors and compute delta cosine against the LLM recommendation vector. The resulting
distribution propagates full parameter uncertainty from the main model.

- **Posterior mean delta cosine:** +0.0677
- **90% credible interval:** [+0.0554, +0.0789]
- **P(delta > 0):** 1.000

- **Posterior mean delta Hellinger:** +0.0219
- **90% CI:** [+0.0174, +0.0265]

### Frequentist permutation test (backup, N = 10,000)

Under the null hypothesis, the LLM recommendation vector is unrelated to the
pre/post-2023 distinction. We randomly shuffle which years are assigned to
'post' (keeping the same number of post years = 3) and recompute the
delta cosine similarity each time.

- **Observed delta cosine:** +0.0657
- **Permutation p-value:** 0.0025
- **Observed delta Hellinger:** +0.0223
- **Permutation p-value:** 0.0012

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

*(Auto-generated; update after reviewing results.)*
