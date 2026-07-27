"""
Trend temporale delle parole "tipiche degli LLM" negli abstract archeologici.

Idea: parole come "delve", "intricate", "showcase"... sono diventate molto piu'
frequenti nei testi scientifici dopo l'uscita di ChatGPT (novembre 2022).
Questo script conta tali marcatori in tutti gli abstract di df_cleaned, normalizza
per il numero totale di parole pubblicate ogni anno (per non confondere "piu' paper"
con "piu' uso per paper") e produce un grafico a linea con un marker sul 2022.

Uso:
    conda activate ai_abstract
    python Python/5_llm_words/llm_word_trends.py

Output:
    data/output/llm_word_trends_by_year.csv
    data/output/llm_word_counts_by_word_year.csv
    data/output/figures/llm_words/llm_word_trends.png
"""

import os
import re

import matplotlib.pyplot as plt
import pandas as pd

# ---------------------------------------------------------------------------
# CONFIGURAZIONE
# ---------------------------------------------------------------------------

# Lemmi marcatori LLM (lista curata: Liang et al. 2024, Kobak et al. 2024).
# Modifica liberamente questa lista. Per ogni lemma viene costruita una regex
# che cattura le inflessioni piu' comuni (es. delve / delves / delved / delving).
LLM_WORDS = [
    "delve",
    "intricate",
    "showcase",
    "underscore",
    "pivotal",
    "realm",
    "tapestry",
    "meticulous",
    "boast",
    "leverage",
    "nuanced",
    "multifaceted",
    "encompass",
    "comprehensive",
    "notably",
    "crucial",
    "garner",
    "foster",
    "seamless",
    "robust",
    "paradigm",
    "holistic",
    "elucidate",
    "endeavor",
    "intricacies",
]

# Anno di riferimento (uscita pubblica di ChatGPT: 30 novembre 2022).
CHATGPT_YEAR = 2022

# Range di anni affidabile. Il 2026 e' tipicamente parziale: lo escludiamo dal
# grafico per non avere un punto finale fuorviante (cambia EXCLUDE_PARTIAL_LAST
# a False per includerlo).
YEAR_MIN = 2010
YEAR_MAX = 2025
EXCLUDE_PARTIAL_LAST = True

# Soglia sotto la quale un anno ha "pochi" paper: viene segnalato a console.
MIN_PAPERS_WARN = 30

# Percorsi (relativi a questo file).
HERE = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = os.path.join(HERE, "..", "1_dataset", "df_cleaned.xlsx")
OUT_DIR = os.path.join(HERE, "..", "..", "data", "output")
FIG_DIR = os.path.join(OUT_DIR, "figures", "llm_words")


# ---------------------------------------------------------------------------
# REGEX DEI MARCATORI
# ---------------------------------------------------------------------------

def build_word_patterns(words):
    """Per ogni lemma costruisce una regex compilata che cattura le inflessioni
    comuni (plurale, passato, gerundio). Es: 'delve' -> \\bdelv(?:e|es|ed|ing)\\b.

    Gestione dei lemmi che terminano in 'e' (delve, leverage, ...): si rimuove
    la 'e' finale e si aggiungono i suffissi e/es/ed/ing. Per gli altri si
    aggiungono direttamente s/ed/ing oltre alla forma base.
    """
    patterns = {}
    for w in words:
        w = w.lower().strip()
        if w.endswith("e"):
            stem = w[:-1]
            suffixes = ["e", "es", "ed", "ing"]
        elif w.endswith("y"):
            # es. 'intricacies' e' gia' plurale: lasciamo la forma cosi' com'e'.
            stem = w
            suffixes = [""]
        else:
            stem = w
            suffixes = ["", "s", "ed", "ing"]
        alternation = "|".join(re.escape(s) for s in suffixes)
        patterns[w] = re.compile(r"\b" + re.escape(stem) + r"(?:" + alternation + r")\b")
    return patterns


WORD_RE = re.compile(r"\b\w+\b")


# ---------------------------------------------------------------------------
# CARICAMENTO DATI
# ---------------------------------------------------------------------------

def load_abstracts():
    df = pd.read_excel(DATA_FILE)
    for col in ("abstract", "year"):
        if col not in df.columns:
            raise KeyError(f"Colonna '{col}' assente in {DATA_FILE}")

    df = df[["year", "abstract"]].copy()
    df["abstract"] = df["abstract"].astype("string")
    df = df.dropna(subset=["abstract", "year"])

    # year -> intero, scartando valori non numerici.
    df["year"] = pd.to_numeric(df["year"], errors="coerce")
    df = df.dropna(subset=["year"])
    df["year"] = df["year"].astype(int)

    df = df[(df["year"] >= YEAR_MIN) & (df["year"] <= YEAR_MAX)]
    df["abstract"] = df["abstract"].str.lower()
    return df.reset_index(drop=True)


# ---------------------------------------------------------------------------
# CONTEGGIO
# ---------------------------------------------------------------------------

def count_occurrences(df, patterns):
    """Restituisce due DataFrame:
    - per_year: anno, n_papers, total_words, marker_occurrences, freq_per_10k
    - per_word_year: matrice (anno x parola) con i conteggi grezzi.
    """
    word_names = list(patterns.keys())

    # accumulatori per-abstract
    df = df.copy()
    df["total_words"] = df["abstract"].apply(lambda t: len(WORD_RE.findall(t)))

    # conteggio di ciascun marcatore per ogni abstract
    for w, pat in patterns.items():
        df[f"_w_{w}"] = df["abstract"].apply(lambda t, p=pat: len(p.findall(t)))

    marker_cols = [f"_w_{w}" for w in word_names]
    df["marker_occurrences"] = df[marker_cols].sum(axis=1)

    # aggregazione per anno
    grp = df.groupby("year")
    per_year = pd.DataFrame({
        "n_papers": grp.size(),
        "total_words": grp["total_words"].sum(),
        "marker_occurrences": grp["marker_occurrences"].sum(),
    }).reset_index()
    per_year["freq_per_10k"] = (
        per_year["marker_occurrences"] / per_year["total_words"] * 10000
    )

    # matrice parola x anno
    per_word_year = grp[marker_cols].sum()
    per_word_year.columns = word_names
    per_word_year = per_word_year.T  # parole come righe, anni come colonne
    per_word_year.index.name = "word"

    return per_year, per_word_year


# ---------------------------------------------------------------------------
# GRAFICO
# ---------------------------------------------------------------------------

def make_plot(per_year):
    os.makedirs(FIG_DIR, exist_ok=True)
    out_png = os.path.join(FIG_DIR, "llm_word_trends.png")

    fig, ax = plt.subplots(figsize=(10, 6), dpi=200)

    ax.plot(
        per_year["year"], per_year["freq_per_10k"],
        marker="o", linewidth=2, color="#B2182B", zorder=3,
    )

    # linea verticale ChatGPT
    ax.axvline(CHATGPT_YEAR, linestyle="--", color="grey", linewidth=1.5, zorder=2)
    ymax = per_year["freq_per_10k"].max()
    ax.annotate(
        "ChatGPT (nov 2022)",
        xy=(CHATGPT_YEAR, ymax * 0.95),
        xytext=(6, 0), textcoords="offset points",
        va="top", ha="left", color="grey", fontsize=10,
    )

    ax.set_title("'LLM-typical' words in archaeology abstracts", fontsize=13)
    ax.set_xlabel("Publication year")
    ax.set_ylabel("Occurrences per 10,000 words")
    ax.grid(True, linestyle=":", alpha=0.5)
    ax.set_axisbelow(True)
    fig.tight_layout()
    fig.savefig(out_png, dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return out_png


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    patterns = build_word_patterns(LLM_WORDS)
    df = load_abstracts()

    print(f"Abstract caricati: {len(df)}")
    print(f"Range anni: {df['year'].min()}-{df['year'].max()}")
    if EXCLUDE_PARTIAL_LAST:
        print(f"(2026 escluso come anno parziale; range usato {YEAR_MIN}-{YEAR_MAX})")

    per_year, per_word_year = count_occurrences(df, patterns)

    # segnala anni con pochi paper (denominatore poco affidabile)
    sparse = per_year[per_year["n_papers"] < MIN_PAPERS_WARN]
    if not sparse.empty:
        print("\nAttenzione - anni con pochi paper (frequenza piu' rumorosa):")
        for _, r in sparse.iterrows():
            print(f"  {int(r['year'])}: {int(r['n_papers'])} paper")

    # salvataggio CSV
    by_year_csv = os.path.join(OUT_DIR, "llm_word_trends_by_year.csv")
    by_word_csv = os.path.join(OUT_DIR, "llm_word_counts_by_word_year.csv")
    per_year.to_csv(by_year_csv, index=False)
    per_word_year.to_csv(by_word_csv)

    # nota metodologica: media pre vs post 2022
    pre = per_year[per_year["year"] < CHATGPT_YEAR]
    post = per_year[per_year["year"] >= CHATGPT_YEAR]
    if not pre.empty and not post.empty:
        # media pesata per parole totali (piu' robusta della media semplice tra anni)
        pre_freq = pre["marker_occurrences"].sum() / pre["total_words"].sum() * 10000
        post_freq = post["marker_occurrences"].sum() / post["total_words"].sum() * 10000
        delta_pct = (post_freq - pre_freq) / pre_freq * 100
        print("\n--- Nota metodologica (frequenza per 10.000 parole) ---")
        print(f"Pre-2022  (<{CHATGPT_YEAR}):  {pre_freq:.2f}")
        print(f"Post-2022 (>={CHATGPT_YEAR}): {post_freq:.2f}")
        print(f"Variazione: {delta_pct:+.1f}%")

    out_png = make_plot(per_year)

    print("\nFile prodotti:")
    print(f"  {by_year_csv}")
    print(f"  {by_word_csv}")
    print(f"  {out_png}")


if __name__ == "__main__":
    main()
