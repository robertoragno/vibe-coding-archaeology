# Main text figures and tables

Figure and table inventory for "(Whose defaults?) Is artificial intelligence
reorienting archaeological methods?", in order of appearance.

Numbering matches the manuscript. **Fig. 1** is the LLM-word-frequency plot,
produced by `Python/5_llm_words/llm_word_trends.py`. **Figs. 2–7** are produced
by `R/09_main_text_figures.R` in greyscale at 300 DPI. **Table 3** is set in the
manuscript text (Tables 1 and 2 are the taxonomy and the profile prompts).
Two supplementary figures are listed at the end.

---

## Fig. 1 — Frequency of LLM-typical words in archaeological literature

**Section:** Introduction

**File:** `data/output/figures/llm_words/llm_word_trends.png`

**What it shows:** Occurrences per 10,000 words of 25 marker words characteristic
of LLM-generated text, across roughly 120,000 Scopus abstracts (2010–2025). A
vertical dashed line marks the release of ChatGPT in November 2022.

**Manuscript caption:** Frequency of LLM-typical words in archaeological
literature (2010–2025), as occurrences per 10,000 words across approximately
120,000 Scopus abstracts. The tracked vocabulary is 25 marker words identified as
characteristic of LLM-generated text. The vertical dashed line marks the release
of ChatGPT in November 2022.

---

## Fig. 2 — Raw method counts over time

**Section:** Methods 3.2 / Results 4.1

**File:** `data/output/figures/main_text/fig2_raw_counts.png`

**What it shows:** Observed paper counts for the 15 most frequent L3 methods,
by year (2010–2025), with the post-2023 boundary marked and a non-parametric
trend ribbon per method.

**Results:** Strong heterogeneity across the top 15 methods. Several show steep
post-2020 growth (feedforward and recurrent neural networks, automated content
classification, k-means clustering); others plateau or decline (geometric
morphometrics, multivariate statistical analysis). The 2023 boundary marks no
visible inflection in the raw data.

**Manuscript caption:** Raw counts of the 15 most frequent L3 methods in the
bibliometric corpus, by year (2010–2025). The dashed vertical line marks the
2023 post-LLM boundary.

---

## Fig. 3 — Sigma posteriors: baseline trend versus post-LLM shift

**Section:** Results 4.1

**File:** `data/output/figures/main_text/fig3_sigma_posteriors.png`

**What it shows:** Posterior densities of the two scale parameters of the
Dirichlet-Multinomial model: sigma_beta, the across-method spread of pre-2023
linear trends, and sigma_gamma, the across-method spread of post-2023 level
shifts.

**Results:** sigma_beta = 0.249 [90% CI 0.210, 0.289]. sigma_gamma = 0.106
[90% CI 0.010, 0.219], with the entire posterior mass above zero. Post-2023
shifts are unevenly distributed across methods, at roughly one third the
magnitude of the baseline trend variation.

**Manuscript caption:** Posterior densities of the two Dirichlet-Multinomial
scale parameters: sigma_beta, the across-method spread of pre-2023 linear trends,
and sigma_gamma, the across-method spread of post-2023 level shifts. The
sigma_gamma posterior lies entirely above zero.

---

## Fig. 4 — Method share by L2 sub-discipline: literature versus both LLMs

**Section:** Results 4.2

**File:** `data/output/figures/main_text/fig4_l2_triple_bar.png`

**What it shows:** Horizontal bar chart of method shares across the 24 L2
categories for four sources: pre-2023 literature, post-2023 literature, Qwen3
recommendations, and Gemma recommendations.

**Results:** Both LLMs over-represent a few L2 categories (network analysis,
agent-based simulation, machine-learning methods) and under-represent the long
tail of specialist techniques (isotope analysis, archaeobotany, faunal
analysis). The literature distribution is far more even, and post-2023 shares
sit close to pre-2023 shares for most categories. Qwen3 and Gemma show similar
concentration patterns.

**Manuscript caption:** Method shares across the 24 L2 sub-disciplines,
comparing Qwen3 and Gemma recommendations with pre- and post-2023 literature.

---

## Fig. 5 — Top 10 L3 methods: Qwen3 versus Gemma

**Section:** Results 4.2

**File:** `data/output/figures/main_text/fig5_top10_qwen_vs_gemma.png`

**What it shows:** Union of each model's ten most-recommended L3 methods, as a
share of that model's total recommendations. Each bar is labelled with the
method's post-2023 literature trajectory (gamma from the Dirichlet-Multinomial
model).

**Results:** High agreement between the two models. Network analysis and
modelling leads both (around 10% share each) despite a declining literature
trajectory. Rank ordering is largely preserved across architectures; Gemma
allocates slightly more to GIS modelling and to multivariate statistical and
machine-learning methods, Qwen3 more to discrete and agent-based simulation.
Top picks include both gaining and declining methods.

**Manuscript caption:** The ten most-recommended L3 methods for each model, as a
share of that model's total recommendations (the union of the two top-ten
lists). The value beside each bar is the method's estimated post-2023 trajectory
in the literature (gamma from the bibliometric Dirichlet-Multinomial model,
§3.3): positive values indicate methods gaining share, negative values methods
declining relative to their pre-2023 trend.

---

## Table 3 — Effective number of methods: literature versus LLM profiles

**Section:** Results 4.3 / Methods 3.4.1

**Format:** Table. It replaces a figure because the message is the size of the
gap between conditions, not the shape of any one distribution.

**What it shows:** Effective number of methods (inverse Simpson index) for each
source, from a Dirichlet conjugate posterior. Each estimate is the posterior
median with 90% credible interval.

> Numbers from the 2025 refit (2010–2025 window).

| Source | Profile | Median | 90% CI |
|--------|---------|-------:|--------|
| Literature pre-2023 | — | 87.6 | [84.6, 90.6] |
| Literature post-2023 | — | 111.2 | [107.7, 114.7] |
| Qwen3 | Novice | 20.9 | [19.5, 22.4] |
| Qwen3 | Intermediate | 30.5 | [28.3, 33.0] |
| Qwen3 | Expert | 60.7 | [56.8, 64.7] |
| Qwen3 | Overall | 31.6 | [30.2, 33.0] |
| Gemma | Novice | 20.5 | [19.0, 21.9] |
| Gemma | Intermediate | 29.5 | [27.3, 31.7] |
| Gemma | Expert | 46.8 | [43.4, 50.2] |
| Gemma | Overall | 28.8 | [27.6, 30.0] |

**Manuscript caption:** Effective number of L3 methods (inverse Simpson index)
for the pre- and post-2023 literature and for the Qwen3 and Gemma recommendation
sets, broken down by researcher profile for the LLM sources. Each value is the
posterior median with 90% credible interval, computed from a Dirichlet conjugate
posterior fitted to the L3 frequency counts of each source (§3.4.1). Higher
values indicate recommendations spread more evenly across methods; lower values
indicate concentration on a few.

---

## Fig. 6 — What predicts LLM method choices

**Section:** Results 4.4 / Methods 3.4.2

**File:** `data/output/figures/main_text/fig6_bpre_bgamma_posteriors.png`

**What it shows:** Posteriors for the two predictors of a negative binomial
regression on recommendation counts. beta_pre weights log1p of the pre-2023
literature count, a proxy for training-corpus prevalence. beta_gamma weights
each method's posterior gamma, its post-2023 excess growth above baseline trend.
Results for Qwen3 and Gemma, pooled across profiles.

**Results:** beta_pre is credibly positive for both models: Qwen3 = 0.657
[90% CI 0.509, 0.806], Gemma = 0.576 [0.400, 0.751]. Methods more common in the
pre-2023 literature are recommended more often. beta_gamma is centred near zero
for both: Qwen3 = 0.115 [-1.391, 1.701], Gemma = 0.191 [-1.354, 1.759]. The
concentration documented in Table 3 tracks training-corpus prevalence, not
post-2023 momentum.

**Manuscript caption:** Posterior distributions from a two-predictor count
regression testing what drives LLM method recommendations. beta_pre measures how
strongly a method's pre-2023 prevalence in the literature predicts how often it
is recommended; beta_gamma measures whether methods that gained momentum after
2023 are recommended more often. Results shown for both Qwen3 and Gemma; see the
figure legend for the zero line, the credible-interval bands, and the posterior
mean.

---

## Fig. 7 — Post-2023 effect by expertise profile

**Section:** Results 4.4

**File:** `data/output/figures/main_text/fig7_bgamma_by_profile.png`

**What it shows:** beta_gamma posteriors for Qwen3 and Gemma under the novice,
intermediate, expert, and pooled profiles.

**Results:** beta_gamma stays centred near zero across every profile and model:
novice (Qwen3 0.089, Gemma 0.131), intermediate (Qwen3 0.070, Gemma 0.098),
expert (Qwen3 0.212, Gemma 0.235). All 90% credible intervals span zero. The
per-technique gamma values feeding the regression are individually small, so a
null was the expected outcome regardless of the underlying truth; Sensitivity C
(ESM §S11.4) addresses the same question without depending on those values.

**Manuscript caption:** Posterior distributions of beta_gamma, the post-2023
momentum coefficient in the negative binomial regression, for Qwen3 and Gemma
under the novice, intermediate, expert, and pooled profiles. All 90% credible
intervals span zero. Point: posterior mean; thick bar: 50% credible interval;
thin bar: 90% credible interval; dashed line: zero.

---

## Supplementary figures (ESM)

Two figures only. The ESM is otherwise table-driven: every quantitative result
is reported in a supplementary table, and these two are included because the
interval overlap and the per-method spread cannot be read from a table.

| Figure | ESM section | File | Contents |
|--------|-------------|------|----------|
| Fig. S7.1 | §S7.6 | `data/output/figures/l2_l3/esm_gamma_top20.png` | Posterior gamma for the 20 L3 methods with the largest posterior mean absolute gamma, with 90% credible intervals. Every interval covers zero; backs the statement that no method's shift is individually credible. Built by `R/bibliometric/03_esm_gamma_topn.R` from `gamma_results.csv` (the full 241-method dotplot is a 36-inch strip and unusable in the PDF). |
| Fig. S9.1 | §S9.2 | `data/output/figures/main_text/esm_concentration_posteriors.png` | Posterior distributions of the effective number of L3 methods by condition. Backs the non-overlap of literature and LLM intervals and the novice < intermediate < expert ordering. |

Both are staged for Overleaf upload in `data/output/ESM figures/` as
`esm_gamma_top20.png` and `esm_concentration_posteriors.png`.

Next candidates, if review asks for a visual: the negative binomial posteriors by
profile (`data/output/figures/prevalence_gamma/plot_bpre_bgamma_by_profile.png`)
for §S10.2, and the posterior predictive check
(`data/output/figures/workflow/plot_ppc_pvalues.png`) for §S8.2.
