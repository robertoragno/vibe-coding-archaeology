# Step 3 Results — LLM Recommendation vs. Bayesian Gamma

Script: `R/06_step3_llm_comparison.R`  
Run date: 2026-04-24

---

## Experiment data summary

| Metric | Value |
|---|---|
| Raw rows in `experiment_results.csv` | 6,924 |
| Consistent L4 → L3 mappings used | 6,581 |
| L3 methods in vocabulary | 186 |
| L3 methods receiving ≥ 1 recommendation | 168 (90%) |

### Recommendations by profile

| Profile | Total recommendations | Distinct L3 methods covered |
|---|---|---|
| Novice | 2,303 | 109 |
| Intermediate | 2,110 | 126 |
| Expert | 2,168 | 158 |

The novice profile covers the fewest distinct methods (109 vs. 158 for expert), consistent with the mean-collapse hypothesis: less methodological guidance from the researcher leads to more concentrated LLM output.

---

## Top 10 most-recommended L3 methods

| L3 method | Total | Novice | Intermediate | Expert | Mean γ | sig90 |
|---|---|---|---|---|---|---|
| L3-173: Discrete Event & Agent Simulation | 566 | 268 | 219 | 79 | −0.079 | FALSE |
| L3-074: Network Structure Analysis | 467 | 259 | 137 | 71 | +0.100 | FALSE |
| L3-035: GIS Computational Analysis | 290 | 166 | 78 | 46 | −0.128 | FALSE |
| L3-076: Topic Modeling & Classification | 266 | 104 | 96 | 66 | −0.054 | FALSE |
| L3-138: Bayesian Computational Techniques | 260 | 42 | 92 | 126 | −0.003 | FALSE |
| L3-021: Spatial Pattern & Suitability Analysis | 178 | 73 | 70 | 35 | +0.332 | FALSE |
| L3-080: Unsupervised Clustering Algorithms | 177 | 25 | 70 | 82 | +0.049 | FALSE |
| L3-134: Geochemical Isotope & Elemental Modeling | 142 | 88 | 38 | 16 | −0.053 | FALSE |
| L3-111: Phylogenetic Inference & Reconstruction | 131 | 64 | 39 | 28 | +0.043 | FALSE |
| L3-176: Computational Simulation & Modeling | 124 | 36 | 51 | 37 | +0.032 | FALSE |

---

## Gamma and recommendation alignment

Positive-γ methods that are also among the most recommended (strongest mean-collapse candidates):

| L3 method | Mean γ | n_rec (total) |
|---|---|---|
| L3-021: Spatial Pattern & Suitability Analysis | +0.332 | 178 |
| L3-010: Image Segmentation Techniques | +0.167 | 87 |
| L3-003: Kernel Density Analysis | +0.129 | 70 |
| L3-020: Point Cloud Analysis and Registration | +0.127 | 67 |
| L3-046: Tree-Based Ensemble Learning | +0.105 | 64 |

*None of these individually reach sig90; the relationship is assessed jointly via the Bayesian Poisson regression (β coefficient).*

Only one L3 method reached sig90 = TRUE: **L3-178: Computational Analytical Methods** — γ = −0.475, n_rec = 6 (a declining method that is also rarely recommended).

---

## Bayesian Poisson regression (β posteriors)

*Numbers below are read from `data/output/step3_beta_summary.csv`, written automatically at the end of each script run. Re-run the script and ask me to update this section to refresh them.*

| Profile | β mean | P(β > 0) | Run date |
|---|---|---|---|
| — | — | — | — |

### Plot A — Overall β posterior

![Overall beta posterior](../data/output/plot_beta_posterior_overall.png)

### Plot B — β posterior by expertise profile

![Beta posterior by profile](../data/output/plot_beta_posterior_by_profile.png)

### Plot C — |γ| vs. LLM recommendation count

![Gamma vs recommendations scatter](../data/output/plot_gamma_vs_recommendations.png)

### Plot D — Top 20 recommended methods and their post-2023 direction

![Top recommended methods direction](../data/output/plot_top_recommended_direction.png)

---

## How to complete the results

Run the script from the project root:

```r
source("R/06_step3_llm_comparison.R")
```

Or from the terminal:

```bash
Rscript R/06_step3_llm_comparison.R
```

At the end of the run, the console prints:

```
=== Step 3 summary ===
Overall   beta: mean = X.XXX, P(beta>0) = X.XXX
Novice    beta: mean = X.XXX, P(beta>0) = X.XXX
Intermed. beta: mean = X.XXX, P(beta>0) = X.XXX
Expert    beta: mean = X.XXX, P(beta>0) = X.XXX

Top 5 most-recommended L3 methods:
...
```

Paste those numbers into the β posteriors section above. The Stan models run 4 chains × 2000 iterations each (4 models total), so expect roughly **5–10 minutes** on a multicore machine.
