# Did LLMs cause convergence in computational archaeology methods?

![Research workflow](docs/workflow_diagram.png)

Imagine that every graduate student in a department suddenly started asking the same AI assistant for methodological advice. The assistant, trained on the same corpus, would naturally recommend the same handful of techniques — not because those techniques are best, but because they are most represented in its training data. Over time, the department's research would start to look eerily similar. This paper asks whether something like that is happening across computational archaeology.

We retrieved archaeology papers published between 2010 and 2026 from Scopus and retained the computational subset — papers whose abstracts describe a quantitative or computational methodology — yielding 7,763 papers for analysis. Each retained paper's methodology was classified into a two-level taxonomy: sub-disciplines (L2) and specific techniques (L3). Classification was performed with Qwen, a large language model, applied consistently to all abstracts, yielding 25 L2 sub-disciplines and 242 L3 techniques. This gives us a record of how the methodological menu of the discipline has changed, year by year, at fine granularity.

The core question is whether that menu got more generic after 2023, the year ChatGPT entered serious academic use. Think of it like watching a restaurant's menu evolve over a decade, and then asking whether the dishes got blander — more convergent on a safe average — once the chef started relying on recipe apps rather than creative intuition.

We measure diversity within each L2 sub-discipline using the Inverse Simpson index, which counts the effective number of distinct L3 methods in use. A score of 1 means one technique dominates completely; higher scores mean methods are more evenly spread. We model how this effective count changes over time using a Bayesian Dirichlet-Multinomial regression fit with Stan. Because each paper can be tagged with multiple L3 methods, the 7,763 unique papers expand to 15,155 paper–method observations that are aggregated into the count array passed to Stan (counts of papers per L3 method, per L2 sub-discipline, per year).

The model has a two-component structure. The first component, beta, captures each method's underlying linear trajectory from 2010 to 2026: some techniques were already rising or falling before LLMs existed. The second component, gamma, captures any additional deviation in log-odds share that began in 2023 and thereafter, encoded as a hard level shift via a binary `post_llm` indicator. Importantly, gamma measures a **step change in level** above the pre-existing beta trend — it cannot separately identify a sudden jump from a gradual post-2023 acceleration, though with only 3–4 years of post-adoption data these are not practically distinguishable. By separating these two components, we can ask not just whether methods changed after 2023, but whether that change was over and above what the pre-existing trend would have predicted. The key estimand is sigma_gamma, the global scale of across-method variation in the post-2023 deviation. If sigma_gamma is credibly above zero, there is real post-LLM heterogeneity in methodological trajectories — some methods accelerating, others declining — consistent with AI-driven recommendation effects.

The prior on sigma_gamma (`exponential(4)`) is intentionally tighter than the prior on sigma_beta (`exponential(2)`), reflecting the expectation that post-LLM effects, accumulated over 3–4 years, should be smaller than baseline trends accumulated over 13 years. This conservative prior means individual gamma estimates carry substantial uncertainty, and results should be interpreted at the level of the global scale parameter and directional patterns rather than individual method estimates.

The primary analysis operates at the L2-to-L3 level: within each sub-discipline, we watch the fine-grained technique mix evolve. As a robustness check on the temporal assumption, we re-run the primary analysis with the `post_llm` break set at 2022 (ChatGPT's launch) rather than 2023; stability of gamma estimates across both breakpoints strengthens the temporal inference. A second sensitivity analysis models the inverse Simpson diversity index directly at the L2 group level, testing whether sub-discipline-level homogenisation is detectable outside the compositional framework.

The bibliometric analysis is paired with a prompting experiment. We systematically query two local LLMs — Qwen3 (Alibaba) and Gemma (Google DeepMind) — at three simulated expertise levels with methodological questions, and classify each response into the same L3 taxonomy. This gives a direct estimate of what methods each LLM currently recommends. Using two models from different families with different training corpora tests whether recommendation behaviour is model-specific or structural.

The key analytical step is a two-predictor negative-binomial regression that separates training-corpus prevalence from post-2023 trajectory:

```
n_rec[i] ~ NB2(exp(alpha + b_pre * log1p(n_pre[i]) + b_gamma * gamma[i]), phi)
```

where `n_pre[i]` is the pre-2023 literature count for method *i* (a proxy for training-corpus exposure) and `gamma[i]` is the signed post-2023 excess. If `b_pre` is positive and `b_gamma` is near zero, the LLM is reflecting its training data but not tracking post-2023 shifts. If both are positive, the LLM is doing both. This separation is critical because a single-predictor regression on gamma alone conflates the two mechanisms.

The model is validated through a four-stage Bayesian workflow following Gelman et al. (2020): prior predictive checks confirm the priors generate plausible diversity values; posterior predictive checks show all 25 L2 groups are well-calibrated (see [workflow checks](docs/workflow_results.md)); fake-data simulation confirms sigma_gamma is identifiable through hierarchical aggregation across groups; and phi is estimated from data — the posterior concentrates at phi ≈ 1133, confirming the field is compositionally regular.

## Preliminary Results

> **Note:** These are preliminary results. All three analysis steps are complete but the evidence in Step 3 remains uncertain.

The analysis proceeds in three steps:

**Step 1 — Is there anomalous post-2023 methodological reshuffling?**

Weakly yes, but with wide uncertainty. The global scale of post-2023 method-level change (sigma_gamma) is above zero, though the lower bound of the 90% CI is near zero.

The model estimates phi from data using a weakly informative lognormal prior. In the primary L2→L3 analysis (25 L2 groups, 242 L3 methods), phi ≈ 1133 [605, 2088], confirming the field is compositionally regular — observed proportions track the structural trend closely year to year. sigma_gamma = 0.110 [0.010, 0.222].

The fit converged cleanly (Rhat ≤ 1.01, ESS (sigma_gamma) = 581, zero divergences). sigma_gamma < sigma_beta (0.110 vs 0.288): the post-LLM reshuffling is smaller in magnitude than the long-run baseline trend.

Note: sigma_gamma measures the *magnitude* of reshuffling, not its direction. A sigma_gamma credibly above zero is necessary but not sufficient evidence for convergence toward generic methods.

**Step 2 — Is the reshuffling directionally consistent with LLM-driven convergence?**

Uncertain. No individual gamma estimates have a 90% CI that fully excludes zero — all directional claims are tentative. The top methods by posterior mean are reported below as directional indicators.

Methods gaining share post-2023 (positive gamma mean, all CIs cross zero):
- L3-090: Multi-Criteria Decision Analysis (+0.098)
- L3-107: Chemometric and Spectroscopic Analysis (+0.091)
- L3-101: Information-Theoretic Entropy Measures (+0.091)
- L3-123: Generalized Linear Mixed Models (+0.089)
- L3-091: Bibliometric and Scientometric Mapping (+0.089)

Methods losing share post-2023 (negative gamma mean, all CIs cross zero):
- L3-103: Ecological Diversity Metrics (−0.125)
- L3-080: Network Analysis and Modeling (−0.083)
- L3-134: Logistic Regression Variants (−0.080)
- L3-026: Monte Carlo Simulation Methods (−0.077)
- L3-241: Archaeological Dating and Analysis Methods (−0.076)

Individual estimates should be read as directional indicators, not precise effect sizes. The conservative prior on sigma_gamma and the breadth of the taxonomy (242 methods) mean that individual method gammas are appropriately uncertain. The global reshuffling scale (sigma_gamma) remains the primary inferential target.

**Step 3 — Does the LLM's recommendation profile match the post-2023 literature?**

The prompting experiment queries Qwen3 and Gemma at 3 expertise levels with 28 archaeological research questions, classifies each response into the L3 taxonomy, and tests whether the LLM's recommendations align with post-2023 methodological shifts. We approach this from four angles. See `experiment/Results.md` for detailed results.

*Two-predictor regression (primary test).* A Bayesian negative-binomial regression separates training-corpus prevalence (`b_pre`) from post-2023 trajectory (`b_gamma`). The result is unambiguous: `b_pre` is credibly positive in all 8 conditions (2 models × 4 profiles, P > 0 = 1.000) — both LLMs recommend methods in proportion to their pre-2023 corpus presence. `b_gamma` is indistinguishable from zero in every condition (P ranges 0.518–0.594) — after controlling for prevalence, neither LLM shows any sensitivity to post-2023 trajectory. The LLMs reflect their training data, not recent shifts.

*Concentration analysis (with Bayesian uncertainty).* The Inverse Simpson index, computed with full Dirichlet-conjugate posterior uncertainty, confirms that both LLMs are dramatically more concentrated than the literature. Posterior medians: literature 88–114 effective methods; Qwen3 overall 32 [30.5, 33.4]; Gemma overall 29 [28.0, 30.4]. The gap is credible (P = 1.000). The profile gradient (novice < intermediate < expert) survives with full uncertainty, and the novice b_pre is the largest (Qwen3 novice: +1.048 vs expert: +0.417), explaining the concentration gradient mechanistically: less-constrained prompts allow the LLM to default more heavily to corpus frequency.

*Cross-model replication.* Qwen3 and Gemma agree moderately on which methods to recommend (Spearman rho = 0.595) but produce the same structural concentration pattern. Gemma is credibly more concentrated than Qwen3 overall (P = 0.992 for the difference). The concentration mechanism is model-independent; the specific recommendations are not.

*Distributional test.* The LLM's overall distributional shape is credibly closer to the post-2023 literature than the pre-2023 literature (delta cosine = +0.071, 90% CI [+0.058, +0.085]), with a novice > intermediate > expert gradient. This weaker, non-directional signal is consistent with the LLM reflecting a recent training corpus rather than actively tracking post-2023 trends.

**What the results mean in plain terms**

The mean-collapse hypothesis has two parts: (1) the LLM recommends a narrow set of methods, and (2) the literature converges toward that set. The evidence supports (1) but not (2).

Both LLMs recommend methods in direct proportion to their pre-2023 corpus prevalence. The less guidance a researcher provides, the stronger this prevalence effect — producing a recommendation distribution roughly a third as diverse as the published literature. The mechanism for convergence is demonstrably present, structural across two model families, and quantified with full Bayesian uncertainty.

But the literature has not converged. The Inverse Simpson index has risen from ~88 (pre-2023) to ~114 (post-2023), and this diversifying trend continued uninterrupted through the post-LLM period. sigma_gamma = 0.110 [0.010, 0.222] shows weak evidence of post-2023 reshuffling, but its magnitude is smaller than the pre-existing trend (sigma_gamma < sigma_beta, 0.110 vs 0.288), and no individual method shows a credible shift.

The two-predictor regression resolves the key ambiguity in the earlier single-predictor analysis, which produced negative beta posteriors. That negative direction was a confound: the most prevalent pre-2023 methods (which the LLM favours) happen to have slightly negative gamma (they were already large and stable, not post-2023 gainers). Once prevalence is separated from gamma, the apparent negative relationship disappears — the LLM is simply indifferent to post-2023 trajectory.

The honest summary: LLMs recommend from training-corpus prominence (the gun is loaded), but 3–4 years after widespread adoption, the field continues to diversify (it has not fired). Whether this reflects low adoption rates, researcher selectivity in which LLM advice they follow, or countervailing forces toward specialisation — the current data cannot distinguish.

## Sensitivity Analyses

**Sensitivity A — Minimum-count threshold (06b)**

33/242 L3 methods survive a >=50 paper filter in 2023–2025. Under this restriction, overall β = −0.138, P(β > 0) = 0.438 — still negative and consistent with the main analysis. The null Step 3 result is robust to restricting to well-represented methods.

**Sensitivity B — Step 3 with v2→v3 taxonomy remapping (08)**

The L3 taxonomy was revised during the project (v2: 225 methods → v3: 242 methods), with many labels renamed or reorganised. The early experiment run was classified under v2; only 53/242 v3 methods matched exactly. This sensitivity uses fuzzy string matching to remap the v2 labels onto v3, raising coverage to 205/242 (85%). The results are unchanged: overall β = −0.339, P(β > 0) = 0.368. All profiles remain negative. Note: the current experiment data was reclassified directly against v3, so this sensitivity applies only to the earlier v2-classified run.

**Sensitivity C — Distributional test (09)**

Instead of regressing on noisy individual gammas, we compare the *whole* LLM recommendation distribution to the pre- vs. post-2023 method frequency vectors. The LLM is credibly closer to the post-2023 literature: posterior predictive delta cosine = +0.071, 90% CI [+0.058, +0.085], P(delta > 0) = 1.000. The profile gradient matches the mean-collapse prediction: novice delta (+0.080) > intermediate (+0.069) > expert (+0.013). This recovers the positive signal that the regression could not detect — the LLM's recommendations align with the post-2023 method mix, especially under novice guidance. See [full results](docs/distributional_test_results.md).

**Sensitivity D — Direct diversity trajectory (07)**

Models inv_simpson directly at L2 group level with the same two-slope structure. sigma_gamma = 0.064 [0.003, 0.174], effectively null. sigma_beta = 0.677 [0.510, 0.910] — pre-existing trend variation is 10× larger. All 25 group-level gamma CIs straddle zero. The field reorients internally but does not measurably homogenise at the sub-discipline level.

## Analysis outputs

| Analysis | Description | Results |
|---|---|---|
| L2→L3 primary | Within each sub-discipline, specific technique shares over time | [View](docs/l2_l3_results.md) |
| Bayesian workflow | Prior predictive, PPC, fake data recovery, phi sensitivity | [View](docs/workflow_results.md) |
| Step 3: NB regression | Single-predictor NB on gamma (Qwen3 + Gemma) | [View](experiment/Results.md) |
| Step 3: Concentration | Dirichlet-conjugate concentration posteriors (both models × 3 profiles) | [View](experiment/Results.md) |
| Step 3: Prevalence vs trajectory | Two-predictor NB separating corpus prevalence from post-2023 shifts | [View](experiment/Results.md) |
| Cross-model comparison | Qwen3 vs Gemma recommendation patterns and divergences | [View](experiment/Results.md) |
| Sensitivity A | Count-threshold variant of Step 3 (>=50 papers) | [View](R/sensitivity/README.md) |
| Sensitivity B | Step 3 with v2→v3 taxonomy remapping (85% match) | [View](docs/step3_remapped_results.md) |
| Sensitivity C | Distributional test: LLM vs pre/post-2023 (cosine, permutation) | [View](docs/distributional_test_results.md) |
| Sensitivity D | Direct diversity trajectory model (inv_simpson) | [View](R/sensitivity/README.md) |

## Future directions

The analysis identifies a clear gap between the LLM's concentrated recommendations (29–32 effective methods) and the literature's continuing diversification (~114 effective methods). Two design improvements could determine whether this gap will close:

1. **More post-LLM years.** With only 3–4 post-LLM years, gamma is weakly identified by construction (0/242 methods reach sig90). Rerunning in 2028 with 5–6 post-LLM years would substantially sharpen the estimates and reveal whether the diversification trend has slowed, plateaued, or reversed.

2. **Paper-level LLM usage data.** The current design cannot distinguish whether the LLM's distributional resemblance to the post-2023 literature (Sensitivity C) reflects causal influence or passive reflection of training data. Surveys or metadata on which papers used LLM-assisted methodological choices would allow a direct test of the causal pathway.

## Pipeline execution order

The scripts must be run in this order (each depends on outputs from earlier steps):

```
# Core bibliometric pipeline
00_data_prep.R            → stan_data.rds, vocab.rds
01_fit_model.R            → MCMC fit (phi-free Dirichlet-Multinomial)
02_extract_plot.R         → L2→L3 posteriors, diversity plots
inspect_gamma.R           → gamma_results.csv (used by 05, 06, 08, 09)
04_workflow_checks.R      → Bayesian workflow validation
05_robustness_2022.R      → 2022-break robustness check

# Experiment: single-predictor NB regression (n_rec ~ gamma)
06_step3_llm_comparison.R       → Qwen3 NB regression on gamma
06b_step3_llm_comparison_gemma.R → Gemma NB regression on gamma

# Experiment: exploratory descriptive analysis
07_exploratory_graphs.R         → Qwen3 exploratory graphs
07b_exploratory_gemma.R         → Gemma exploratory + cross-model comparison

# Experiment: Bayesian concentration posteriors
08_experiment_concentration.R   → Dirichlet-conjugate inv_simpson posteriors

# Experiment: two-predictor regression (n_rec ~ n_pre + gamma)
09_literature_vs_llm.R          → Separates corpus prevalence from post-2023 trajectory

# Sensitivity (standalone, run after main pipeline)
R/sensitivity/06b_step3_count_threshold.R → Count-threshold variant of Step 3
R/sensitivity/07_diversity_trajectory.R   → Direct diversity trajectory model
R/sensitivity/08_step3_v2_remapped.R      → v2→v3 taxonomy remapping
R/sensitivity/09_distributional_test.R    → Distributional cosine test
```

Scripts 04 and 05–06 can run in parallel. `inspect_gamma.R` sits between 02 and the downstream scripts because it produces `data/output/phi_free/gamma_results.csv`. The experiment scripts (06–09) require gamma_results.csv and the experiment CSVs in `experiment/analysis/`.

## Repository structure

```
├── R/
│   ├── 00_data_prep.R                     # Data loading & Stan data preparation
│   ├── 01_fit_model.R                     # L2→L3 primary model (cmdstanr, phi-free)
│   ├── 02_extract_plot.R                  # Extract posteriors & generate L2→L3 plots
│   ├── 04_workflow_checks.R              # Bayesian workflow validation
│   ├── 05_robustness_2022.R              # 2022-break robustness check
│   ├── 06_step3_llm_comparison.R         # Qwen3: single-predictor NB on gamma
│   ├── 06b_step3_llm_comparison_gemma.R  # Gemma: single-predictor NB on gamma
│   ├── 07_exploratory_graphs.R           # Qwen3 descriptive exploratory analysis
│   ├── 07b_exploratory_gemma.R           # Gemma exploratory + cross-model comparison
│   ├── 08_experiment_concentration.R     # Dirichlet-conjugate concentration posteriors
│   ├── 09_literature_vs_llm.R            # Two-predictor NB: prevalence vs trajectory
│   ├── inspect_gamma.R                   # Gamma posterior extraction
│   ├── sensitivity/                      # Sensitivity and robustness analyses
│   └── archive/                          # Deprecated scripts
├── stan/
│   ├── diversity_model_phi_free.stan     # Primary L2→L3 Dirichlet-Multinomial
│   ├── poisson_gamma_regression.stan     # Single-predictor NB regression
│   ├── nb2_prevalence_gamma.stan         # Two-predictor NB regression
│   ├── diversity_trajectory.stan         # Direct diversity trajectory model
│   └── archive/                          # Deprecated models (l1_l2)
├── data/
│   ├── input/                            # Taxonomy and raw corpus data (gitignored)
│   └── output/
│       ├── figures/                      # All analysis plots by subdirectory
│       │   ├── l2_l3/                    # Primary analysis
│       │   ├── step3/                    # Qwen3 NB regression
│       │   ├── step3_gemma/              # Gemma NB regression
│       │   ├── exploratory/              # Qwen3 descriptive
│       │   ├── exploratory_gemma/        # Gemma descriptive
│       │   ├── comparison/               # Cross-model comparison
│       │   ├── concentration/            # Bayesian concentration posteriors
│       │   ├── prevalence_gamma/         # Two-predictor regression
│       │   └── ...                       # workflow, robustness, sensitivity, etc.
│       └── phi_free/                     # Gamma and beta results CSVs
├── docs/                                 # Analysis result documentation
├── experiment/
│   ├── README.md                         # Experiment design and methodology
│   ├── Results.md                        # Detailed experiment results
│   └── analysis/
│       ├── experiment_results_QWEN.csv   # Qwen3 experiment output (v3 taxonomy)
│       ├── experiment_results_GEMMA.csv  # Gemma experiment output
│       └── archive/                      # Superseded experiment data
└── logs/                                 # Runtime logs (gitignored)
```
