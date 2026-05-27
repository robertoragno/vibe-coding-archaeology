

import requests
import pandas as pd
import time
import json
import os
from tqdm import tqdm
from datetime import datetime

# ─── CONFIGS ────────────────────────────────────────────────────────────

API_KEY       = "API_KEY"    
INPUT_FILE    = "source.txt"      
OUTPUT_CSV    = "scopus_results.csv"
OUTPUT_XLSX   = "scopus_results.xlsx"
PROGRESS_FILE = "progress.json"         
DELAY         = 0.45                   
SAVE_EVERY    = 500                   
YEAR_FROM     = 2010 #1900
YEAR_TO       = datetime.now().year

# Retry settings
MAX_RETRIES   = 5
RETRY_WAIT    = [5, 10, 20, 40, 60]    # secondi di attesa tra i tentativi

# ───────────────────────────────────────────────────────────────────────────────

SEARCH_URL = "https://api.elsevier.com/content/search/scopus"
HEADERS    = {"X-ELS-APIKey": API_KEY, "Accept": "application/json"}

FIELDS = ",".join([
    "dc:identifier", "eid", "dc:title", "dc:creator",
    "author", "prism:publicationName", "prism:volume",
    "prism:issueIdentifier", "prism:pageRange", "prism:coverDate",
    "prism:doi", "citedby-count", "subtypeDescription", "subtype",
    "pubStatus", "openaccess", "affiliation",
    "prism:issn", "prism:isbn", "pubmed-id", "dc:publisher",
    "source-id", "prism:aggregationType",
    "authkeywords", "dc:description", "language",
])


# ── Progress tracking ─────────────────────────────────────────────────────────

def load_progress() -> dict:
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, "r") as f:
            return json.load(f)
    return {"completed": [], "started_at": datetime.now().isoformat()}


def mark_completed(progress: dict, source_id: str):
    if source_id not in progress["completed"]:
        progress["completed"].append(source_id)
    progress["last_completed"] = source_id
    progress["last_updated"] = datetime.now().isoformat()
    with open(PROGRESS_FILE, "w") as f:
        json.dump(progress, f, indent=2)


# ── Request with retry ───────────────────────────────────────────────────────

def get_with_retry(url, params=None, context=""):
    for attempt in range(MAX_RETRIES):
        try:
            r = requests.get(url, headers=HEADERS, params=params, timeout=60)

            if r.status_code == 429:
                wait = RETRY_WAIT[min(attempt, len(RETRY_WAIT) - 1)]
                tqdm.write(f"  ⚠ Rate limit {context}. Waiting {wait}s "
                           f"(Attempt {attempt+1}/{MAX_RETRIES})")
                time.sleep(wait)
                continue

            if r.status_code >= 500:
                wait = RETRY_WAIT[min(attempt, len(RETRY_WAIT) - 1)]
                tqdm.write(f"  ⚠ Server error {r.status_code} {context}. Waiting {wait}s "
                           f"(Attempt {attempt+1}/{MAX_RETRIES})")
                time.sleep(wait)
                continue

            return r

        except (requests.exceptions.ReadTimeout,
                requests.exceptions.ConnectTimeout,
                requests.exceptions.ConnectionError) as e:
            wait = RETRY_WAIT[min(attempt, len(RETRY_WAIT) - 1)]
            tqdm.write(f"  ⚠ Timeout {context}: {type(e).__name__}. Waiting {wait}s "
                       f"(Attempt {attempt+1}/{MAX_RETRIES})")
            time.sleep(wait)

    tqdm.write(f"  ✗ Failed after {MAX_RETRIES} attempts {context}")
    return None


# ── Helper parsing ────────────────────────────────────────────────────────────

def _str(val):
    if val is None:
        return ""
    if isinstance(val, dict):
        return val.get("$", "") or val.get("#text", "") or ""
    return str(val).strip()


def _parse_authors(entry):
    authors = entry.get("author", [])
    if isinstance(authors, dict):
        authors = [authors]
    names = []
    for a in authors:
        given   = _str(a.get("given-name"))
        surname = _str(a.get("surname"))
        if given and surname:
            names.append(f"{given} {surname}")
        elif surname:
            names.append(surname)
        else:
            names.append(_str(a.get("authname") or a.get("ce:indexed-name")))
    return "; ".join(n for n in names if n)


def _parse_affiliations(entry):
    affils = entry.get("affiliation", [])
    if isinstance(affils, dict):
        affils = [affils]
    parts = []
    for a in affils:
        label = ", ".join(filter(None, [
            _str(a.get("affilname")),
            _str(a.get("affiliation-city")),
            _str(a.get("affiliation-country")),
        ]))
        if label:
            parts.append(label)
    return " | ".join(parts)


def _parse_keywords(entry):
    kw = entry.get("authkeywords", "")
    if isinstance(kw, dict):
        kw = _str(kw)
    return str(kw).strip()


def _parse_issn(entry):
    issn = entry.get("prism:issn", "")
    if isinstance(issn, list):
        return "; ".join(_str(i) for i in issn)
    return _str(issn)


def _parse_language(entry):
    lang = entry.get("language")
    if lang is None:
        return ""
    if isinstance(lang, dict):
        return _str(lang.get("@xml:lang") or lang.get("$") or lang)
    return str(lang).strip()


def parse_entry(entry, source_id) -> dict:
    cover_date = _str(entry.get("prism:coverDate", ""))
    year = cover_date[:4] if cover_date else ""
    return {
        "source_id":        source_id,
        "authors":          _parse_authors(entry),
        "first_author":     _str(entry.get("dc:creator")),
        "title":            _str(entry.get("dc:title")),
        "year":             year,
        "eid":              _str(entry.get("eid")),
        "source_title":     _str(entry.get("prism:publicationName")),
        "volume":           _str(entry.get("prism:volume")),
        "issue":            _str(entry.get("prism:issueIdentifier")),
        "pages":            _str(entry.get("prism:pageRange")),
        "citation_count":   _str(entry.get("citedby-count")),
        "source_type":      _str(entry.get("prism:aggregationType")),
        "doc_type":         _str(entry.get("subtypeDescription") or entry.get("subtype")),
        "pub_stage":        _str(entry.get("pubStatus")),
        "doi":              _str(entry.get("prism:doi")),
        "open_access":      _str(entry.get("openaccess")),
        "affiliations":     _parse_affiliations(entry),
        "issn":             _parse_issn(entry),
        "isbn":             _str(entry.get("prism:isbn")),
        "pubmed_id":        _str(entry.get("pubmed-id")),
        "publisher":        _str(entry.get("dc:publisher")),
        "editors":          "",
        "language":         _parse_language(entry),
        "correspondence":   "",
        "abbrev_source":    "",
        "abstract":         _str(entry.get("dc:description")),
        "author_keywords":  _parse_keywords(entry),
        "indexed_keywords": "",
    }


# ── Search API ────────────────────────────────────────────────

def search_all(query: str, desc: str) -> list:
    params = {
        "query": query,
        "count": 25,
        "start": 0,
        "view":  "COMPLETE",
        "field": FIELDS,
    }

    r = get_with_retry(SEARCH_URL, params=params, context=f"[{desc}]")
    if r is None or r.status_code != 200:
        if r is not None:
            msgs = {401: "API key not valid", 403: "Access denied", 400: "Bad request"}
            tqdm.write(f"  ✗ {msgs.get(r.status_code, f'HTTP {r.status_code}')} [{desc}]")
        return []

    data    = r.json().get("search-results", {})
    total   = int(data.get("opensearch:totalResults", 0))
    entries = data.get("entry", [])
    if not entries or entries == [{"@_fa": "true", "error": "Result set was empty"}]:
        return []

    all_entries = list(entries)
    time.sleep(DELAY)

    pbar = tqdm(total=min(total, 5000), initial=len(all_entries),
                desc=desc, unit=" art", leave=False)
    while len(all_entries) < min(total, 5000):
        params["start"] = len(all_entries)
        r = get_with_retry(SEARCH_URL, params=params,
                           context=f"[{desc} start={params['start']}]")
        if r is None or r.status_code != 200:
            tqdm.write(f"  ✗ Pagination interrupted at {len(all_entries)} [{desc}]")
            break
        batch = r.json().get("search-results", {}).get("entry", [])
        if not batch or batch == [{"@_fa": "true", "error": "Result set was empty"}]:
            break
        all_entries.extend(batch)
        pbar.update(len(batch))
        time.sleep(DELAY)
    pbar.close()

    return all_entries


def fetch_source(source_id: str) -> list:
    base_query = f"SOURCE-ID({source_id})"

    r = get_with_retry(SEARCH_URL,
                       params={"query": base_query, "count": 1},
                       context=f"[source {source_id}]")
    if r is None or r.status_code != 200:
        print(f"\n  ✗ Source {source_id}: impossible to count records")
        return []

    total = int(r.json().get("search-results", {}).get("opensearch:totalResults", 0))
    print(f"\n  Source {source_id}: {total} articles total")
    time.sleep(DELAY)

    records = []
    if total <= 5000:
        entries = search_all(base_query, f"Source {source_id}")
        records = [parse_entry(e, source_id) for e in entries]
    else:
        print(f"  ⚠ More than 5000 results → downloading year by year ({YEAR_FROM}–{YEAR_TO})")
        for year in tqdm(range(YEAR_FROM, YEAR_TO + 1),
                         desc=f"  Years source {source_id}"):
            query = f"SOURCE-ID({source_id}) AND PUBYEAR IS {year}"
            entries = search_all(query, f"{source_id}/{year}")
            records.extend([parse_entry(e, source_id) for e in entries])
            time.sleep(DELAY)

    return records


# ── Saving ───────────────────────────────────────────────────────────────

def _save(records):
    df = pd.DataFrame(records)
    before = len(df)
    df = df.drop_duplicates(subset=["eid"], keep="last")
    after = len(df)
    if before != after:
        print(f"  🧹 Removed {before - after} duplicates (EID)")
    df.to_csv(OUTPUT_CSV, index=False, encoding="utf-8-sig")
    df.to_excel(OUTPUT_XLSX, index=False)
    return len(df)


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    with open(INPUT_FILE, "rb") as f:
        raw = f.read()
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        text = raw.decode("utf-16")
    else:
        text = raw.decode("utf-8", errors="replace")
    source_ids = [l.strip() for l in text.splitlines() if l.strip()]
    print(f"✓ Loaded {len(source_ids)} Source IDs from '{INPUT_FILE}'")

    # Load progress
    progress   = load_progress()
    completed  = set(progress.get("completed", []))
    skipped    = [sid for sid in source_ids if sid in completed]
    to_process = [sid for sid in source_ids if sid not in completed]

    if skipped:
        print(f"  ⏭ Already completed (skip): {len(skipped)} source ID → {skipped}")
    print(f"  ▶ To process: {len(to_process)} source ID")

    # Load existing results (from previous runs)
    if os.path.exists(OUTPUT_CSV) and skipped:
        existing_df = pd.read_csv(OUTPUT_CSV, dtype=str, encoding="utf-8-sig")
        all_records = existing_df.to_dict("records")
        print(f"  📂 Loaded {len(all_records)} existing records from '{OUTPUT_CSV}'")
    else:
        all_records = []

    last_save_count = len(all_records)

    for sid in to_process:
        print(f"\n── Source ID: {sid} {'─'*30}")
        records = fetch_source(sid)

        if not records:
            print(f"  ⚠ No records retrieved for {sid} — source skipped (not marked as completed)")
            continue

        all_records.extend(records)
        print(f"  → {len(records)} articles retrieved")

        # Mark as completed ONLY if the download was successful
        mark_completed(progress, sid)
        print(f"  ✓ Source {sid} marked as completed in progress.json")

        # Periodic checkpoint
        if len(all_records) - last_save_count >= SAVE_EVERY:
            n = _save(all_records)
            last_save_count = len(all_records)
            print(f"  💾 Periodic checkpoint saved ({n} unique records total)")

    # Final saving
    n = _save(all_records)
    print(f"\n{'═'*50}")
    print(f"✓ Completed: {n} unique articles total")
    print(f"  CSV  → {OUTPUT_CSV}")
    print(f"  XLSX → {OUTPUT_XLSX}")
    print(f"  Log  → {PROGRESS_FILE}")


if __name__ == "__main__":
    main()