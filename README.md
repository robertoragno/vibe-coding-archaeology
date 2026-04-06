## Did LLMs cause convergence in computational archaeology methods?

Imagine that every graduate student in a department suddenly started asking the same AI assistant for methodological advice. The assistant, trained on the same corpus, would naturally recommend the same handful of techniques — not because those techniques are best, but because they are most represented in its training data. Over time, the department's research would start to look eerily similar. This paper asks whether something like that is happening across computational archaeology.

We assembled roughly 68,000 archaeology papers published between 2010 and 2025 and classified each one's methodology into a three-level taxonomy: broad families (L1), sub-disciplines (L2), and specific techniques (L3). The taxonomy was built with Qwen, a large language model, applied consistently to all abstracts. This gives us a record of how the methodological menu of the discipline has changed, year by year, at fine granularity.

The core question is whether that menu got more generic after 2023, the year ChatGPT entered serious academic use. Think of it like watching a restaurant's menu evolve over a decade, and then asking whether the dishes got blander — more convergent on a safe average — once the chef started relying on recipe apps rather than creative intuition.

We measure diversity within each L2 sub-discipline using the Inverse Simpson index, which counts the effective number of distinct L3 methods in use. A score of 1 means one technique dominates completely; higher scores mean methods are more evenly spread. We model how this effective count changes over time using a Bayesian Dirichlet-Multinomial regression fit with Stan.

The model has a two-slope structure. The first slope, beta, captures each method's underlying linear trajectory from 2010 to 2025: some techniques were already rising or falling before LLMs existed. The second slope, gamma, captures any additional deviation that began in 2023 and thereafter. By separating these two components, we can ask not just whether methods changed after 2023, but whether that change was over and above what the pre-existing trend would have predicted. The key estimand is sigma_gamma, the global scale of across-method variation in the post-2023 slope. If sigma_gamma is credibly above zero, there is real post-LLM heterogeneity in methodological trajectories — some methods accelerating, others declining — consistent with AI-driven recommendation effects.

We run this analysis twice. The primary analysis operates at the L2-to-L3 level: within each sub-discipline, we watch the fine-grained technique mix evolve. A complementary sensitivity analysis operates at the L1-to-L2 level: within each broad family, we watch the sub-discipline mix. If both levels tell a consistent story, the finding is robust.

The bibliometric analysis is paired with a planned prompting experiment. We will systematically query five or six major LLMs — at three simulated expertise levels and with three types of methodological question — and classify each response into the same L3 taxonomy using Qwen. This gives us a direct estimate of what methods LLMs currently recommend. We then correlate recommendation frequency with the posterior mean gamma for each method. If LLMs are driving convergence, the methods they recommend most often should be the ones whose post-2023 share increased most in the published literature.

The model is validated through a four-stage Bayesian workflow following Gelman et al. (2020): prior predictive checks confirm the priors generate plausible diversity values; posterior predictive checks show 44 of 48 method groups are well-calibrated; fake-data simulation confirms sigma_gamma is identifiable through hierarchical aggregation across groups; and a kappa sensitivity analysis tests whether the fixed concentration parameter drives the conclusions. An empirical kappa exploration in `00b_kappa_exploration.R` shows that kappa varies substantially across groups, with most groups having empirical kappa well above 10 — suggesting our primary analysis is conservative.

## Results

> [!WARNING]
> The models are still undergoing some changes. Results below are preliminary — you can already explore the outputs and read through the model logic, but treat the numbers as work-in-progress until this notice is removed.

| Analysis | Description | Results |
|---|---|---|
| L1 → L2 | Sensitivity check. Within each broad methodological family (L1), we track how sub-discipline (L2) shares evolve over time. Tests whether the post-LLM signal is consistent at a coarser taxonomic level. | [View L2 results](docs/l2_results.md) |
| L2 → L3 | Primary analysis. Within each sub-discipline (L2), we track how specific technique (L3) shares evolve. The main estimand is whether technique-level diversity changed after 2023. | [View L3 results](docs/l3_results.md) |
| Workflow checks | Prior predictive, PPC, fake data recovery, kappa sensitivity — four-stage validation following Gelman et al. (2020). | [View workflow results](docs/workflow_results.md) |

## Repository structure

```
.
├── R/
│   ├── 00_data_prep.R          # Ingest raw CSVs, build taxonomy vocab, write Stan inputs
│   ├── 00b_kappa_exploration.R # Exploratory: empirical kappa calibration and overdispersion plots
│   ├── 01_fit_model.R          # Compile and sample the Stan model
│   ├── 02_extract_plot.R       # Extract posterior draws, produce L3 plots, push results
│   ├── 03_l2_analysis.R        # L1→L2 sensitivity analysis (inline Stan, own plots)
│   └── 04_workflow_checks.R    # Bayesian workflow checks: prior predictive, PPC, fake data, sensitivity
├── stan/
│   └── diversity_model.stan    # Dirichlet-Multinomial two-slope model
├── data/
│   ├── output/
│   │   ├── l3/                 # Plots from the primary L2→L3 analysis
│   │   ├── l2/                 # Plots from the L1→L2 sensitivity check
│   │   └── workflow/           # Plots from the Bayesian workflow checks
│   └── ...                     # Raw and intermediate data files
├── docs/
│   ├── l3_results.md           # Auto-updated L3 diagnostics and results
│   ├── l2_results.md           # Auto-updated L2 diagnostics and results
│   └── workflow_results.md     # Auto-updated Bayesian workflow check results
└── experiment/
    ├── prompts/                 # Prompt templates for querying LLMs
    ├── responses/               # Raw LLM responses
    └── classify/                # Scripts to classify responses into L3 taxonomy
```

Scripts are run in order from the project root: `00` → `00b` → `01` → `02` → `03` → `04`.
