"""
LLM Recommendation Simulation — full pipeline
==============================================
Simulates three researcher profiles (Expert / Intermediate / Novice) querying
a local Qwen 9-B model for computational-method recommendations on 28
archaeological research questions.  Each LLM response is parsed into L4
methods, which are then mapped back onto the L3 taxonomy by a second LLM call
(run N_MAPPING_RUNS times for consistency checking).

Usage
-----
    python run_experiment.py [N_ITERATIONS]

    N_ITERATIONS  – total sampling iterations (default 252 = 28 × 9).
                    Each iteration samples one (question, L2, vague) triplet
                    and queries all three profiles, so the total number of
                    LLM generation calls is N_ITERATIONS × 3 (plus mapping).
"""

import os
import sys
import glob
import json
import re
import random
import pandas as pd
from llama_cpp import Llama
from tqdm import tqdm

# ─── CONFIGURATION ────────────────────────────────────────────────────────────

TAXONOMY_CSV    = "/mnt/ssd_lavoro/LAB_AI_PC/AI_abstract/taxonomy/taxonomy_results.csv"
RESULTS_FILE    = os.path.join(os.path.dirname(__file__), 'experiment_results.csv')
INPUTS_DIR      = os.path.dirname(__file__)          # where L2/Vague/Questions.xlsx live

#N_ITERATIONS    = int(sys.argv[1]) if len(sys.argv) > 1 else 252
N_ITERATIONS    = 252    # total sampling iterations (one question + L2 + vague triplet per iteration)
N_MAPPING_RUNS  = 3      # consistency check runs per L4 item
TEMPERATURE     = 0.1
MAX_TOKENS_GEN  = 1024   # generation call
MAX_TOKENS_MAP  = 128    # mapping call (only returns a code)

# ─── HARDCODED INPUT DATA (from experiment.md) ────────────────────────────────

QUESTIONS_DATA = [
    "How do I classify and interpret a heterogeneous assemblage of artefacts recovered from an archaeological context?",
    "How do I systematically document and communicate the results of an excavation or surface survey?",
    "How do I analyse and interpret architectural structures or built features at a site?",
    "How do I study funerary practices and biological characteristics of a past population from skeletal remains?",
    "How do I characterise and compare material cultures from different periods or traditions to identify continuities and discontinuities?",
    "How do I evaluate the effectiveness of a theoretical or methodological approach applied to a specific archaeological problem?",
    "How do I interpret the function, chronology, and overall significance of an archaeological site?",
    "How do I systematically analyse and interpret images, symbols, or figurative representations in an archaeological context?",
    "How do I extract historical and cultural information from a corpus of ancient epigraphic or textual sources?",
    "How do I reconstruct the environmental and geomorphological conditions in which past human activities took place?",
    "How do I reconstruct the social, economic, or political structure of a community from material evidence?",
    "How do I analyse faunal remains to reconstruct hunting, herding practices, and human-animal relationships?",
    "How do I reconstruct the chaîne opératoire and raw material processing techniques of past societies?",
    "How do I identify and interpret ritual or religious behaviour from material and contextual evidence?",
    "How do I integrate written historical sources and material data to reconstruct past events and geographical transformations?",
    "How do I reconstruct the dietary and subsistence strategies of a past community?",
    "How do I analyse the organisation, growth, and transformation of an ancient urban context?",
    "How do I determine the composition, provenance, or manufacturing techniques of an artefact through physicochemical analysis?",
    "How do I build a reliable chronological sequence when available dating evidence is uncertain or fragmentary?",
    "How do I reconstruct the evolution of approaches and research interests within a discipline over time?",
    "How do I analyse the distribution and organisation of human settlements across a territory over the long term?",
    "How do I reconstruct past vegetation, plant use, and landscape change through botanical remains?",
    "How do I analyse textile production and its economic and cultural significance in a past society?",
    "How do I document, classify, and interpret architectural decorative programmes within a historical and cultural context?",
    "How do I reconstruct exchange networks and cultural interaction between distant communities?",
    "How do I assess, manage, and communicate the value of a cultural asset within a protection and risk framework?",
    "How do I use comparisons with modern or experimental practices to interpret material evidence from the past?",
    "How do I document, classify, and interpret rock art manifestations within their spatial and cultural context?",
]

VAGUE_DATA = [
    "some kind of statistical or quantitative analysis",
    "some kind of spatial or geographic approach",
    "some kind of image or visual analysis",
    "some kind of network or relational analysis",
    "some kind of text or document analysis",
    "some kind of dating or chronological modelling",
    "some kind of 3D reconstruction or modelling",
    "some kind of machine learning or pattern recognition",
    "some kind of simulation or agent-based modelling",
]


# ─── INPUT FILE MANAGEMENT ────────────────────────────────────────────────────

def ensure_input_files():
    """Create L2.xlsx, Vague.xlsx, Questions.xlsx from taxonomy + hardcoded data."""
    l2_path  = os.path.join(INPUTS_DIR, 'L2.xlsx')
    vg_path  = os.path.join(INPUTS_DIR, 'Vague.xlsx')
    q_path   = os.path.join(INPUTS_DIR, 'Questions.xlsx')

    if not os.path.exists(l2_path):
        taxonomy = pd.read_csv(TAXONOMY_CSV)
        l2_values = sorted(taxonomy['level_2_mid'].dropna().unique().tolist())
        pd.DataFrame({'L2': l2_values}).to_excel(l2_path, index=False)
        print(f"Created {l2_path}  ({len(l2_values)} L2 categories)")

    if not os.path.exists(vg_path):
        pd.DataFrame({'Vague': VAGUE_DATA}).to_excel(vg_path, index=False)
        print(f"Created {vg_path}  ({len(VAGUE_DATA)} entries)")

    if not os.path.exists(q_path):
        pd.DataFrame({'Question': QUESTIONS_DATA}).to_excel(q_path, index=False)
        print(f"Created {q_path}  ({len(QUESTIONS_DATA)} questions)")


# ─── TAXONOMY ─────────────────────────────────────────────────────────────────

def load_l3_taxonomy():
    """Return a sorted list of unique L3 labels from the taxonomy CSV."""
    df = pd.read_csv(TAXONOMY_CSV)
    return sorted(df['level_3'].dropna().unique().tolist())


# ─── PROMPTS ──────────────────────────────────────────────────────────────────

def prompt_expert(question: str, l2: str) -> str:
    return (
        "You are a research assistant for computational archaeologists.\n\n"
        "A researcher comes to you with the following problem:\n\n"
        f'"I am working on: {question}\n'
        f'I already know I want to apply {l2} to my analysis.\n'
        "Which specific tools, algorithms, or variants of this method would you\n"
        'recommend, and how would you apply them concretely to this problem?"\n\n'
        "List the computational methods you would use, being as specific as possible.\n"
        "For each method, provide a one-sentence justification.\n"
        "Format each line strictly as:  Method Name | One-sentence justification."
    )


def prompt_intermediate(question: str, vague: str) -> str:
    return (
        "You are a research assistant for computational archaeologists.\n\n"
        "A researcher comes to you with the following problem:\n\n"
        f'"I am working on: {question}\n'
        f'I have a rough idea that I need {vague},\n'
        'but I do not know which specific method to choose.\n'
        'What would you recommend?"\n\n'
        "List the computational methods you would use, being as specific as possible.\n"
        "For each method, provide a one-sentence justification.\n"
        "Format each line strictly as:  Method Name | One-sentence justification."
    )


def prompt_novice(question: str) -> str:
    return (
        "You are a research assistant for computational archaeologists.\n\n"
        "A researcher comes to you with the following problem:\n\n"
        f'"I am working on: {question}\n'
        "I have no specific computational background.\n"
        'Which digital methods could I use to address this research problem?"\n\n'
        "List the computational methods you would use, being as specific as possible.\n"
        "For each method, provide a one-sentence justification.\n"
        "Format each line strictly as:  Method Name | One-sentence justification."
    )


def prompt_l4_to_l3(l4_method: str, l3_list: list) -> str:
    taxonomy_block = "\n".join(l3_list)
    return (
        "You are a taxonomy classifier.\n\n"
        "Given the following L4 computational method, identify the single most appropriate\n"
        "L3 category from the list below.  Reply with ONLY the exact L3 label as it appears\n"
        "in the list — nothing else, no explanation.\n\n"
        f"L4 method: {l4_method}\n\n"
        "L3 taxonomy:\n"
        f"{taxonomy_block}\n\n"
        "Best matching L3 category:"
    )


# ─── L4 RESPONSE PARSER ───────────────────────────────────────────────────────

_STRIP_PREFIX = re.compile(r'^[\s\-\*\d\.\)]+')
_BOLD         = re.compile(r'\*\*([^*]+)\*\*')


def parse_l4_methods(text: str) -> list:
    """
    Parse LLM generation output into a list of (method, justification) tuples.
    Handles numbered lists, bullets, bold formatting, and bare method names.
    """
    results = []
    for raw_line in text.strip().split('\n'):
        line = raw_line.strip()
        if not line:
            continue
        # Remove bold markers
        line = _BOLD.sub(r'\1', line)
        # Strip leading numbering / bullets
        line = _STRIP_PREFIX.sub('', line).strip()
        if not line:
            continue

        if '|' in line:
            parts = line.split('|', 1)
            method = parts[0].strip().rstrip(':')
            justification = parts[1].strip() if len(parts) > 1 else ''
        elif ':' in line and len(line.split(':', 1)[0].split()) <= 8:
            # "Method Name: justification sentence"
            parts = line.split(':', 1)
            method = parts[0].strip()
            justification = parts[1].strip()
        else:
            method = line.strip()
            justification = ''

        if method and len(method) < 200:
            results.append((method, justification))

    return results


# ─── L4 → L3 MAPPING ──────────────────────────────────────────────────────────

def extract_l3_from_response(response: str, l3_list: list) -> str:
    """
    Find the best matching L3 label from the model response.
    Strategy:
      1. Exact match of the full label.
      2. Match by L3 code prefix (e.g. "L3-097").
      3. Longest substring match against any L3 label.
      4. Return the raw response stripped to 300 chars (flagged for review).
    """
    resp_clean = response.strip()

    # 1. Exact match
    if resp_clean in l3_list:
        return resp_clean

    # 2. Code-prefix match  (e.g. model returns "L3-097" or "L3-097: ...")
    code_match = re.search(r'L3-\d+', resp_clean)
    if code_match:
        code = code_match.group(0)
        for label in l3_list:
            if label.startswith(code):
                return label

    # 3. Longest substring of any label found in the response
    resp_lower = resp_clean.lower()
    best = None
    best_len = 0
    for label in l3_list:
        # Compare the descriptive part after the code
        desc = label.split(':', 1)[-1].strip().lower()
        if desc and desc in resp_lower and len(desc) > best_len:
            best = label
            best_len = len(desc)
    if best:
        return best

    # 4. Fallback — raw response (will be flagged as inconsistent)
    return resp_clean[:300]


def map_l4_to_l3(llm: Llama, l4_method: str, l3_list: list, _token_checked: list = []) -> dict:
    """
    Run N_MAPPING_RUNS mapping calls and return consensus + consistency flag.
    """
    runs = []
    mapping_prompt = prompt_l4_to_l3(l4_method, l3_list)

    # Check prompt token count once per run (to verify it fits in context)
    if not _token_checked:
        n_tokens = len(llm.tokenize(mapping_prompt.encode()))
        print(f"[token check] Mapping prompt: {n_tokens} tokens  (n_ctx={llm.n_ctx()})")
        if n_tokens > llm.n_ctx():
            print("WARNING: mapping prompt exceeds context window — L3 list will be truncated!")
        _token_checked.append(True)

    for _ in range(N_MAPPING_RUNS):
        raw = llm.create_chat_completion(
            messages=[{"role": "user", "content": mapping_prompt}],
            temperature=TEMPERATURE,
            max_tokens=MAX_TOKENS_MAP,
        )['choices'][0]['message']['content']
        runs.append(extract_l3_from_response(raw, l3_list))

    # Majority vote
    from collections import Counter
    consensus = Counter(runs).most_common(1)[0][0]
    consistent = len(set(runs)) == 1

    return {
        'l3_mapping':            consensus,
        'l3_mapping_consistent': consistent,
        'l3_mapping_runs':       json.dumps(runs),
    }


# ─── MAIN PIPELINE ────────────────────────────────────────────────────────────

COLUMNS = [
    'iteration', 'profile', 'question', 'l2_input', 'vague_input',
    'l4_method', 'l4_justification',
    'l3_mapping', 'l3_mapping_consistent', 'l3_mapping_runs',
]


def load_completed(results_file: str) -> set:
    """Return set of (iteration, profile) pairs already saved."""
    if not os.path.exists(results_file):
        return set()
    try:
        saved = pd.read_csv(results_file)
        if 'iteration' in saved.columns and 'profile' in saved.columns:
            return set(zip(saved['iteration'].tolist(), saved['profile'].tolist()))
    except Exception:
        pass
    return set()


def append_rows(results_file: str, rows: list):
    if not rows:
        return
    df = pd.DataFrame(rows, columns=COLUMNS)
    write_header = not os.path.exists(results_file)
    df.to_csv(results_file, mode='a', header=write_header, index=False)


def find_model() -> str:
    search_root = os.path.join(os.path.dirname(__file__), '..')
    # Prefer the 9B model by name
    candidates = (
        glob.glob(os.path.join(search_root, 'Qwen3.5-9B-Q8_0.gguf')) +
        glob.glob(os.path.join(search_root, '*9B*Q8_0.gguf')) +
        glob.glob(os.path.join(search_root, '*Q8_0.gguf'))
    )
    # Filter out embedding models
    candidates = [p for p in candidates if 'Embedding' not in os.path.basename(p)]
    if not candidates:
        raise FileNotFoundError(
            "No Qwen 9B GGUF model found.  "
            "Expected Qwen3.5-9B-Q8_0.gguf in the parent directory."
        )
    return candidates[0]


def main():
    # ── Setup ──────────────────────────────────────────────────────────────────
    os.chdir(os.path.dirname(__file__))
    ensure_input_files()

    L2        = pd.read_excel('L2.xlsx')
    VAGUE     = pd.read_excel('Vague.xlsx')
    QUESTIONS = pd.read_excel('Questions.xlsx')
    l3_list   = load_l3_taxonomy()

    l2_col       = L2.columns[0]
    vague_col    = VAGUE.columns[0]
    question_col = QUESTIONS.columns[0]

    completed = load_completed(RESULTS_FILE)
    n_skip = len(completed)
    if n_skip:
        print(f"Resuming: {n_skip} (iteration, profile) pairs already done.")

    # ── Model ──────────────────────────────────────────────────────────────────
    #model_path = find_model()
    model_path = "/mnt/ssd_lavoro/LAB_AI_PC/Archaeogentic-researcher/models/gemma-4-E4B-it-UD-Q8_K_XL.gguf"
    print(f"Loading model: {os.path.basename(model_path)}")
    llm = Llama(
        model_path=model_path,
        n_gpu_layers=-1,
        n_ctx=8192,
        verbose=False,
    )
    print("Model loaded.")

    # ── Main loop ──────────────────────────────────────────────────────────────
    for iteration in tqdm(range(1, N_ITERATIONS + 1), desc="Iterations"):

        # Fixed triplet across all three profiles
        l2       = L2[l2_col].dropna().sample(1).values[0]
        vague    = VAGUE[vague_col].dropna().sample(1).values[0]
        question = QUESTIONS[question_col].dropna().sample(1).values[0]

        profiles = {
            'expert':       (prompt_expert(question, l2),        l2,    ''),
            'intermediate': (prompt_intermediate(question, vague), '',   vague),
            'novice':       (prompt_novice(question),              '',    ''),
        }

        for profile, (prompt, l2_val, vague_val) in profiles.items():
            if (iteration, profile) in completed:
                continue

            # ── Generation ────────────────────────────────────────────────────
            raw_response = llm.create_chat_completion(
                messages=[{"role": "user", "content": prompt}],
                temperature=TEMPERATURE,
                max_tokens=MAX_TOKENS_GEN,
            )['choices'][0]['message']['content']

            l4_methods = parse_l4_methods(raw_response)

            # Fallback: if parser found nothing, store the raw response as one item
            if not l4_methods:
                l4_methods = [('UNPARSED', raw_response[:500])]

            # ── L4 → L3 mapping + row collection ──────────────────────────────
            rows = []
            for l4_method, l4_justification in l4_methods:
                mapping = map_l4_to_l3(llm, l4_method, l3_list)
                rows.append([
                    iteration, profile, question, l2_val, vague_val,
                    l4_method, l4_justification,
                    mapping['l3_mapping'],
                    mapping['l3_mapping_consistent'],
                    mapping['l3_mapping_runs'],
                ])

            # ── Incremental save ───────────────────────────────────────────────
            append_rows(RESULTS_FILE, rows)
            completed.add((iteration, profile))

    print(f"\nDone.  Results saved to: {RESULTS_FILE}")
    df = pd.read_csv(RESULTS_FILE)
    print(f"Total rows: {len(df)}")
    print(f"Profiles:   {df['profile'].value_counts().to_dict()}")
    unmapped = df[~df['l3_mapping'].str.startswith('L3-', na=False)]
    total = len(df)
    n_unmapped = len(unmapped)
    print(f"Unmapped L4 items (review needed): {n_unmapped} / {total} ({100*n_unmapped/total:.1f}%)")
    if n_unmapped:
        print(unmapped[['l4_method', 'l3_mapping']].to_string(index=False))


if __name__ == '__main__':
    main()
