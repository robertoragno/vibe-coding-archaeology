# Step 3 Results — LLM Recommendation vs. Bayesian Gamma

Script: `R/06_step3_llm_comparison.R`  
Run date: 2026-05-09

---

## Experiment data summary

| Metric | Value |
|---|---|
| Raw rows in `experiment_results.csv` | 6,758 |
| Consistent L4 → L3 mappings used | 6,284 |
| L3 methods matched to vocabulary | 6,080 |
| L3 methods in vocabulary | 225 |
| L3 methods receiving ≥ 1 recommendation | 192 (85%) |

### Recommendations by profile

| Profile | Total recommendations | Distinct L3 methods covered |
|---|---|---|
| Novice | 2,263 | 123 |
| Intermediate | 1,998 | 134 |
| Expert | 1,819 | 169 |

The novice profile covers the fewest distinct methods (123 vs. 169 for expert) and generates the most total recommendations, consistent with the mean-collapse hypothesis: less methodological guidance from the researcher leads to more concentrated LLM output.

---

## Top 10 most-recommended L3 methods

**Note on sig90:** A method has `sig90 = TRUE` if the 90% posterior credible interval for its γ (post-2023 excess slope above the pre-existing trend) excludes zero — meaning the post-2023 change in that method's share is credibly nonzero. None of the 225 methods reaches this threshold, indicating that individual post-2023 γ estimates remain uncertain.

| L3 method | Total | Novice | Intermediate | Expert | Mean γ | sig90 |
|---|---|---|---|---|---|---|
| L3-216: Process-Based Simulation Modeling | 545 | 285 | 246 | 14 | +0.115 | FALSE |
| L3-080: Complex Network Analysis | 499 | 242 | 177 | 80 | −0.043 | FALSE |
| L3-193: Natural Language Processing | 324 | 158 | 137 | 29 | −0.016 | FALSE |
| L3-225: GIS-Based Spatial Analysis | 308 | 211 | 81 | 16 | +0.054 | FALSE |
| L3-240: Remote Sensing and Photogrammetry | 151 | 116 | 32 | 3 | +0.039 | FALSE |
| L3-236: Automated Content Classification | 140 | 105 | 29 | 6 | +0.029 | FALSE |
| L3-019: Principal Component Analysis Variants | 123 | 16 | 22 | 85 | −0.096 | FALSE |
| L3-158: Bayesian Statistical Modeling | 119 | 27 | 34 | 58 | +0.058 | FALSE |
| L3-144: Bayesian Chronological Inference | 112 | 46 | 46 | 20 | +0.001 | FALSE |
| L3-052: Partitioning Clustering Algorithms | 108 | 11 | 38 | 59 | +0.019 | FALSE |

---

## Gamma and recommendation alignment

Positive-γ methods that are also among the most recommended (strongest mean-collapse candidates):

| L3 method | Mean γ | n_rec (total) |
|---|---|---|
| L3-216: Process-Based Simulation Modeling | +0.115 | 545 |
| L3-225: GIS-Based Spatial Analysis | +0.054 | 308 |
| L3-240: Remote Sensing and Photogrammetry | +0.039 | 151 |
| L3-236: Automated Content Classification | +0.029 | 140 |
| L3-158: Bayesian Statistical Modeling | +0.058 | 119 |

*None of these individually reach sig90; the relationship is assessed jointly via the Bayesian negative-binomial regression (β coefficient).*

No L3 methods reached sig90 = TRUE in this taxonomy version.

---

## Bayesian negative-binomial regression (β posteriors)

### The generative story

Think of it this way. For each of the 225 L3 methods in our taxonomy, we know two things: how often Qwen3 recommended it across the simulation runs, and how much that method's share in the published literature shifted post-2023 beyond its pre-existing trend (that's γ, from the main model). The question we're asking is: *does the magnitude of a method's post-2023 change predict how often the LLM reaches for it?*

If the LLM is reinforcing whatever is reshaping the literature — recommending the methods that gained, avoiding the ones that declined — we'd expect a positive relationship. If the LLM is blind to post-2023 trajectories and just reaches for whatever is most prevalent in its training data regardless of recent shifts, there'd be no relationship.

The model is:

```
n_rec[i] ~ NegBin2( exp(α + β × γ̄ᵢ) , φ )
```

where γ̄ᵢ is the *signed* posterior mean gamma for method *i* — positive for methods that gained share post-2023, negative for methods that declined.

**What "signed γ" means.** γ (gamma) is the excess slope estimated for each L3 method post-2023 by the main model: how much that method's share in the published literature shifted after 2023, above and beyond whatever trend it already had before. *Signed* means the value keeps its natural positive or negative direction, as opposed to taking the absolute value |γ|. So γ > 0 means a method gained share post-2023; γ < 0 means it lost share; γ ≈ 0 means its trajectory was roughly flat. The sign matters here because the mean-collapse hypothesis is directional — it predicts LLMs should specifically recommend methods that *gained* share. Using |γ| would lump sharply rising and sharply declining methods into the same high-|γ| bucket, washing out the directional signal. Signed γ is the correct operationalisation.

**α** is the log-rate intercept: the expected recommendation count for a method whose post-2023 trajectory is exactly flat (γ = 0). Think of it as the LLM's default baseline — how often it would reach for a perfectly stable method.

**β** is the parameter we care about. It is the change in log expected recommendation count for each unit increase in γ̄. A positive β means the LLM reaches more often for methods that *gained* share post-2023 and less often for methods that declined — the directional prediction of mean collapse. A negative β would mean the opposite (the LLM preferentially recommends declining methods). β ≈ 0 means the LLM is indifferent to post-2023 trajectory.

Note: the previous version of this analysis used |γ̄| (absolute value), which is a weaker, non-directional test. The signed version is the correct operationalisation of mean collapse, which predicts a positive β specifically for *gaining* methods.

**φ** is the overdispersion of the negative-binomial. Some methods get recommended far more, or far less, than their γ alone would predict — perhaps because they are simply famous (network analysis, machine learning) or highly niche. φ absorbs that extra noise beyond pure Poisson randomness.

**Priors:** β ~ Normal(0, 1) — weakly informative. On the log scale, a β of ±1 would mean a one-unit increase in |γ| multiplies expected recommendation count by e ≈ 2.7. That's a very large effect; the prior is saying we'd be surprised by something that strong but we're not excluding it. α ~ Normal(0, 2) similarly allows a wide baseline. φ ~ Exponential(1) is a weakly regularising prior on overdispersion.

The model is run four times: once on total recommendations (overall) and once separately for each expertise profile (novice / intermediate / expert).

---

### Convergence

Four independent Stan fits (4 chains × 1000 post-warmup draws each). Diagnostics saved to `data/output/step3_convergence.csv`. Good convergence requires max Rhat < 1.01 and min n_eff > 400.

| Profile | Max Rhat | Min n_eff |
|---|---|---|
| Overall | 1.001 | 3651 |
| Novice | 1.0008 | 3804 |
| Intermediate | 1.0021 | 3601 |
| Expert | 1.0027 | 3278 |

---

### Results

| Profile | β mean | 90% credible interval | P(β > 0) |
|---|---|---|---|
| Overall | +0.638 | [−0.851, +2.101] | 0.765 |
| Novice | +0.646 | [−0.923, +2.238] | 0.753 |
| Intermediate | +0.553 | [−0.919, +2.065] | 0.721 |
| Expert | −0.330 | [−1.831, +1.163] | 0.359 |

The posteriors for β are wide in all four conditions — every 90% CI crosses zero. The model has looked at the data and is uncertain, but the direction is now consistent with the mean-collapse prediction: the overall, novice, and intermediate posteriors lean positive (P(β > 0) ≈ 0.72–0.77), while the expert posterior leans negative. A positive β means the LLM reaches more often for methods that gained share post-2023.

**Profile gradient.** The mean-collapse hypothesis predicts a monotone ordering novice > intermediate > expert: a researcher who gives the LLM less methodological guidance should get output more tightly aligned with recent trends. The observed means run in the predicted direction for the expert separation — expert (−0.330) is clearly below both novice (+0.646) and intermediate (+0.553). The novice-intermediate distinction is negligible: P(β_novice > β_intermediate) = 0.529, essentially a coin flip. The sharper signal is the expert split: P(β_novice > β_expert) = 0.768, P(β_intermediate > β_expert) = 0.758. The data suggest that expert prompts decouple the LLM from post-2023 trends, while novice and intermediate prompts produce similar trend-aligned behaviour — consistent with the mean-collapse mechanism, though none of the individual CIs excludes zero.

---

### Interpretation: what this does and does not mean

**The direction is now consistent with the mean-collapse prediction, but the evidence is suggestive rather than confirmatory.** Steps 1 and 2 established that something changed post-2023: sigma_gamma is credibly above zero, and the directional pattern (generic methods gaining, specialised methods losing) is consistent with LLM-driven mean collapse. Step 3 was designed to close the causal loop by asking whether Qwen3's recommendations specifically predict which methods gained.

The overall β posterior leans positive (mean +0.638, P(β > 0) = 0.765), and the profile ordering (novice/intermediate positive, expert negative) matches the predicted direction. But none of the four CIs excludes zero. The data are *compatible* with the mean-collapse mechanism but do not *confirm* it. The width of the posteriors reflects at least two structural limitations:

1. **γ is estimated with substantial noise.** None of the 225 methods has a 90% credible interval for γ that excludes zero. When the predictor in a regression is this noisy, the coefficient is attenuated toward zero regardless of the true relationship. The wide β posterior reflects, in part, that γ itself is uncertain.

2. **Qwen3 is a proxy for the LLMs archaeologists are actually using.** The reshuffling in the corpus reflects whatever LLMs researchers were querying during 2023–2025 — primarily ChatGPT and GPT-4. Qwen3 is a different model from a different family with a different training corpus. Its recommendations are not guaranteed to match those of the models that actually influenced the published literature.

The honest summary is: the regression is directionally consistent with the mean-collapse mechanism — the LLM reaches more often for methods that gained share post-2023, especially under novice and intermediate prompts — but the CIs are too wide for this to constitute strong evidence. The structural noise problems (uncertain γ predictors, proxy LLM) would need to be resolved before a sharper test is possible.

---

### Plot A — Overall β posterior

*This plot shows the full posterior distribution of β estimated from all 225 L3 methods combined (pooling across novice, intermediate, and expert profiles). The x-axis is the value of β; the y-axis is posterior density. The distribution leans positive (mean = +0.638, P(β > 0) = 0.765) but is wide enough that the 90% CI crosses zero. The posterior is consistent with, but not confirmatory of, the mean-collapse prediction.*

<img src="../data/output/figures/step3/plot_beta_posterior_overall.png" width="520">

### Plot B — β posterior by expertise profile

*This plot overlays or panels the β posteriors separately for the three researcher profiles (novice, intermediate, expert). The mean-collapse hypothesis predicts novice > intermediate > expert. The expert distribution sits clearly to the left (mean = −0.330), while novice (+0.646) and intermediate (+0.553) overlap substantially. The separation is between expert and the other two profiles, not a smooth monotone gradient. All three distributions straddle zero.*

<img src="../data/output/figures/step3/plot_beta_posterior_by_profile.png" width="520">

### Plot C — Signed γ vs. LLM recommendation count

<img src="../data/output/figures/step3/plot_gamma_vs_recommendations.png" width="520">

### Plot D — Top 20 recommended methods and their post-2023 direction

<img src="../data/output/figures/step3/plot_top_recommended_direction.png" width="520">

All bars in Plot D are grey: all 20 most-recommended methods have uncertain post-2023 trajectories (90% CI for γ crosses zero), since no method in the taxonomy reaches sig90. This is a direct read from the main model's gamma posteriors and does not depend on the β regression. It reinforces the noise point above — the most-recommended methods are not ones whose post-2023 trajectory is well-identified, which limits what the regression can recover.

---

## Overall assessment: did the paper succeed?

The short answer is: **suggestive, and honestly uncertain.**

**What the paper delivers:**

- **The phenomenon is real.** The main model (Steps 1–2) finds σ_γ credibly above zero: post-2023, methods did not all move together — some gained share and some lost it, beyond what a flat trend would predict. The directional pattern (generic, broadly applicable methods gaining; specialised methods losing) is consistent with the mean-collapse hypothesis.
- **LLM behaviour matches the qualitative prediction.** The experiment shows that Qwen3 produces more concentrated recommendations for novice profiles than expert ones: 123 distinct L3 methods covered vs. 169. The concentration mechanism that mean-collapse requires is demonstrably present in LLM output.
- **The direction of Step 3 is consistent with the mean-collapse prediction.** The overall β posterior leans positive (P(β > 0) = 0.765): the LLM tends to recommend methods that gained share post-2023 more than those that declined. The profile ordering matches the prediction — expert β is negative (−0.330) while novice (+0.646) and intermediate (+0.553) are positive, and P(β_novice > β_expert) = 0.768.

**What the paper does not deliver:**

- **The causal link is not confirmed.** Step 3 returns β posteriors in the predicted direction but with 90% CIs that all cross zero. The model is leaning toward the mean-collapse explanation with moderate posterior probability, but the evidence is not strong enough to rule out chance. The data are compatible with the hypothesis, not confirmatory of it.
- **The full monotone gradient is absent.** The expert profile separates clearly from novice and intermediate, but the novice–intermediate distinction is negligible (P(β_novice > β_intermediate) = 0.529). The story is "expert prompts decouple the LLM from post-2023 trends" rather than the smooth expertise gradient the hypothesis predicts.

**Is this a success?**

Partially. The direction of all three steps is now consistent — something changed post-2023, generic methods gained, and Qwen3's recommendations lean toward those gaining methods, especially under less expert guidance. But no individual CI excludes zero in Step 3, and two structural problems limit the precision of the test: γ is estimated with high uncertainty (none of 225 methods has a credible non-zero γ, meaning the predictor is dominated by noise), and Qwen3 is a proxy for the specific LLMs that were actually shaping the corpus during 2023–2025 (primarily ChatGPT and GPT-4).

The paper is best read as establishing *directional consistency* across all three steps of the mean-collapse argument — pattern, mechanism, and correlation all point the same way — while acknowledging that the quantitative evidence in Step 3 remains uncertain. A sharper test would need γ estimates precise enough to serve as reliable predictors, and recommendation data from the actual models involved rather than a surrogate. The methodological infrastructure built here — the two-slope hierarchical model, the taxonomy, the simulation framework — is the foundation any follow-up study would need to strengthen the causal argument.

---

## Sensitivity and robustness notes

### Would a frequentist correlation have changed the Step 3 result?

Almost certainly not. The core result — β posteriors that lean positive but with CIs crossing zero — is driven by the structure of the data, not the inferential framework. A frequentist Pearson or Spearman correlation between γ̄ and n_rec would face the same problem: all 225 methods have γ estimates so uncertain that the predictor is dominated by noise. A frequentist analysis would likely return a non-significant result for the same structural reason the Bayesian CIs are wide.

The profile separation (expert negative, novice/intermediate positive) is also a feature of the data, not the framework — a frequentist analysis would show the same ordering.

What the Bayesian approach adds here is expressive precision. Instead of a binary "p > 0.05, fail to reject null," the posteriors communicate that the model leans in the predicted direction with moderate probability — P(β > 0) = 0.765 overall — while remaining genuinely uncertain. The negative-binomial model also explicitly handles overdispersion in recommendation counts that a simple correlation ignores. The qualitative conclusion is the same; the Bayesian framing is more informative about the shape of the uncertainty.

### Would adjusting the L2 taxonomy groupings change the results?

**The headline finding (σ_γ credibly above zero) would almost certainly survive.** The post-2023 reshuffling signal is present in the raw counts. The existing L1→L2 sensitivity analysis (`R/03_l1_l2_analysis.R`) already demonstrates this: the same model run one level up the hierarchy still finds a nonzero σ_γ, as expected from a real phenomenon rather than an artefact of a particular grouping choice.

**Individual γ estimates would change, potentially substantially.** Each L3 method's γ is estimated relative to the other methods sharing its L2 group. Reassigning a method to a different L2 group changes its competitive reference set — its baseline, its pre-2023 trend, the zero-sum constraint it operates under. The specific list of "gaining" and "losing" methods from Step 2 could look different under a different taxonomy.

**Step 3 (β) would almost certainly remain uncertain.** The problem in the regression is not that the γ values are mis-specified — it is that *all* γ estimates carry so much uncertainty that they function as noisy predictors. Different L2 groupings would produce a different set of γ values, but they would still be estimated with high uncertainty (no methods reach sig90 in the current taxonomy). β would remain wide with CIs crossing zero.

The one scenario in which L2 restructuring could materially change the Step 3 conclusion is if the current groupings are actively suppressing signal — for instance, if a genuinely gaining method is grouped with other gaining methods, making its *relative* gain within the group appear flat. This is theoretically possible but would require a substantive, theoretically motivated argument for which specific restructuring reveals the true signal rather than a different one.
