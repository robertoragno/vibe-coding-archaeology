# Step 3 Remapped — v2 Experiment → v3 Taxonomy

Script: `R/sensitivity/B_v2_taxonomy_remap.R`  
Run date: 2026-05-11

---

## What this does

The prompting experiment (Step 3) was run with the v2 taxonomy (225 L3 methods).
Taxonomy v3 has a different L3 vocabulary (242 methods with renamed labels).
Under direct matching, only 53/242 methods had recommendation data — too few
for a meaningful regression.

This script bridges the gap by mapping v2 L3 labels to v3 L3 labels using two
strategies:

1. **Prefix matching** (same L3 number, e.g. L3-009 → L3-009): 153 methods
2. **Exact match** (identical labels): 52 methods
3. **Fuzzy string match** (Jaro-Winkler distance, close): 0 methods
4. **Fuzzy string match** (distant, >0.15): 0 methods

After remapping, **205 / 242** v3 methods have recommendation data (85%).

The full mapping table is saved to `data/output/step3_v2_to_v3_mapping.csv`.

---

## Results

| Profile | β mean | 90% CI | P(β > 0) |
|---|---|---|---|
| Overall | -0.339 | [-1.874, 1.145] | 0.368 |
| Novice | -0.275 | [-1.793, 1.276] | 0.390 |
| Intermediate | -0.157 | [-1.685, 1.356] | 0.419 |
| Expert | -0.198 | [-1.760, 1.310] | 0.416 |

### Convergence

| Profile | Max Rhat | Min n_eff |
|---|---|---|
| Overall | 1.0028 | 3941 |
| Novice | 1.0007 | 3580 |
| Intermediate | 1.0051 | 3813 |
| Expert | 1.0024 | 3845 |

---

## Plots

### Overall β posterior

![Overall beta](../data/output/figures/step3_remapped/plot_beta_posterior_overall.png)

### β posterior by expertise profile

![Profile beta](../data/output/figures/step3_remapped/plot_beta_posterior_by_profile.png)

### γ vs. recommendation count

![Scatter](../data/output/figures/step3_remapped/plot_gamma_vs_recommendations.png)

### Top 20 recommended methods

![Top 20](../data/output/figures/step3_remapped/plot_top_recommended_direction.png)

---

## Interpretation

The remapping raised the match rate from 22% to 85%, recovering almost all of the experiment data. The results are consistent with the direct-match analysis: all β posteriors are negative with CIs crossing zero. The negative direction is not an artifact of the taxonomy mismatch — it persists with full coverage.

**What this means for Step 3:** The LLM (Qwen3) does not preferentially recommend the methods that gained share post-2023. If anything, it leans slightly toward methods that lost share, consistent with recommending from its training corpus (which reflects pre-2023 prevalence) rather than tracking recent shifts. The mean-collapse hypothesis — that LLMs drive convergence by recommending methods that are gaining share — is not supported by these data.

**What this means for the paper:** Steps 1–2 show weak evidence of post-2023 reshuffling (σ_γ = 0.110, above zero but uncertain). Step 3, with proper taxonomy matching, finds no link between that reshuffling and LLM recommendations. The three steps are not directionally aligned: some reshuffling exists, but LLMs are not driving it. The honest conclusion is that LLMs have not produced measurable methodological convergence in computational archaeology.
