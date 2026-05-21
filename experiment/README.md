# LLM Recommendation Simulation

## What this pipeline does

This pipeline tests whether the post-2023 reshuffling of computational methods identified by the Bayesian model is consistent with the recommendation behaviour of a large language model. The core idea is simple: if LLMs are driving archaeologists towards a narrower, more canonical set of methods, then asking an LLM to recommend computational approaches for a given archaeological problem should reproduce — or predict — the methods that gained share in the empirical corpus.

The pipeline simulates three types of researcher interacting with an LLM assistant. Each type brings a different degree of methodological prior knowledge to the conversation. The LLM's outputs — called L4 methods — are then mapped back onto the L3 taxonomy and compared to the gamma estimates from the Bayesian model.

---

## The mean-collapse hypothesis

The Bayesian model identified a set of methods gaining share post-2023 and a set losing share .The question this pipeline asks is: **are the methods gaining share precisely the ones an LLM recommends by default?**

LLMs are trained on the aggregate of the literature. When asked for a recommendation, they are expected to collapse towards the most statistically frequent and widely cited approaches — a phenomenon we call **mean collapse**. Mean collapse is not a failure; it is a structural property of how language models generalise. The hypothesis is that this property is now being transmitted to researchers who consult LLMs during study design, producing the convergence visible in sigma_gamma.

A key observable implication: mean collapse should be **stronger when the researcher provides less methodological guidance**. Profile C (novice, no method specified) should produce the most canonical recommendations; Profile A (expert, specific L2 provided) should constrain the LLM and produce more varied outputs. The difference between profiles is itself a test of the hypothesis.

---

## Input data

Three Excel files are loaded at runtime:

| File | Content |
|---|---|---|
| `L2.xlsx` | L2 sub-discipline labels from the existing taxonomy | |
| `Vague.xlsx` | Broad methodological families expressed in informal language |
| `Questions.xlsx` | Pre-defined archaeological research questions, one per thematic category |

The 28 research questions were constructed to cover the full thematic space of the SCOPUS corpus (all periods, all regions) and are **methodologically neutral** — they describe a substantive archaeological problem without implying any computational solution. This is essential for Profile C, where lexical priming from the question itself would confound the LLM's recommendation.

### Research questions by thematic category

| # | Category | Question |
|---|---|---|
| 1 | Artefacts / Finds | How do I classify and interpret a heterogeneous assemblage of artefacts recovered from an archaeological context? |
| 2 | Excavation / Survey report | How do I systematically document and communicate the results of an excavation or surface survey? |
| 3 | Architecture and other features | How do I analyse and interpret architectural structures or built features at a site? |
| 4 | Burials / Human remains | How do I study funerary practices and biological characteristics of a past population from skeletal remains? |
| 5 | Period / Tradition discussion | How do I characterise and compare material cultures from different periods or traditions to identify continuities and discontinuities? |
| 6 | Approaches / Theories / Methodology | How do I evaluate the effectiveness of a theoretical or methodological approach applied to a specific archaeological problem? |
| 7 | Site(s) discussion | How do I interpret the function, chronology, and overall significance of an archaeological site? |
| 8 | Art history / Iconography | How do I systematically analyse and interpret images, symbols, or figurative representations in an archaeological context? |
| 9 | Tablet find / Texts / Inscriptions / Philology | How do I extract historical and cultural information from a corpus of ancient epigraphic or textual sources? |
| 10 | Palaeoenvironment / Geoarchaeology / Geology | How do I reconstruct the environmental and geomorphological conditions in which past human activities took place? |
| 11 | Political / Economic / Social Organisation | How do I reconstruct the social, economic, or political structure of a community from material evidence? |
| 12 | Zooarchaeology | How do I analyse faunal remains to reconstruct hunting, herding practices, and human-animal relationships? |
| 13 | Resource exploitation / Manufacture / Technology | How do I reconstruct the chaîne opératoire and raw material processing techniques of past societies? |
| 14 | Ritual / Cult / Myths / Religion | How do I identify and interpret ritual or religious behaviour from material and contextual evidence? |
| 15 | Evental History / Historical Geography | How do I integrate written historical sources and material data to reconstruct past events and geographical transformations? |
| 16 | Subsistence economy / Food / Diet | How do I reconstruct the dietary and subsistence strategies of a past community? |
| 17 | Urban archaeology / Urbanism | How do I analyse the organisation, growth, and transformation of an ancient urban context? |
| 18 | Archaeometry | How do I determine the composition, provenance, or manufacturing techniques of an artefact through physicochemical analysis? |
| 19 | Chronology / Dating | How do I build a reliable chronological sequence when available dating evidence is uncertain or fragmentary? |
| 20 | History of archaeological research | How do I reconstruct the evolution of approaches and research interests within a discipline over time? |
| 21 | Landscape / Settlement / Territorial studies | How do I analyse the distribution and organisation of human settlements across a territory over the long term? |
| 22 | Archaeobotany / Palynology | How do I reconstruct past vegetation, plant use, and landscape change through botanical remains? |
| 23 | Textile / Textile tools | How do I analyse textile production and its economic and cultural significance in a past society? |
| 24 | Architectural decorations | How do I document, classify, and interpret architectural decorative programmes within a historical and cultural context? |
| 25 | Trade / Exchange / Interactions | How do I reconstruct exchange networks and cultural interaction between distant communities? |
| 26 | Heritage / Conservation | How do I assess, manage, and communicate the value of a cultural asset within a protection and risk framework? |
| 27 | Experimental archaeology / Ethnoarchaeology | How do I use comparisons with modern or experimental practices to interpret material evidence from the past? |
| 28 | Rock art | How do I document, classify, and interpret rock art manifestations within their spatial and cultural context? |

### Vague methodological families (Profile B)

These are **independent of the 28 questions** and represent the methodological axis of Profile B. They are sampled separately and combined with any question, including non-obvious pairings (e.g. *rock art + network analysis*), to test whether the LLM can bridge uncommon combinations or collapses to canonical defaults.

| Vague methodological family |
|---|
| "some kind of statistical or quantitative analysis" |
| "some kind of spatial or geographic approach" |
| "some kind of image or visual analysis" |
| "some kind of network or relational analysis" |
| "some kind of text or document analysis" |
| "some kind of dating or chronological modelling" |
| "some kind of 3D reconstruction or modelling" |
| "some kind of machine learning or pattern recognition" |
| "some kind of simulation or agent-based modelling" |

---

## Researcher profiles

The pipeline simulates three researcher profiles. The profiles differ in a single dimension: **how much methodological prior knowledge the researcher contributes to the prompt**. Everything else — the model, the system prompt, the output format instruction — is held constant across profiles.

### Profile A — Expert

The researcher specifies a concrete L2 method. The LLM is asked to recommend specific tools, algorithms, or variants within that method family. This profile constrains the LLM's output space and is expected to produce the most diverse L4 recommendations.

```
You are a research assistant for computational archaeologists.

A researcher comes to you with the following problem:

"I am working on: [QUESTION]
I already know I want to apply [L2 SPECIFIC METHOD] to my analysis.
Which specific tools, algorithms, or variants of this method would you
recommend, and how would you apply them concretely to this problem?"

List the computational methods you would use, being as specific as possible.
For each method, provide a one-sentence justification.
```

### Profile B — Intermediate

The researcher specifies a vague methodological family but no specific method. The LLM must choose both the method family and the specific technique. This profile produces partial constraint.

```
You are a research assistant for computational archaeologists.

A researcher comes to you with the following problem:

"I am working on: [QUESTION]
I have a rough idea that I need [VAGUE METHODOLOGICAL FAMILY],
but I do not know which specific method to choose.
What would you recommend?"

List the computational methods you would use, being as specific as possible.
For each method, provide a one-sentence justification.
```

### Profile C — Novice

The researcher provides only the archaeological problem. The LLM has full freedom to choose method family and specific technique. This profile is expected to produce the strongest mean collapse signal.

```
You are a research assistant for computational archaeologists.

A researcher comes to you with the following problem:

"I am working on: [QUESTION]
I have no specific computational background.
Which digital methods could I use to address this research problem?"

List the computational methods you would use, being as specific as possible.
For each method, provide a one-sentence justification.
```

---

## Sampling design

For each iteration, a single triplet `(question, L2, vague)` is sampled once and passed to all three profiles. This means the three profiles in a given iteration face the same archaeological problem, and differ only in how much methodological context they are given. The triplet is fixed across profiles to make profile comparisons valid.

```python
def sample_inputs():
    l2       = L2[l2_col].dropna().sample(1).values[0]
    vague    = VAGUE[vague_col].dropna().sample(1).values[0]
    question = QUESTIONS[question_col].dropna().sample(1).values[0]
    return l2, vague, question
```

The number of iterations should be sufficient to cover the full combinatorial space of questions × L2 methods. A minimum of 28 × n(L2) iterations is recommended to ensure each question appears with each L2 at least once.

---

## The models

The experiment is run with two local LLMs to test whether recommendation behaviour is model-specific or structural.

**Qwen3 (local instance).** The primary model. A local model is used for two reasons: (1) the number of iterations required makes API costs prohibitive; (2) a local model with a fixed checkpoint ensures reproducibility — the same prompt always produces the same output distribution.

**Gemma (local instance).** A second model from a different family (Google DeepMind) run with the identical pipeline, prompts, and sampling design. If both models produce the same concentration pattern despite different training corpora, the finding is more likely a structural property of LLMs in general rather than an artefact of one model's training data.

The system prompt is identical across all profiles, all iterations, and both models. Temperature is set to a low value to minimise stochastic variation and isolate the structural recommendation behaviour. The model version and training cutoff must be reported explicitly in any publication, as the mean collapse signal is model-specific and cutoff-dependent.

---

## Output structure — L4 methods

Each LLM response is parsed into a list of specific computational methods: these are the **L4 methods**. L4 is finer-grained than L3 — it names concrete tools, algorithms, or implementations rather than technique families.

Each L4 response item has the structure:

```
method_name | one-sentence justification
```

The justification is retained for two purposes: (1) to verify that the recommendation is archaeologically coherent rather than generic; (2) as a qualitative trace for post-hoc analysis of why the LLM recommended a given method.

---

## L4 → L3 mapping

Each L4 method is mapped back onto the existing L3 taxonomy by a second LLM call. The mapping prompt provides the full L3 taxonomy as context and asks the model to assign the single most appropriate L3 category to each L4 item. The mapping is run multiple times per L4 item to measure consistency; items with low cross-run agreement are flagged for manual review.

The mapping must be performed with the **same taxonomy** used in the original topic modelling pipeline to ensure that L4 frequencies are directly comparable to the L3 frequencies modelled in the Bayesian analysis.

### Taxonomy versions and the v2→v3 remapping

The L3 taxonomy was revised during the project. The v2 taxonomy had 225 methods; the v3 taxonomy has 242. Many method labels were renamed, split, or reorganised between versions. The Bayesian model on the literature corpus uses v3 throughout.

The early experiment run classified LLM responses against the v2 taxonomy. When compared to the v3-based Bayesian model, only 53/242 methods matched exactly — the remaining v2 labels had no direct v3 counterpart. Sensitivity B (`R/sensitivity/08_step3_v2_remapped.R`) tested whether fuzzy string matching to remap v2 labels onto v3 changed the Step 3 result; it did not (overall beta = -0.339, P(>0) = 0.368).

The current experiment data (`experiment_results_QWEN.csv`, `experiment_results_GEMMA.csv`) was reclassified directly against the v3 taxonomy, eliminating the mismatch entirely. The v2→v3 remapping is no longer needed for the primary analysis — it exists only as a sensitivity check confirming that the earlier taxonomy mismatch did not affect the qualitative result.

---

## Comparison with Bayesian results

Once L4 methods are mapped to L3, their frequency distribution across profiles is compared to the gamma estimates from the Bayesian model. The key comparison is:

- **Methods with high positive gamma** (gaining share post-2023) should appear more frequently in Profile C outputs than in Profile A outputs.
- **Methods with high negative gamma** (losing share post-2023) should appear less frequently or not at all in Profile C outputs.
- The **rank correlation** between LLM recommendation frequency (Profile C) and gamma estimates is the primary quantitative test of the mean-collapse hypothesis.

A secondary comparison examines whether the LLM introduces methods **not present** in the existing L3 taxonomy — i.e. whether the LLM goes beyond the corpus. Such methods would appear as unmappable L4 items and would constitute evidence against a purely circular explanation of the results.

---

## Limitations

**Circularity (partial).** The L2 methods used as Profile A inputs are drawn from the same taxonomy built from the corpus. This means Profile A partially asks the LLM to elaborate on methods it already knows from training. The circularity is intentional — it tests the depth of LLM knowledge within known categories — but it means Profile A results cannot be used to claim that LLMs *introduced* novel methods to the field. Profile C is the primary evidence for that claim.
