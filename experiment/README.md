# Prompting Experiment

## Purpose

The bibliometric analysis establishes whether methodological diversity in archaeology changed after 2023. This experiment asks whether LLMs are a plausible mechanism: do their method recommendations match the post-2023 shifts we observe in the literature?

For each L3 method, we have a posterior mean gamma from the Stan model — a signed, quantified estimate of how much that method's share changed after 2023 relative to its pre-existing trend. The experiment produces a parallel dataset: how often each method is recommended by LLMs. We then correlate the two.

## Design

The experiment crosses three dimensions:

- **LLMs** (5-6 models): a mix of frontier models likely to be used by researchers in 2023-2025
- **Expertise levels** (3): prompts framed as coming from a graduate student, a postdoc, and a senior PI
- **Question types** (3): open-ended ("what methods should I use for X?"), comparative ("which is better, A or B?"), and task-specific ("I want to do X with Y data, how?")

This gives approximately 45-54 prompts per methodological domain, depending on final model selection. Domains are selected to cover the L2 groups with the largest gamma variation in the L3 analysis.

## Classification pipeline

Raw LLM responses are saved verbatim in `responses/`. Each response is then passed to Qwen with the same taxonomy prompt used to classify the original papers, producing an L3 method label for each recommendation. Classification scripts live in `analysis/`.

The output is a frequency table: for each (LLM, expertise level, question type, L3 method) combination, the number of times that method was recommended. This is aggregated to method-level recommendation frequencies and merged with the gamma posteriors from `data/output/`.

## Output

The primary output is a scatter plot of posterior mean gamma (x-axis) against LLM recommendation frequency (y-axis), with one point per L3 method. A positive correlation would support the hypothesis that LLMs are reinforcing the methods that gained ground post-2023. Secondary outputs include breakdowns by LLM, expertise level, and question type.

## Folder structure

- `prompts/` — prompt templates, one file per question type and expertise level
- `responses/` — raw LLM outputs, named by model, expertise level, question type, and domain
- `analysis/` — classification scripts and correlation analysis
