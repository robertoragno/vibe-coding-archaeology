
import re
import ast
import glob
import json as _json
import os
import gc
import pandas as pd
import numpy as np
from collections import Counter, defaultdict
from thefuzz import fuzz
from sklearn.cluster import AgglomerativeClustering
from sklearn.neighbors import NearestCentroid
from evoc import EVoC
from llama_cpp import Llama
from tqdm import tqdm

# ============================================================
# CONFIG
# ============================================================
INPUT_CSV     = "vibe-coding-archaeology/Python/2_methods_extractions/qwen_method_results_gguf.csv"
OUTPUT_CSV    = "taxonomy_results.csv"
JOIN_CSV      = "taxonomy_abstract_join.csv"
DESC_JSON     = "taxonomy_descriptions.json"
LABEL_CACHE   = "taxonomy_labels_cache.json"
EMB_CACHE     = "taxonomy_embeddings_cache.npy"
CANON_CACHE   = "taxonomy_canonical_cache.txt"

FUZZY_THRESHOLD      = 88
EVOC_MAX_LAYERS      = 12
EVOC_MIN_CLUSTER_SIZE = 5
SEMANTIC_MERGE_THR   = 0.98   


L2_TAXONOMY = {
    # ── Statistics & Modeling ────────────────────────────────────────────
    "Univariate & Classical Hypothesis Testing": (
        "Classical frequentist tests for comparing groups or distributions on a single "
        "variable, forming the baseline of inferential statistics before multivariate "
        "and computational methods. "
        "Examples: t-test, Mann-Whitney U, Chi-square, ANOVA, Kruskal-Wallis, "
        "Kolmogorov-Smirnov, Fisher's Exact Test, Wilcoxon Signed-Rank."
    ),
    "Multivariate Analysis & Dimensionality Reduction": (
        "Techniques that reduce or decompose high-dimensional datasets into lower-dimensional "
        "representations, including ordination, matrix factorization and manifold learning. "
        "Examples: PCA, Correspondence Analysis, MDS, t-SNE, Procrustes Analysis, "
        "Nonlinear Manifold Learning, Factor Analysis."
    ),
    "Regression & Generalized Linear Models": (
        "Parametric models that quantify relationships between a response variable and one or "
        "more predictors, including linear, logistic, Poisson and mixture variants. "
        "Examples: OLS Regression, GLM, GAM, Logistic Regression, Mixture Modeling, "
        "Generalized Additive Models."
    ),
    "Clustering & Unsupervised Learning": (
        "Algorithms that partition unlabelled data into groups based on similarity, without "
        "prior class definitions. "
        "Examples: k-means, Hierarchical Clustering, DBSCAN, HDBSCAN, Gaussian Mixture Models, "
        "Self-Organizing Maps."
    ),
    "Distance & Similarity Metrics": (
        "Mathematical measures of dissimilarity or proximity between observations or features, "
        "used as building blocks for classification, clustering and retrieval. "
        "Examples: Mahalanobis Distance, Nearest Neighbor Analysis, Relief Algorithms, "
        "Cluster Validation Indices, Jaccard Similarity, Edit Distance."
    ),
    "Bayesian & Probabilistic Inference": (
        "Frameworks that combine prior knowledge with observed data via Bayes' theorem to "
        "produce posterior distributions, including MCMC sampling and hierarchical models. "
        "Examples: MCMC, Metropolis-Hastings, Gibbs Sampling, Hierarchical Bayesian Models, "
        "Bayesian Networks, Belief Propagation."
    ),
    "Time Series & Sequence Analysis": (
        "Methods for analysing ordered temporal or sequential data, including autocorrelation, "
        "spectral analysis and dynamic time warping. "
        "Examples: Autocorrelation, Fourier Analysis, Wavelet Transform, DTW, "
        "Sequence Alignment, ARIMA."
    ),
    "Chronological Modelling & Dating": (
        "Computational approaches for estimating or calibrating the age of archaeological "
        "materials and events, integrating multiple dating evidence. "
        "Examples: Bayesian Radiocarbon Calibration (OxCal), OSL Modelling, "
        "Dendrochronology Calibration, Seriation, Stratigraphic Modelling."
    ),

    # ── Space & Territory ──────────────────────────────────────────────────
    "Spatial Statistics & Point Pattern Analysis": (
        "Statistical methods that account for the geographic location of observations, "
        "detecting spatial dependence, clustering and interpolation. "
        "Examples: Ripley's K, Kernel Density Estimation, Kriging, Spatial Autocorrelation "
        "(Moran's I), Geographically Weighted Regression."
    ),
    "GIS & Landscape Analysis": (
        "Geographic Information Systems tools and spatial modelling techniques for analysing "
        "site distributions, movement corridors and territory in landscape contexts. "
        "Examples: Viewshed Analysis, Least-Cost Path, Site Catchment Analysis, "
        "Digital Elevation Models, Terrain Morphometry."
    ),
    "Remote Sensing & Satellite Imagery": (
        "Processing and interpretation of multispectral, hyperspectral or radar imagery "
        "acquired from satellites or aircraft to detect and map archaeological features. "
        "Examples: Multispectral Classification, SAR Analysis, NDVI, "
        "Change Detection, Image Segmentation from Satellite."
    ),
    "Geophysical Prospection": (
        "Near-surface geophysical methods used to detect buried archaeological structures "
        "without excavation, including electromagnetic and seismic techniques. "
        "Examples: Ground-Penetrating Radar (GPR), Magnetometry, Electrical Resistivity "
        "Tomography (ERT), Seismic Refraction, Electromagnetic Induction."
    ),

    # ── 3D & Image ────────────────────────────────────────────────────────
    "Photogrammetry & 3D Reconstruction": (
        "Computational methods that derive accurate 3D geometry from overlapping photographs "
        "or structured light, producing point clouds and meshes. "
        "Examples: Structure-from-Motion (SfM), Multi-View Stereo (MVS), "
        "Terrestrial Laser Scanning, Mesh Processing, Point Cloud Registration."
    ),
    "Geometric Morphometrics": (
        "Quantitative methods for capturing and analysing shape variation in biological or "
        "artefact outlines and landmark configurations. "
        "Examples: Landmark-Based Morphometrics, Elliptic Fourier Analysis, "
        "Thin-Plate Splines, Procrustes Superimposition, Outline Analysis."
    ),
    "Computer Vision & Image Processing": (
        "Algorithmic techniques for extracting information from digital images, including "
        "segmentation, feature detection and texture analysis applied to archaeological material. "
        "Examples: Edge Detection, Texture Classification, Template Matching, "
        "Histogram Analysis, Image Segmentation, Colour Analysis."
    ),

    # ── ML & AI ──────────────────────────────────────────────────────────────
    "Machine Learning & Supervised Classification": (
        "Statistical learning algorithms trained on labelled examples to classify or predict "
        "outcomes, using hand-crafted features rather than end-to-end learning. "
        "Examples: Support Vector Machines (SVM), Random Forests, Gradient Boosting, "
        "Decision Trees, k-Nearest Neighbours, Naive Bayes."
    ),
    "Deep Learning & Neural Networks": (
        "Multi-layer artificial neural network architectures that learn hierarchical "
        "representations directly from raw data such as images, sequences or point clouds. "
        "Examples: Convolutional Neural Networks (CNN), Recurrent Neural Networks (RNN), "
        "Transformers, Transfer Learning, Autoencoders, Generative Adversarial Networks."
    ),
    "NLP & Text Mining": (
        "Computational methods for extracting structured information and patterns from "
        "unstructured textual sources, including ancient corpora and modern literature. "
        "Examples: Named Entity Recognition, Topic Modelling, Word Embeddings, "
        "Large Language Models (LLM), Corpus Analysis, Optical Character Recognition."
    ),

    # ── Material Analysis ─────────────────────────────────────────────────────
    "Archaeometry & Compositional Analysis": (
        "Physico-chemical analytical methods paired with statistical processing to characterise "
        "the elemental or mineralogical composition of artefacts and raw materials. "
        "Examples: X-Ray Fluorescence (XRF/pXRF), Raman Spectroscopy, FTIR, "
        "Neutron Activation Analysis (NAA), ICP-MS, Electron Microprobe."
    ),
    "Isotope & Bioarchaeological Analysis": (
        "Computational processing of stable or radiogenic isotope ratios and ancient biomolecular "
        "data to reconstruct diet, mobility, kinship and population history. "
        "Examples: Strontium Isotope Analysis, δ13C / δ15N, aDNA Analysis, "
        "Proteomics, Isotope Mixing Models, Zooarchaeological Morphometry."
    ),
    "Geoarchaeology & Sediment Analysis": (
        "Quantitative methods applied to sediment, soil and micromorphological data to "
        "reconstruct depositional histories and palaeoenvironments. "
        "Examples: Granulometry, Micromorphometry, Geochemical Profiling, "
        "Magnetic Susceptibility, Phytolith Analysis."
    ),

    # ── Simulation & Networks ───────────────────────────────────────────────────
    "Agent-Based Modelling & Simulation": (
        "Computational simulations in which autonomous agents interact according to defined "
        "rules, used to model social dynamics, land use and demographic change. "
        "Examples: Agent-Based Models (ABM), Cellular Automata, "
        "System Dynamics, Demographic Modelling, Monte Carlo Simulation."
    ),
    "Network Analysis & Graph Theory": (
        "Methods derived from graph theory to study relationships and flows among entities "
        "such as sites, individuals, trade goods or ideas. "
        "Examples: Social Network Analysis, Centrality Measures, Community Detection, "
        "Exchange Network Modelling, Minimum Spanning Trees."
    ),
    "Ecological & Palaeoenvironmental Modelling": (
        "Quantitative models that reconstruct past environments or predict species/site "
        "distributions by combining proxy data with environmental variables. "
        "Examples: Species Distribution Models (SDM), Palynological Modelling, "
        "Climate Reconstruction, MaxEnt, Predictive Site Modelling."
    ),

    # ── Data & Communication ─────────────────────────────────────────────────
    "Visualization & Scientific Communication": (
        "Computational methods and tools for representing archaeological data visually to "
        "support analysis, interpretation and public dissemination. "
        "Examples: Scientific Cartography, 3D Visualization, Dashboards, "
        "Infographics, Virtual Reality (VR/AR), Interactive Web Maps."
    ),
}

L2_INDEX = {name: i for i, name in enumerate(L2_TAXONOMY.keys())}

# ============================================================
# Phase 0 — CSV Extraction of raw terms
# ============================================================
print("=" * 60)
print("Phase 0 — CSV Extraction of raw terms")
print("=" * 60)

df_raw = pd.read_csv(INPUT_CSV)
df_raw.dropna(subset=["computational_methods"], inplace=True)

raw_methods = []
for val in df_raw["computational_methods"].dropna():
    try:
        parsed = ast.literal_eval(val)
        if isinstance(parsed, list):
            for item in parsed:
                for method in str(item).split("|"):
                    raw_methods.append(method.strip())
        else:
            for method in str(parsed).split("|"):
                raw_methods.append(method.strip())
    except (ValueError, SyntaxError):
        for method in str(val).split("|"):
            raw_methods.append(method.strip())

raw_counter = Counter(raw_methods)
unique_raw = sorted(set(raw_methods))
print(f"  Termini grezzi totali: {len(raw_methods)}")
print(f"  Termini unici grezzi:  {len(unique_raw)}")

# ============================================================
# Phase 1 — Text Normalization
# ============================================================
print("\n" + "=" * 60)
print("Phase 1 — Text Normalization")
print("=" * 60)

SPELLING_MAP = {
    r"\b3-D\b": "3D", r"\b2-D\b": "2D",
    r"modelling": "modeling", r"colour": "color",
    r"digitisation": "digitization", r"characterisation": "characterization",
    r"organisation": "organization", r"optimisation": "optimization",
    r"visualisation": "visualization", r"normalisation": "normalization",
    r"categorisation": "categorization", r"parametrisation": "parameterization",
    r"utilisation": "utilization", r"minimisation": "minimization",
    r"maximisation": "maximization", r"synchronisation": "synchronization",
    r"localisation": "localization", r"serialisation": "serialization",
    r"generalisation": "generalization", r"specialisation": "specialization",
    r"regularisation": "regularization", r"analyse\b": "analysis",
    r"analyses\b": "analysis", r"neighbour\b": "neighbor",
    r"neighbours\b": "neighbors", r"grey\b": "gray",
    r"centre\b": "center", r"fibre\b": "fiber",
    r"programme\b": "program",
}


def normalize_term(text: str) -> str:
    t = str(text).strip()
    if not t:
        return t
    for pattern, replacement in SPELLING_MAP.items():
        t = re.sub(pattern, replacement, t, flags=re.IGNORECASE)
    t = re.sub(r"(?<=[A-Za-z]{3})-(?=[A-Za-z]{3})", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    words = t.split()
    result = []
    for w in words:
        if w.isupper() and len(w) >= 2:
            result.append(w)
        elif re.match(r"^[a-z]-", w):
            result.append(w)
        else:
            result.append(w.capitalize())
    t = " ".join(result)
    t = re.sub(r"\b([A-Z][a-z]{3,})s\b", r"\1", t)
    return t


norm_map = {term: normalize_term(term) for term in unique_raw}
norm_counter = Counter()
for term, count in raw_counter.items():
    norm_counter[norm_map[term]] += count
unique_norm = sorted(set(norm_map.values()))
print(f"  Unique normalized terms: {len(unique_norm)} (from {len(unique_raw)})")

# ============================================================
# Phase 2 — Fuzzy Deduplication
# ============================================================
print("\n" + "=" * 60)
print(f"Phase 2 — Fuzzy Deduplication (threshold={FUZZY_THRESHOLD})")
print("=" * 60)


def fuzzy_cluster(terms: list, threshold: int = 88) -> dict:
    remaining = sorted(terms, key=lambda x: -norm_counter.get(x, 0))
    clusters = {}
    assigned = set()
    for term in tqdm(remaining, desc="  Fuzzy matching"):
        if term in assigned:
            continue
        cluster = [term]
        assigned.add(term)
        for other in remaining:
            if other in assigned:
                continue
            if fuzz.token_sort_ratio(term.lower(), other.lower()) >= threshold:
                cluster.append(other)
                assigned.add(other)
        canonical = max(cluster, key=lambda x: norm_counter.get(x, 0))
        clusters[canonical] = cluster
    return clusters


fuzzy_groups = fuzzy_cluster(unique_norm, FUZZY_THRESHOLD)
norm_to_canonical = {}
for canonical, variants in fuzzy_groups.items():
    for v in variants:
        norm_to_canonical[v] = canonical

canonical_terms = sorted(fuzzy_groups.keys())
canonical_counter = Counter()
for norm, canon in norm_to_canonical.items():
    canonical_counter[canon] += norm_counter.get(norm, 0)

print(f"  Canonical terms: {len(canonical_terms)} (from {len(unique_norm)})")
multi = {k: v for k, v in fuzzy_groups.items() if len(v) > 1}
print(f"  Clusters with variants: {len(multi)}")
for canon, variants in sorted(multi.items(), key=lambda x: -len(x[1]))[:10]:
    print(f"    '{canon}' ← {variants}")

# ============================================================
# Phase 3 — Embedding + EVoC → cluster L3
# ============================================================
print("\n" + "=" * 60)
print("Phase 3 — Semantic Embedding + EVoC (cluster L3)")
print("=" * 60)

gguf_files = glob.glob("*Embedding*.gguf")
if not gguf_files:
    raise FileNotFoundError("No GGUF model for embedding found.")
GGUF_MODEL = gguf_files[0]
print(f"  Embedding model: {GGUF_MODEL}")

llm_emb = Llama(
    model_path=GGUF_MODEL,
    n_gpu_layers=-1,
    embedding=True,
    n_ctx=512,
    verbose=False,
    random_seed=42,
)

INSTRUCTION = (
    "Represent this computational method for grouping by its specific algorithmic "
    "paradigm and technique family, ignoring application domain: "
)


def embed_terms(terms: list, batch_size: int = 32) -> np.ndarray:
    all_embeddings = []
    for i in tqdm(range(0, len(terms), batch_size), desc="  Embedding"):
        batch = terms[i: i + batch_size]
        for t in batch:
            out = llm_emb.create_embedding(INSTRUCTION + t)
            all_embeddings.append(out["data"][0]["embedding"])
    return np.array(all_embeddings, dtype=np.float32)


# Cache embedding
cache_valid = False
if os.path.exists(EMB_CACHE) and os.path.exists(CANON_CACHE):
    with open(CANON_CACHE) as f:
        cached_terms = [l.strip() for l in f]
    if cached_terms == canonical_terms:
        print(f"  Cache valid. Loading from {EMB_CACHE}...")
        embeddings = np.load(EMB_CACHE)
        cache_valid = True

if not cache_valid:
    print(f"  Computing embeddings for {len(canonical_terms)} terms...")
    embeddings = embed_terms(canonical_terms)
    np.save(EMB_CACHE, embeddings)
    with open(CANON_CACHE, "w") as f:
        f.write("\n".join(canonical_terms))
    print("  Cache saved.")

print(f"  Shape embedding: {embeddings.shape}")

# EVoC clustering → L3
print(f"  EVoC clustering (max_layers={EVOC_MAX_LAYERS}, "
      f"base_min_cluster_size={EVOC_MIN_CLUSTER_SIZE})...")
evoc = EVoC(
    base_min_cluster_size=EVOC_MIN_CLUSTER_SIZE,
    max_layers=EVOC_MAX_LAYERS,
    random_state=42,
)
evoc.fit(embeddings)

layers = evoc.cluster_layers_
print(f"  Available EVoC layers: {len(layers)}")
for i, layer in enumerate(layers):
    n_cls = len(np.unique(layer[layer >= 0]))
    n_noise = int((layer == -1).sum())
    print(f"    Layer {i:2d}: {n_cls:4d} cluster | {n_noise:4d} noise")

# L3 = layer 0 (most fine-grained)
labels_l3_raw = np.array(layers[0])


def reassign_noise(labels_raw, emb):
    labels = np.array(labels_raw, dtype=np.int32)
    noise_mask = labels == -1
    if noise_mask.sum() == 0:
        return labels
    nc = NearestCentroid()
    assigned = ~noise_mask
    nc.fit(emb[assigned], labels[assigned])
    labels[noise_mask] = nc.predict(emb[noise_mask])
    return labels


def compact_ids(labels_arr):
    unique_ids = sorted(set(labels_arr))
    remap = {old: new for new, old in enumerate(unique_ids)}
    return np.array([remap[v] for v in labels_arr], dtype=np.int32)


labels_l3 = compact_ids(reassign_noise(labels_l3_raw, embeddings))
n_l3 = len(set(labels_l3))
print(f"  L3 clusters: {n_l3}")

# Centroids L3
l3_centroids = {}
for cid in sorted(set(labels_l3)):
    mask = labels_l3 == cid
    l3_centroids[cid] = embeddings[mask].mean(axis=0)


def get_cluster_members(terms, labels, counter):
    cluster_map = defaultdict(list)
    for term, label in zip(terms, labels):
        cluster_map[label].append(term)
    for cid in cluster_map:
        cluster_map[cid].sort(key=lambda x: -counter.get(x, 0))
    return cluster_map


l3_members = get_cluster_members(canonical_terms, labels_l3, canonical_counter)

print(f"\n  Semantic merge L3 pre-labeling (threshold={SEMANTIC_MERGE_THR})...")
from sklearn.metrics.pairwise import cosine_similarity


def semantic_merge_l3(l3_to_parent, centroids_map, threshold):
    parent_to_l3 = defaultdict(list)
    for l3, pid in l3_to_parent.items():
        parent_to_l3[pid].append(l3)

    merged_count = 0
    changed = True
    while changed:
        changed = False
        pids = sorted(parent_to_l3.keys())
        if len(pids) <= 2:
            break
        cent_list = np.array([centroids_map[p] for p in pids])
        sim = cosine_similarity(cent_list)
        np.fill_diagonal(sim, 0.0)
        i_max, j_max = np.unravel_index(sim.argmax(), sim.shape)
        if sim[i_max, j_max] >= threshold:
            pid_a, pid_b = pids[i_max], pids[j_max]
            if len(parent_to_l3[pid_a]) >= len(parent_to_l3[pid_b]):
                survivor, absorbed = pid_a, pid_b
            else:
                survivor, absorbed = pid_b, pid_a
            parent_to_l3[survivor].extend(parent_to_l3.pop(absorbed))
            all_vecs = np.array([centroids_map[c] for c in parent_to_l3[survivor]])
            centroids_map[survivor] = all_vecs.mean(axis=0)
            changed = True
            merged_count += 1

    pid_remap = {old: new for new, old in enumerate(sorted(parent_to_l3.keys()))}
    new_mapping = {}
    for pid, l3_list in parent_to_l3.items():
        for l3 in l3_list:
            new_mapping[l3] = pid_remap[pid]
    print(f"    Merges executed: {merged_count} → L3 remaining: {len(parent_to_l3)}")
    return new_mapping


# L3 with identity mapping (each L3 is a "child" of itself as parent)
l3_self_map = {cid: cid for cid in l3_centroids}
l3_self_map = semantic_merge_l3(l3_self_map, l3_centroids, SEMANTIC_MERGE_THR)

# Rebuild L3 labels and centroids after merge
labels_l3 = compact_ids(np.array([l3_self_map[int(l)] for l in labels_l3]))
l3_centroids = {}
for cid in sorted(set(labels_l3)):
    mask = labels_l3 == cid
    l3_centroids[cid] = embeddings[mask].mean(axis=0)
l3_members = get_cluster_members(canonical_terms, labels_l3, canonical_counter)
n_l3 = len(set(labels_l3))
print(f"  L3 clusters after semantic merge: {n_l3}")

# Download generative model for labeling and assignment
print("\n  Downloading embedding model...")
del llm_emb
gc.collect()

gen_model_path = "../Qwen3.5-9B-Q8_0.gguf"
print(f"  Loading generative model: {gen_model_path}")
llm_gen = Llama(
    model_path=gen_model_path,
    n_gpu_layers=-1,
    n_ctx=2048 * 2,
    verbose=False,
    random_seed=42,
)

# ============================================================
# Phase 4 — Auto-labeling L3 using LLM
# ============================================================
print("\n" + "=" * 60)
print("Phase 4 — Auto-labeling L3")
print("=" * 60)


def generate_l3_label(member_terms: list) -> tuple[str, str]:
    sample = ", ".join(member_terms[:30])
    if len(member_terms) > 30:
        sample += f" ... (+{len(member_terms) - 30} more)"
    user_msg = (
        f"These computational method terms form a fine-grained cluster:\n{sample}\n\n"
        f"Provide:\n"
        f"1. A SINGLE short label (2-5 words) naming the specific technique family.\n"
        f"   GOOD: 'Convolutional Neural Networks', 'Bayesian Radiocarbon Calibration', "
        f"'Elliptic Fourier Analysis'.\n"
        f"   FORBIDDEN: generic terms like 'Methods', 'Techniques', 'Analysis', "
        f"or compound labels joining two families with '&', '/' or 'and'.\n"
        f"2. A concise description (1-2 sentences) of what specific techniques are grouped here.\n\n"
        f"Reply ONLY with valid JSON: {{\"label\": \"...\", \"description\": \"...\"}}"
    )
    messages = [
        {"role": "system", "content": (
            "You are a taxonomy expert for computational methods. "
            "Reply ONLY with valid JSON with fields 'label' and 'description'."
        )},
        {"role": "user", "content": user_msg},
    ]
    out = llm_gen.create_chat_completion(messages, max_tokens=150, temperature=0.1)
    raw = out["choices"][0]["message"]["content"].strip()
    label, desc = "", ""
    try:
        m = re.search(r'\{[^{}]*"label"[^{}]*"description"[^{}]*\}', raw, re.DOTALL)
        parsed = _json.loads(m.group() if m else raw)
        label = str(parsed.get("label", "")).strip()
        desc = str(parsed.get("description", "")).strip()
    except Exception:
        label = raw[:60]
    for prefix in ["Label:", "label:", "**", "##"]:
        if label.lower().startswith(prefix.lower()):
            label = label[len(prefix):].strip()
    label = label.replace("**", "").strip()
    return label, desc


l3_names, l3_descriptions = {}, {}
label_cache = {}
if os.path.exists(LABEL_CACHE):
    with open(LABEL_CACHE) as f:
        label_cache = _json.load(f)
    l3_names = {int(k): v for k, v in label_cache.get("l3", {}).items()}
    l3_descriptions = {int(k): v for k, v in label_cache.get("l3_descriptions", {}).items()}
    if set(l3_names.keys()) == set(l3_members.keys()):
        print("Valid Cache label L3 , skip generation.")
    else:
        print("  Cache label L3 not valid (clusters changed). Will regenerate.")
        l3_names, l3_descriptions = {}, {}

if not l3_names:
    print(f"  Generation label for {n_l3} L3 clusters...")
    for cid in tqdm(sorted(l3_members.keys()), desc="  L3 labels"):
        label, desc = generate_l3_label(l3_members[cid])
        l3_names[cid] = label
        l3_descriptions[cid] = desc

# ============================================================
# Phase 4.5 — Garbage validation
# ============================================================
print("\n" + "=" * 60)
print("Phase 4.5 — Garbage validation")
print("=" * 60)


def is_cluster_garbage(l3_label: str, member_terms: list) -> bool:
    sample = ", ".join(member_terms[:40])
    if len(member_terms) > 40:
        sample += f" ... (+{len(member_terms) - 40} more)"
    user_msg = (
        f"L3 cluster:\n"
        f"  Label: '{l3_label}'\n"
        f"  Members: {sample}\n\n"
        f"Does this cluster contain a SIGNIFICANT PROPORTION of terms that are NOT "
        f"computational/statistical/analytical methods?\n\n"
        f"Reply ONLY with valid JSON: {{\"garbage\": false}} or {{\"garbage\": true}}"
    )
    messages = [
        {"role": "system", "content": (
            "You are a garbage detector for taxonomy clusters of computational methods. "
            "Mark garbage=TRUE only if a notable share of the members are NOT scientific "
            "methods — for example: generic words (Integration, Comparison, Control, Part, "
            "Match, Zoom, Buffer), software product names, non-analytical activities "
            "(Interview, Trial Excavation), or completely unrelated jargon mixed together "
            "with no coherent methodological theme. "
            "Mark garbage=FALSE if the members are mostly real scientific methods, even if "
            "the cluster is broad, contains many terms, spans multiple sub-fields, or has "
            "a generic-sounding label. "
            "Examples of NOT garbage: 'Kernel Density Estimation', 'Support Vector Machine "
            "Variants', 'Statistical Hypothesis Testing', 'Multivariate Statistical Methods', "
            "'Audio Signal Processing', 'Redundancy Analysis'. "
            "When in doubt, reply garbage=false. "
            "Reply ONLY with valid JSON."
        )},
        {"role": "user", "content": user_msg},
    ]
    out = llm_gen.create_chat_completion(messages, max_tokens=20, temperature=0.0)
    raw = out["choices"][0]["message"]["content"].strip()
    try:
        m = re.search(r'\{[^{}]*"garbage"[^{}]*\}', raw, re.DOTALL)
        parsed = _json.loads(m.group() if m else raw)
        return bool(parsed.get("garbage", False))
    except Exception:
        return False  # fallback: assume non-garbage if parsing fails


GARBAGE_CACHE = "taxonomy_garbage_cache.json"
garbage_l3_ids: set = set()
cached_garbage: dict = {}

if os.path.exists(GARBAGE_CACHE):
    with open(GARBAGE_CACHE) as f:
        cached_garbage = _json.load(f)
    if set(int(k) for k in cached_garbage.keys()) == set(l3_members.keys()):
        print("  Cache garbage valid. Loading results...")
        garbage_l3_ids = {int(k) for k, v in cached_garbage.items() if v}
    else:
        print("  Cache garbage not valid (clusters changed). Will revalidate.")
        cached_garbage = {}

if not cached_garbage:
    print(f"  Generation of garbage labels for {n_l3} L3 clusters...")
    all_garbage: dict = {}
    for cid in tqdm(sorted(l3_members.keys()), desc="  Garbage check"):
        label = l3_names.get(cid, "?")
        result = is_cluster_garbage(label, l3_members[cid])
        all_garbage[str(cid)] = result
        if result:
            print(f"    [GARBAGE] L3-{cid:03d}: '{label}' ({len(l3_members[cid])})")
    with open(GARBAGE_CACHE, "w") as f:
        _json.dump(all_garbage, f, indent=2)
    garbage_l3_ids = {int(k) for k, v in all_garbage.items() if v}

n_garbage_clusters = len(garbage_l3_ids)
n_garbage_terms = sum(len(l3_members.get(cid, [])) for cid in garbage_l3_ids)
print(f"  Cluster garbage: {n_garbage_clusters} / {n_l3} "
      f"({n_garbage_terms}")

# ============================================================
# Phase 5 — L3 → L2 Assignment using LLM with fixed taxonomy
# ============================================================
print("\n" + "=" * 60)
print("Phase 5 — L3 → L2 Assignment (fixed taxonomy)")
print("=" * 60)

L2_CATALOG = "\n".join(
    f"[{i}] {name}\n     {desc}"
    for i, (name, desc) in enumerate(L2_TAXONOMY.items())
)
L2_NAMES_LIST = list(L2_TAXONOMY.keys())


def assign_l3_to_l2(l3_label: str, l3_terms: list) -> int:

    sample = ", ".join(l3_terms[:25])
    if len(l3_terms) > 25:
        sample += f" ... (+{len(l3_terms) - 25} more)"

    user_msg = (
        f"You are classifying computational methods used in archaeology into a fixed taxonomy.\n\n"
        f"L3 cluster to classify:\n"
        f"  Label: '{l3_label}'\n"
        f"  Terms: {sample}\n\n"
        f"Available L2 categories (choose exactly ONE):\n{L2_CATALOG}\n\n"
        f"Instructions:\n"
        f"  - Choose the category whose description BEST matches the methodological paradigm "
        f"of the L3 cluster, not the archaeological application.\n"
        f"  - Focus on the algorithmic/statistical nature of the methods, not on what they "
        f"are applied to (e.g. ceramics, sites, texts).\n"
        f"  - If uncertain between two categories, prefer the more specific one.\n\n"
        f"Reply ONLY with valid JSON: {{\"l2_index\": <number in brackets above>}}"
    )
    messages = [
        {"role": "system", "content": (
            "You are a taxonomy expert for computational methods in archaeology. "
            "Reply ONLY with valid JSON: {\"l2_index\": N} where N is the number "
            "in brackets from the category list."
        )},
        {"role": "user", "content": user_msg},
    ]
    out = llm_gen.create_chat_completion(messages, max_tokens=20, temperature=0.0)
    raw = out["choices"][0]["message"]["content"].strip()
    try:
        m = re.search(r'\{[^{}]*"l2_index"[^{}]*\}', raw, re.DOTALL)
        parsed = _json.loads(m.group() if m else raw)
        idx = int(parsed.get("l2_index", 0))
        if 0 <= idx < len(L2_NAMES_LIST):
            return idx
    except Exception:
        pass
    for n in re.findall(r'\b(\d+)\b', raw):
        idx = int(n)
        if 0 <= idx < len(L2_NAMES_LIST):
            return idx
    return -1


ASSIGN_CACHE = "taxonomy_l3_l2_assignments.json"
l3_to_l2_idx: dict[int, int] = {}  # l3_id → indice L2

if os.path.exists(ASSIGN_CACHE):
    with open(ASSIGN_CACHE) as f:
        raw_cache = _json.load(f)
    cached_assignments = {int(k): v for k, v in raw_cache.items()}
    if set(cached_assignments.keys()) == set(l3_members.keys()):
        print("  Cache assignments valid. Loading results...")
        l3_to_l2_idx = cached_assignments
    else:
        print("  Cache assignments not valid. Reclassifying...")

if not l3_to_l2_idx:
    print(f"  Classifying {n_l3} L3 clusters into {len(L2_NAMES_LIST)} L2 categories...")
    for cid in tqdm(sorted(l3_members.keys()), desc="  L3→L2 assignment"):
        l3_label = l3_names.get(cid, "Unknown")
        l3_terms = l3_members[cid]
        idx = assign_l3_to_l2(l3_label, l3_terms)
        l3_to_l2_idx[cid] = idx
        print(f"    L3-{cid:03d} '{l3_label}' → [{idx:02d}] {L2_NAMES_LIST[idx]}")

    with open(ASSIGN_CACHE, "w") as f:
        _json.dump({str(k): v for k, v in l3_to_l2_idx.items()}, f, indent=2)
    print(f"  Cache assignments saved.")

# ============================================================
# Phase 6 — Audit: check anomalous assignments
# ============================================================
print("\n" + "=" * 60)
print("PHASE 6 — Audit of Anomalous Assignments")
print("=" * 60)


def review_l3_assignment(l3_id: int, l3_label: str, l3_terms: list,
                          current_l2_idx: int, n_votes: int = 3) -> int:

    if current_l2_idx == -1:
        return -1
    current_l2_name = L2_NAMES_LIST[current_l2_idx]
    current_l2_desc = L2_TAXONOMY[current_l2_name]
    sample = ", ".join(l3_terms[:20])

    user_msg = (
        f"Audit task: verify the placement of a computational methods cluster.\n\n"
        f"L3 cluster:\n"
        f"  Label: '{l3_label}'\n"
        f"  Terms: {sample}\n\n"
        f"Currently assigned to L2 [{current_l2_idx}] '{current_l2_name}':\n"
        f"  {current_l2_desc}\n\n"
        f"Is this assignment correct?\n"
        f"- If YES → reply {{\"correct\": true}}\n"
        f"- If NO, and the current category is COMPLETELY UNRELATED to the cluster's "
        f"methodology → reply {{\"correct\": false, \"better_l2_index\": <N>}}\n\n"
        f"All L2 categories for reference:\n{L2_CATALOG}\n\n"
        f"Reply ONLY with valid JSON."
    )
    messages = [
        {"role": "system", "content": (
            "You are a conservative taxonomy auditor for computational methods in archaeology. "
            "Your default answer is {\"correct\": true}. "
            "Only flag a misplacement when the current category is COMPLETELY UNRELATED "
            "to the cluster's core methodology — not because another category seems "
            "marginally or equally good. If the current assignment is plausible or "
            "defensible from any reasonable angle, reply correct=true. "
            "When in doubt, reply correct=true. "
            "Reply ONLY with valid JSON."
        )},
        {"role": "user", "content": user_msg},
    ]

    votes = []
    for _ in range(n_votes):
        out = llm_gen.create_chat_completion(messages, max_tokens=30, temperature=0.3)
        raw = out["choices"][0]["message"]["content"].strip()
        try:
            m = re.search(r'\{[^{}]*"correct"[^{}]*\}', raw, re.DOTALL)
            parsed = _json.loads(m.group() if m else raw)
            if bool(parsed.get("correct", True)):
                votes.append(current_l2_idx)
            else:
                better = int(parsed.get("better_l2_index", current_l2_idx))
                votes.append(better if 0 <= better < len(L2_NAMES_LIST) else current_l2_idx)
        except Exception:
            votes.append(current_l2_idx)

    if len(set(votes)) == 1 and votes[0] != current_l2_idx:
        return votes[0]
    return current_l2_idx


print(f"  Review of {n_l3} L3→L2 assignments (triple confirmation, unanimity required)...")
corrections = 0
for cid in tqdm(sorted(l3_members.keys()), desc="  L3 review"):
    current_idx = l3_to_l2_idx[cid]
    new_idx = review_l3_assignment(
        cid, l3_names.get(cid, "?"), l3_members[cid], current_idx
    )
    if new_idx != current_idx:
        old_name = L2_NAMES_LIST[current_idx]
        new_name = L2_NAMES_LIST[new_idx]
        print(f"    L3-{cid:03d} '{l3_names.get(cid, '?')}': "
              f"[{current_idx:02d}] '{old_name}' → [{new_idx:02d}] '{new_name}'")
        l3_to_l2_idx[cid] = new_idx
        corrections += 1

print(f"  Corrections applied: {corrections}")

with open(ASSIGN_CACHE, "w") as f:
    _json.dump({str(k): v for k, v in l3_to_l2_idx.items()}, f, indent=2)

label_cache_out = {
    "l3": {str(k): v for k, v in l3_names.items()},
    "l3_descriptions": {str(k): v for k, v in l3_descriptions.items()},
}
with open(LABEL_CACHE, "w") as f:
    _json.dump(label_cache_out, f, indent=2, ensure_ascii=False)

del llm_gen
gc.collect()

# ============================================================
# Taxonomy Preview: print L2 categories with their L3 children and sample terms
# ============================================================
print("\n--- TAXONOMY PREVIEW (L2 → L3) ---")

# Raggruppa L3 per L2
l2_to_l3_map = defaultdict(list)
for l3_id, l2_idx in l3_to_l2_idx.items():
    if l2_idx >= 0:
        l2_to_l3_map[l2_idx].append(l3_id)
uncategorized_l3 = [cid for cid, idx in l3_to_l2_idx.items() if idx == -1]
if uncategorized_l3:
    print(f"  [ERROR] L3 not categorized (idx=-1): {uncategorized_l3}")

for l2_idx, l2_name in enumerate(L2_NAMES_LIST):
    l3_children = sorted(l2_to_l3_map.get(l2_idx, []))
    n_terms = sum(len(l3_members.get(c, [])) for c in l3_children)
    print(f"\n  L2-{l2_idx:02d}: {l2_name} ({len(l3_children)} L3, {n_terms} termini)")
    for l3_id in l3_children[:5]:
        n3 = len(l3_members.get(l3_id, []))
        print(f"    L3-{l3_id:03d}: {l3_names.get(l3_id, '?')} ({n3} termini)")
    if len(l3_children) > 5:
        print(f"    ... +{len(l3_children) - 5} altri L3")

empty_l2 = [name for i, name in enumerate(L2_NAMES_LIST) if i not in l2_to_l3_map]
if empty_l2:
    print(f"\n  [WARN] Categories without L3: {empty_l2}")

# ============================================================
# OUTPUT
# ============================================================
print("\n" + "=" * 60)
print("OUTPUT — Build CSV")
print("=" * 60)


canonical_to_idx = {term: i for i, term in enumerate(canonical_terms)}


def lookup_taxonomy(orig_term: str) -> dict:
    norm = norm_map.get(orig_term, normalize_term(orig_term))
    canon = norm_to_canonical.get(norm, norm)
    if canon in canonical_to_idx:
        idx = canonical_to_idx[canon]
        l3_id = int(labels_l3[idx])
        is_garbage = l3_id in garbage_l3_ids
        l2_idx = l3_to_l2_idx.get(l3_id, -1)
        if l2_idx == -1:
            return {
                "canonical": canon,
                "l2_index": -1,
                "level_2": "Uncategorized",
                "level_2_description": "",
                "l3_id": l3_id,
                "level_3": f"L3-{l3_id:03d}: {l3_names.get(l3_id, '?')}",
                "level_3_description": l3_descriptions.get(l3_id, ""),
                "is_garbage": is_garbage,
            }
        l2_name = L2_NAMES_LIST[l2_idx]
        l2_desc = L2_TAXONOMY[l2_name]
        l3_name = l3_names.get(l3_id, "Uncategorized")
        l3_desc = l3_descriptions.get(l3_id, "")
        return {
            "canonical": canon,
            "l2_index": l2_idx,
            "level_2": f"L2-{l2_idx:02d}: {l2_name}",
            "level_2_description": l2_desc,
            "l3_id": l3_id,
            "level_3": f"L3-{l3_id:03d}: {l3_name}",
            "level_3_description": l3_desc,
            "is_garbage": is_garbage,
        }
    return {
        "canonical": canon,
        "l2_index": -1,
        "level_2": "Uncategorized",
        "level_2_description": "",
        "l3_id": -1,
        "level_3": "Uncategorized",
        "level_3_description": "",
        "is_garbage": False,
    }


rows = []
for orig_term in unique_raw:
    tax = lookup_taxonomy(orig_term)
    rows.append({
        "original_term": orig_term,
        "normalized": norm_map.get(orig_term, orig_term),
        "canonical": tax["canonical"],
        "frequency": raw_counter[orig_term],
        "is_garbage": tax["is_garbage"],
        "level_2": tax["level_2"],
        "level_2_description": tax["level_2_description"],
        "level_3": tax["level_3"],
        "level_3_description": tax["level_3_description"],
    })

df_out = pd.DataFrame(rows)
df_out.sort_values(["level_2", "level_3", "canonical", "original_term"], inplace=True)
df_out = df_out[[
    "original_term", "normalized", "canonical", "frequency", "is_garbage",
    "level_2", "level_2_description",
    "level_3", "level_3_description",
]]
df_out.to_csv(OUTPUT_CSV, index=False, encoding="utf-8")
print(f"  Saved: {OUTPUT_CSV}  ({len(df_out)} rows)")

join_rows = []
for _, row in df_raw.iterrows():
    eid = row["eid"]
    val = row["computational_methods"]
    if pd.isna(val):
        continue
    try:
        parsed = ast.literal_eval(val)
        terms_in_abstract = []
        if isinstance(parsed, list):
            for item in parsed:
                for m in str(item).split("|"):
                    terms_in_abstract.append(m.strip())
        else:
            for m in str(parsed).split("|"):
                terms_in_abstract.append(m.strip())
    except (ValueError, SyntaxError):
        terms_in_abstract = [m.strip() for m in str(val).split("|")]

    seen = set()
    for term in terms_in_abstract:
        tax = lookup_taxonomy(term)
        canon = tax["canonical"]
        if canon in seen:
            continue
        seen.add(canon)
        join_rows.append({
            "eid": eid,
            "canonical": canon,
            "is_garbage": tax["is_garbage"],
            "level_2": tax["level_2"],
            "level_2_description": tax["level_2_description"],
            "level_3": tax["level_3"],
            "level_3_description": tax["level_3_description"],
        })

df_join = pd.DataFrame(join_rows)
df_join.sort_values(["eid", "level_2", "level_3"], inplace=True)
df_join.to_csv(JOIN_CSV, index=False, encoding="utf-8")
print(f"  Saved: {JOIN_CSV}  "
      f"({len(df_join)} rows, {df_join['eid'].nunique()} abstract)")

desc_export = {}
for l2_idx, l2_name in enumerate(L2_NAMES_LIST):
    l3_children = sorted(l2_to_l3_map.get(l2_idx, []))
    if not l3_children:
        continue
    l2_key = f"L2-{l2_idx:02d}: {l2_name}"
    all_l2_terms = []
    for c in l3_children:
        all_l2_terms.extend(l3_members.get(c, []))
    all_l2_terms = sorted(set(all_l2_terms), key=lambda x: -canonical_counter.get(x, 0))

    desc_export[l2_key] = {
        "description": L2_TAXONOMY[l2_name],
        "members_sample": all_l2_terms[:15],
        "children": {}
    }
    for l3_id in l3_children:
        l3_key = f"L3-{l3_id:03d}: {l3_names.get(l3_id, '?')}"
        desc_export[l2_key]["children"][l3_key] = {
            "description": l3_descriptions.get(l3_id, ""),
            "members": l3_members.get(l3_id, []),
            "is_garbage": l3_id in garbage_l3_ids,
        }

with open(DESC_JSON, "w", encoding="utf-8") as f:
    _json.dump(desc_export, f, indent=2, ensure_ascii=False)
print(f"  Saved: {DESC_JSON}")

# ============================================================
# Final Report
# ============================================================
print("\n" + "=" * 60)
print("FINAL REPORT")
print("=" * 60)
print(f"  Original terms:      {len(unique_raw)}")
print(f"  After normalization:   {len(unique_norm)}")
print(f"  After fuzzy dedup:       {len(canonical_terms)}")
print(f"  Cluster L3 garbage:     {n_garbage_clusters} ({n_garbage_terms} terms)")
print(f"  Categories L2 (fixed):   {len(L2_TAXONOMY)}")
print(f"  Cluster L3 (discovered):  {n_l3}")
print(f"  L2 with at least one L3:    {len(l2_to_l3_map)}")
print(f"  Empty L2:               {len(empty_l2)}")

print("\n--- DISTRIBUTION L2 ---")
l2_term_counts = []
for l2_idx, l2_name in enumerate(L2_NAMES_LIST):
    l3_children = l2_to_l3_map.get(l2_idx, [])
    n_terms = sum(len(l3_members.get(c, [])) for c in l3_children)
    n_l3_here = len(l3_children)
    l2_term_counts.append((l2_name, n_l3_here, n_terms))

for name, n_l3_here, n_terms in sorted(l2_term_counts, key=lambda x: -x[2]):
    bar = "█" * min(40, n_terms // max(1, max(x[2] for x in l2_term_counts) // 40))
    print(f"  [{L2_INDEX[name]:02d}] {name:<55s} L3={n_l3_here:3d}  terms={n_terms:4d}  {bar}")

print("\Done!")