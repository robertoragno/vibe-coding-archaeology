# Did LLMs cause convergence in computational archaeology methods?

![Research workflow](docs/pipeline_v2.png)

Imagine that every graduate student in a department suddenly started asking the same AI assistant for methodological advice. The assistant, trained on the same corpus, would naturally recommend the same handful of techniques — not because those techniques are best, but because they are most represented in its training data. Over time, the department's research would start to look eerily similar. This paper asks whether something like that is happening across computational archaeology.

We retrieved archaeology papers published between 2010 and 2026 from Scopus and retained the computational subset — papers whose abstracts describe a quantitative or computational methodology — yielding 7,763 papers for analysis. Each retained paper's methodology was classified into a three-level taxonomy: broad families (L1), sub-disciplines (L2), and specific techniques (L3). Classification was performed with Qwen, a large language model, applied consistently to all abstracts. This gives us a record of how the methodological menu of the discipline has changed, year by year, at fine granularity.

The core question is whether that menu got more generic after 2023, the year ChatGPT entered serious academic use. Think of it like watching a restaurant's menu evolve over a decade, and then asking whether the dishes got blander — more convergent on a safe average — once the chef started relying on recipe apps rather than creative intuition.

We measure diversity within each L2 sub-discipline using the Inverse Simpson index, which counts the effective number of distinct L3 methods in use. A score of 1 means one technique dominates completely; higher scores mean methods are more evenly spread. We model how this effective count changes over time using a Bayesian Dirichlet-Multinomial regression fit with Stan. Because each paper can be tagged with multiple L3 methods, the 7,763 unique papers expand to 15,158 paper–method observations that are aggregated into the count array passed to Stan (counts of papers per L3 method, per L2 sub-discipline, per year).

The model has a two-component structure. The first component, beta, captures each method's underlying linear trajectory from 2010 to 2026: some techniques were already rising or falling before LLMs existed. The second component, gamma, captures any additional deviation in log-odds share that began in 2023 and thereafter, encoded as a hard level shift via a binary `post_llm` indicator. Importantly, gamma measures a **step change in level** above the pre-existing beta trend — it cannot separately identify a sudden jump from a gradual post-2023 acceleration, though with only 3–4 years of post-adoption data these are not practically distinguishable. By separating these two components, we can ask not just whether methods changed after 2023, but whether that change was over and above what the pre-existing trend would have predicted. The key estimand is sigma_gamma, the global scale of across-method variation in the post-2023 deviation. If sigma_gamma is credibly above zero, there is real post-LLM heterogeneity in methodological trajectories — some methods accelerating, others declining — consistent with AI-driven recommendation effects.

The prior on sigma_gamma (`exponential(4)`) is intentionally tighter than the prior on sigma_beta (`exponential(2)`), reflecting the expectation that post-LLM effects, accumulated over 3–4 years, should be smaller than baseline trends accumulated over 13 years. This conservative prior means individual gamma estimates carry substantial uncertainty, and results should be interpreted at the level of the global scale parameter and directional patterns rather than individual method estimates.

We run this analysis twice. The primary analysis operates at the L2-to-L3 level: within each sub-discipline, we watch the fine-grained technique mix evolve. A complementary sensitivity analysis operates at the L1-to-L2 level: within each broad family, we watch the sub-discipline mix. If both levels tell a consistent story, the finding is robust. As a robustness check on the temporal assumption, we re-run the primary analysis with the `post_llm` break set at 2022 (ChatGPT's launch) rather than 2023; stability of gamma estimates across both breakpoints would strengthen the temporal inference.

The bibliometric analysis is paired with a prompting experiment. We systematically query Qwen3 (fixed local checkpoint) at three simulated expertise levels and with three types of methodological question, and classify each response into the same L3 taxonomy using Qwen. This gives us a direct estimate of what methods Qwen3 currently recommends. We then correlate recommendation frequency with the posterior mean gamma for each method. Critically, this comparison is made against **gamma specifically** — the excess share post-2023 above the pre-existing trend — rather than against raw method prevalence. This is what allows us to distinguish between two alternative explanations: the model recommending methods that were already trending before 2023 (reflecting its training data) versus recommending methods that accelerated specifically after LLM adoption (consistent with causal influence on research practice). If LLMs are driving convergence, the methods Qwen3 recommends most often should be the ones whose post-2023 share increased most in the published literature, after accounting for prior trajectories.

The model is validated through a four-stage Bayesian workflow following Gelman et al. (2020): prior predictive checks confirm the priors generate plausible diversity values; posterior predictive checks show 44 of 48 method groups are well-calibrated; fake-data simulation confirms sigma_gamma is identifiable through hierarchical aggregation across groups; and phi is estimated from data — the posterior concentrates at phi ≈ 596, confirming the field is compositionally regular.

## Preliminary Results

> **Note:** These are preliminary results. The bibliometric analysis (Steps 1 and 2) is complete; the prompting experiment (Step 3) is in progress. The full causal argument requires all three steps.

The analysis proceeds in three steps:

**Step 1 — Is there anomalous post-2023 methodological reshuffling?**

Weakly yes, but with wider uncertainty than earlier estimates. The global scale of post-2023 method-level change (sigma_gamma) is above zero, though the lower bound of the 90% CI is close to zero.

The model estimates phi from data using a weakly informative lognormal prior. In the primary L2→L3 analysis, phi ≈ 596 [302, 1131], confirming the field is compositionally regular — observed proportions track the structural trend closely year to year. sigma_gamma = 0.142 [0.021, 0.250].

The fit converged cleanly (Rhat < 1.001, ESS (sigma_gamma) = 664, zero divergences). sigma_gamma < sigma_beta (0.142 vs 0.204): the post-LLM reshuffling is smaller in magnitude than the long-run baseline trend.

Note: sigma_gamma measures the *magnitude* of reshuffling, not its direction. A sigma_gamma credibly above zero is necessary but not sufficient evidence for convergence toward generic methods.

**Step 2 — Is the reshuffling directionally consistent with LLM-driven convergence?**

Uncertain. No individual gamma estimates have a 90% CI that fully excludes zero — all directional claims are tentative. The top methods by posterior mean are reported below as directional indicators.

Methods gaining share post-2023 (positive gamma mean, all CIs cross zero):
- L3-024: Bayesian Panel Data Methods (+0.150)
- L3-101: Information-Theoretic Entropy Measures (+0.136)
- L3-009: Real-Time Object Detection (+0.135)
- L3-006: Partial Least Squares Variants (+0.131)
- L3-123: Generalized Linear Modeling (+0.130)

Methods losing share post-2023 (negative gamma mean, all CIs cross zero):
- L3-134: Logistic Regression Variants (−0.138)
- L3-103: Ecological Diversity Metrics (−0.125)
- L3-017: Kernel Methods and Matrix Factorization (−0.113)
- L3-109: Categorical Data Analysis (−0.110)
- L3-118: Hypothesis Testing Procedures (−0.107)

Individual estimates should be read as directional indicators, not precise effect sizes. The conservative prior on sigma_gamma and the breadth of the new taxonomy mean that individual method gammas are appropriately uncertain. The global reshuffling scale (sigma_gamma) remains the primary inferential target.

**Step 3 — Are the gaining methods the ones Qwen3 actually recommends? (in progress)**

The prompting experiment queries Qwen3 (fixed local checkpoint) at 3 expertise levels with 3 question types, classifies each response into the L3 taxonomy via Qwen, and correlates recommendation frequencies with posterior mean gamma per method. The comparison is specifically designed to test excess post-2023 share (gamma) rather than overall prevalence, thereby distinguishing LLM influence from mere reflection of pre-existing trends in training data.

The statistical test is a fully Bayesian Poisson regression (`stan/poisson_gamma_regression.stan`): `n_recommended_i ~ Poisson(exp(alpha + beta * |gamma_true_i|))`, where `gamma_true` is a latent variable with a Normal prior centred on the posterior summary from the main model. This propagates predictor uncertainty (from Stage 1) into the posterior of beta via sequential Bayesian updating. A positive beta — meaning methods with larger post-2023 deviation are recommended more often — closes the causal argument. The model is run separately for overall counts and for each expertise profile (novice/intermediate/expert) to test whether expertise modulates trend-chasing. See `experiment/` for the planned design and `R/06_step3_llm_comparison.R` for the analysis.

**What the results mean in plain terms**

In the 3–4 years since LLMs entered academic use, there is tentative evidence of methodological reshuffling in computational archaeology, though the signal is weaker than earlier estimates suggested. sigma_gamma = 0.142 [0.021, 0.250] is above zero but the lower bound is close to it, and no individual method shows a post-2023 shift credible at the 90% level. The magnitude of reshuffling is smaller than the long-run baseline trend (sigma_gamma < sigma_beta). Whether this pattern reflects LLM-driven convergence or other dynamics in the field remains to be established by Step 3.

## Analysis outputs

| Analysis | Description | Results |
|---|---|---|
| L2→L3 primary | Within each sub-discipline, specific technique shares over time | [View](docs/l2_l3_results.md) |
| L1→L2 sensitivity | Within each broad family, sub-discipline shares over time | [View](docs/l1_l2_results.md) |
| Bayesian workflow | Prior predictive, PPC, fake data recovery, phi sensitivity | [View](docs/workflow_results.md) |

## Repository structure

```
├── R/
│   ├── 00_data_prep.R          # Data loading & Stan data preparation
│   ├── 01_fit_model.R          # L2→L3 primary model (cmdstanr, phi-free)
│   ├── 02_extract_plot.R       # Extract posteriors & generate L2→L3 plots
│   ├── 03_l1_l2_analysis.R     # L1→L2 sensitivity analysis
│   ├── 04_workflow_checks.R    # Bayesian workflow validation
│   ├── 05_robustness_2022.R    # 2022-break robustness check
│   ├── 06_step3_llm_comparison.R  # LLM recommendation vs gamma
│   ├── inspect_gamma.R         # Quick gamma posterior inspection
│   └── archive/                # Deprecated scripts
├── stan/
│   ├── diversity_model_phi_free.stan       # Primary L2→L3 model
│   ├── l1_l2_diversity_model.stan          # L1→L2 fixed-phi model
│   ├── l1_l2_diversity_model_phi_free.stan # L1→L2 phi-free model
│   └── poisson_gamma_regression.stan       # Step 3 NB regression
├── data/
│   ├── input/
│   │   ├── taxonomy_v1/        # Original taxonomy data
│   │   └── taxonomy_v2/        # Current taxonomy (df_cleaned.xlsx)
│   └── output/
│       ├── figures/
│       │   ├── l2_l3/          # Primary L2→L3 analysis plots
│       │   ├── l1_l2/          # L1→L2 sensitivity plots
│       │   ├── workflow/       # Bayesian workflow check plots
│       │   ├── robustness/     # 2022-break robustness plots
│       │   └── step3/          # LLM comparison plots
│       ├── phi_free/           # Gamma results CSV
│       └── l2/                 # L1→L2 model fits
├── docs/
│   ├── l2_l3_results.md
│   ├── l1_l2_results.md
│   ├── workflow_results.md
│   └── archive/
└── experiment/
    ├── prompts/
    ├── responses/
    └── analysis/
```
