# Prompting Experiment

## Purpose

The bibliometric analysis establishes whether methodological diversity in archaeology changed after 2023. This experiment asks whether LLMs are a plausible mechanism: do their method recommendations match the post-2023 shifts we observe in the literature?

For each L3 method, we have a posterior mean γ from the Stan model — a signed, quantified estimate of how much that method's share changed after 2023 relative to its pre-existing trend. The experiment produces a parallel dataset: how often each method is recommended by LLMs. We then correlate the two.

The underlying logic is that LLMs default to methods that are dominant in their training data regardless of user expertise level. If the methods LLMs recommend most frequently are precisely those that gained ground post-2023 in the literature, this supports the vibe-coding mechanism: researchers increasingly adopt LLM-default methods rather than domain-appropriate ones.

## Design

The experiment crosses three dimensions:

- **LLMs** (5–6 models): a mix of frontier models likely to be used by researchers in 2023–2025
- **Expertise levels** (3): prompts framed as coming from a novice (graduate student with no methods background), a practitioner (postdoc familiar with the domain and data), and an expert (senior researcher who uses precise methodological vocabulary and asks for justifications)
- **Question types** (3): open-ended, dataset-grounded, and comparative (see below)

This gives approximately 45–54 prompts per methodological domain, depending on final model selection. Domains are selected to cover the L2 groups with the largest γ variation in the L3 analysis.

### Question types

**Q1 — Open task** (`prompts/q1_open/`): the LLM is asked to recommend a method for a broadly described archaeological problem, with no data or alternatives specified. This elicits the model's unconditional default.

> *Novice:* "I'm an archaeology student and I want to analyze patterns in artifact distributions across sites. What should I use?"
> *Practitioner:* "I have a presence/absence matrix of ceramic types across 40 sites. What multivariate method would you recommend for identifying site clusters?"
> *Expert:* "For a Q-mode classification of assemblage composition data with Aitchison geometry, what are the current best-practice dimensionality reduction approaches?"

**Q2 — Dataset-grounded** (`prompts/q2_data/`): the LLM is given a concrete dataset description and asked to choose a method. This tests whether grounding the prompt in real data structure shifts recommendations away from defaults.

> *Novice:* "I have a spreadsheet with dates, site locations, and pottery counts. How do I find patterns?"
> *Practitioner:* "I have radiocarbon dates from 3 sites, lithic counts per stratigraphic unit, and GPS coordinates. I want to identify occupational phases."
> *Expert:* "I have a 200×15 compositional matrix (XRF data, ILR-transformed). I need to model provenance groupings accounting for within-group heteroscedasticity."

**Q3 — Comparative** (`prompts/q3_compare/`): the LLM is asked to choose between two named methods. This forces an explicit preference, directly revealing bias toward specific L3 techniques.

> *Novice:* "Is it better to use clustering or PCA to group archaeological sites?"
> *Practitioner:* "Should I use k-means or hierarchical clustering for ceramic typology? What are the trade-offs?"
> *Expert:* "For spatiotemporal modelling of settlement patterns, what are the relative merits of geographically weighted regression vs. Bayesian spatial CAR models?"

### Fixed design decisions

- **Language**: all prompts in English, for uniformity across models
- **Domain**: held constant within each prompt set (the subdomain varies across Q1/Q2/Q3 to maintain naturalness, but is drawn from the same L2 group)
- **Response format**: prompts request the top 3 methods as a ranked list, to simplify downstream L3 classification
- **Temperature**: 0 where supported, for reproducibility; models that do not expose temperature are run as-is and flagged

## Classification pipeline

Raw LLM responses are saved verbatim in `responses/`. Each response is then passed to Qwen with the same taxonomy prompt used to classify the original papers, producing an L3 method label for each recommendation. Classification scripts live in `analysis/`.

The output is a frequency table: for each (LLM, expertise level, question type, L3 method) combination, the number of times that method was recommended. This is aggregated to method-level recommendation frequencies and merged with the γ posteriors from `data/output/`.

## Output

The primary output is a scatter plot of posterior mean γ (x-axis) against LLM recommendation frequency (y-axis), with one point per L3 method. A positive correlation supports the hypothesis that LLMs reinforce the methods that gained disproportionate ground post-2023. 

Secondary outputs include breakdowns by:
- **LLM**: does the effect concentrate in certain models?
- **Expertise level**: does the LLM default converge regardless of how expert the framing is?
- **Question type**: does grounding the prompt in real data (Q2) shift recommendations relative to open elicitation (Q1)?

A flat expertise-level effect — where novice and expert prompts yield similar recommendation distributions — would be particularly strong evidence for the default-method mechanism.

## Folder structure

```
experiment/
├── prompts/
│   ├── q1_open/          # one file per expertise level
│   ├── q2_data/
│   └── q3_compare/
├── responses/            # raw outputs, named {model}_{level}_{qtype}_{domain}.txt
├── analysis/             # classification and correlation scripts
└── README.md
```
