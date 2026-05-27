

import json
import csv
import argparse
from pathlib import Path
from datetime import datetime


# ── Data loading ──────────────────────────────────────────────────────────────

def load_freq(csv_path: Path) -> dict:
    """Somma le frequenze per canonical term dal CSV dei risultati."""
    freq: dict = {}
    if not csv_path.exists():
        return freq
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            canonical = row.get("canonical", "").strip()
            try:
                fval = int(row.get("frequency", 1))
            except (ValueError, TypeError):
                fval = 1
            if canonical:
                freq[canonical] = freq.get(canonical, 0) + fval
    return freq


def compute_stats(taxonomy: dict) -> dict:
    """Conta L2, L3, termini unici e cluster garbage nella struttura L2→L3."""
    n_l2 = len(taxonomy)
    n_l3 = sum(len(v.get("children", {})) for v in taxonomy.values())
    n_garbage = sum(
        1 for v in taxonomy.values()
        for l3v in v.get("children", {}).values()
        if l3v.get("is_garbage", False)
    )
    all_members: set = set()
    for v in taxonomy.values():
        for l3v in v.get("children", {}).values():
            all_members.update(l3v.get("members", []))
    return {"l2": n_l2, "l3": n_l3, "terms": len(all_members), "garbage": n_garbage}


# ── HTML template ─────────────────────────────────────────────────────────────

HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Computational Methods — Taxonomy Explorer</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --bg:       #0e1018;
  --surf:     #161923;
  --surf2:    #1d2132;
  --border:   #272d3f;
  --text:     #dde1f0;
  --muted:    #6b7494;
  --accent:   #7986e8;
  --font: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
}

body {
  font-family: var(--font);
  background: var(--bg);
  color: var(--text);
  height: 100vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* ── Header ──────────────────────────────────────────────── */
.hdr {
  background: var(--surf);
  border-bottom: 1px solid var(--border);
  padding: 10px 18px;
  display: flex;
  align-items: center;
  gap: 14px;
  flex-shrink: 0;
}
.hdr-title {
  font-size: 0.92rem;
  font-weight: 700;
  letter-spacing: -.01em;
  white-space: nowrap;
}
.hdr-title em { color: var(--accent); font-style: normal; }

.search-wrap { flex: 1; max-width: 380px; }
.search-wrap input {
  width: 100%;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 6px 12px;
  color: var(--text);
  font-size: 0.82rem;
  font-family: var(--font);
  outline: none;
  transition: border-color .15s;
}
.search-wrap input:focus { border-color: var(--accent); }
.search-wrap input::placeholder { color: var(--muted); }

.stats { display: flex; gap: 8px; margin-left: auto; }
.stat {
  background: var(--surf2);
  border: 1px solid var(--border);
  border-radius: 20px;
  padding: 3px 10px;
  font-size: 0.7rem;
  color: var(--muted);
  white-space: nowrap;
}
.stat b { color: var(--text); }

/* ── Layout ──────────────────────────────────────────────── */
.layout { display: flex; flex: 1; overflow: hidden; }

/* ── Sidebar ─────────────────────────────────────────────── */
.sidebar {
  width: 330px;
  flex-shrink: 0;
  background: var(--surf);
  border-right: 1px solid var(--border);
  overflow-y: auto;
  overflow-x: hidden;
}
.sidebar::-webkit-scrollbar { width: 4px; }
.sidebar::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }

/* ── Tree ────────────────────────────────────────────────── */
.tnode { position: relative; }

.nrow {
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 6px 10px;
  cursor: pointer;
  user-select: none;
  border-left: 3px solid transparent;
  transition: background .1s;
  min-height: 30px;
}
.nrow:hover { background: var(--surf2); }
.nrow.sel   { background: var(--surf2); }

.chev {
  width: 14px;
  height: 14px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 8px;
  color: var(--muted);
  transition: transform .16s;
}
.chev.open { transform: rotate(90deg); }
.chev.leaf { opacity: 0; pointer-events: none; }

.lvlbadge {
  font-size: 0.58rem;
  font-weight: 800;
  padding: 1px 4px;
  border-radius: 3px;
  flex-shrink: 0;
  letter-spacing: .04em;
}
.b2 { background: rgba( 95,196,138,.18); color: #5fc48a; }
.b3 { background: rgba(232,144, 96,.18); color: #e8a97e; }

.nlabel {
  flex: 1;
  font-size: 0.78rem;
  line-height: 1.3;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.nl2 { font-weight: 600; font-size: 0.8rem; }
.nl3 { color: var(--muted); }
.nrow.sel .nl3 { color: var(--text); }

.cbadge {
  font-size: 0.6rem;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 1px 6px;
  color: var(--muted);
  flex-shrink: 0;
}

.garbage-tag {
  font-size: 0.55rem;
  font-weight: 800;
  padding: 1px 5px;
  border-radius: 3px;
  background: rgba(220,80,80,.18);
  color: #e07070;
  flex-shrink: 0;
  letter-spacing: .04em;
}

.garbage-banner {
  background: rgba(220,80,80,.08);
  border: 1px solid rgba(220,80,80,.25);
  border-radius: 6px;
  padding: 9px 14px;
  font-size: 0.78rem;
  color: #e07070;
  margin-bottom: 18px;
  display: flex;
  align-items: center;
  gap: 8px;
}

.card.is-garbage { opacity: 0.55; }

.nchildren { padding-left: 14px; }
.nchildren.hidden { display: none; }

.cbar {
  width: 3px;
  min-height: 18px;
  border-radius: 2px;
  align-self: stretch;
  flex-shrink: 0;
}

.no-results {
  padding: 20px;
  color: var(--muted);
  font-size: 0.8rem;
  text-align: center;
  display: none;
}

/* ── Detail panel ────────────────────────────────────────── */
.detail { flex: 1; overflow-y: auto; padding: 22px 28px; }
.detail::-webkit-scrollbar { width: 4px; }
.detail::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }

.empty {
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: var(--muted);
}
.empty-icon { font-size: 2.5rem; opacity: .2; }
.empty-hint { font-size: 0.8rem; }

.bc {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 5px;
  font-size: 0.7rem;
  color: var(--muted);
  margin-bottom: 10px;
}
.bc-item { cursor: pointer; transition: color .1s; }
.bc-item:hover { color: var(--text); }
.bc-sep { opacity: .3; }
.bc-cur { color: var(--text); }

.dtitle {
  font-size: 1.22rem;
  font-weight: 700;
  margin-bottom: 6px;
  line-height: 1.3;
}

.dlevel {
  display: inline-block;
  font-size: 0.67rem;
  font-weight: 700;
  padding: 2px 8px;
  border-radius: 4px;
  margin-bottom: 16px;
  letter-spacing: .07em;
}
.dl2 { background: rgba( 95,196,138,.2); color: #5fc48a; }
.dl3 { background: rgba(232,144, 96,.2); color: #e8a97e; }

.ddesc {
  font-size: 0.84rem;
  line-height: 1.65;
  color: var(--muted);
  background: var(--surf);
  border-left: 3px solid var(--border);
  padding: 10px 14px;
  border-radius: 0 6px 6px 0;
  margin-bottom: 22px;
}

.sec-title {
  font-size: 0.64rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .1em;
  color: var(--muted);
  margin-bottom: 10px;
}

.chips { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 22px; }
.chip {
  background: var(--surf);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 3px 9px;
  font-size: 0.75rem;
  display: flex;
  align-items: center;
  gap: 5px;
  transition: border-color .12s;
}
.chip:hover { border-color: var(--accent); }
.chip-freq { font-size: 0.62rem; font-weight: 700; color: var(--accent); }

.cards {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  gap: 10px;
  margin-bottom: 22px;
}
.card {
  background: var(--surf);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 12px 14px 12px 18px;
  cursor: pointer;
  position: relative;
  transition: border-color .14s, background .14s;
}
.card:hover { border-color: var(--accent); background: var(--surf2); }
.card-bar {
  position: absolute;
  left: 0; top: 0; bottom: 0;
  width: 4px;
  border-radius: 8px 0 0 8px;
}
.card-title { font-size: 0.8rem; font-weight: 600; margin-bottom: 5px; line-height: 1.3; }
.card-desc {
  font-size: 0.72rem;
  color: var(--muted);
  line-height: 1.44;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.card-meta { font-size: 0.62rem; color: var(--muted); margin-top: 7px; }

/* ── Footer ──────────────────────────────────────────────── */
.footer {
  background: var(--surf);
  border-top: 1px solid var(--border);
  padding: 5px 18px;
  font-size: 0.63rem;
  color: var(--muted);
  flex-shrink: 0;
  text-align: right;
}
</style>
</head>
<body>

<div class="hdr">
  <div class="hdr-title">Computational Methods <em>Taxonomy</em></div>
  <div class="search-wrap">
    <input id="search" type="text" placeholder="Search methods, categories…"
           autocomplete="off" spellcheck="false" />
  </div>
  <div class="stats">
    <div class="stat"><b>STAT_L2</b> categories</div>
    <div class="stat"><b>STAT_L3</b> clusters</div>
    <div class="stat"><b>STAT_TERMS</b> terms</div>
    <div class="stat" style="color:#e07070"><b>STAT_GARBAGE</b> garbage</div>
  </div>
</div>

<div class="layout">
  <div class="sidebar" id="sidebar">
    <div class="no-results" id="noResults">No results found.</div>
  </div>
  <div class="detail" id="detail">
    <div class="empty">
      <div class="empty-icon">⬡</div>
      <div class="empty-hint">Select a category from the tree to explore</div>
    </div>
  </div>
</div>

<div class="footer">Generated: GEN_DATE &nbsp;·&nbsp; Taxonomy Explorer</div>

<script>
const T    = TAXONOMY_JSON;
const FREQ = FREQ_JSON;

// ── Palette ───────────────────────────────────────────────────
const L2_KEYS = Object.keys(T);
const PALETTE = L2_KEYS.map(function(_, i) {
  var h = Math.round(i * 360 / L2_KEYS.length);
  return 'hsl(' + h + ',58%,56%)';
});
function l2Color(k) { return PALETTE[L2_KEYS.indexOf(k)] || '#888'; }

// ── Helpers ───────────────────────────────────────────────────
function labelName(key) {
  var m = key.match(/^L\d+-[\w-]+:\s*(.*)/);
  return m ? m[1] : key;
}

function countL3Terms(l2v) {
  return Object.values(l2v.children || {}).reduce(function(s, l3v) {
    return s + (l3v.members || []).length;
  }, 0);
}

// ── State ─────────────────────────────────────────────────────
var selected  = null;
var openNodes = {};   // key -> true

// ── Tree building ─────────────────────────────────────────────
function buildTree() {
  var sb = document.getElementById('sidebar');
  var nr = document.getElementById('noResults');
  while (sb.firstChild && sb.firstChild !== nr) sb.removeChild(sb.firstChild);

  L2_KEYS.forEach(function(l2k, idx) {
    sb.insertBefore(makeL2(l2k, T[l2k], PALETTE[idx]), nr);
  });
}

function makeL2(l2k, l2v, color) {
  var wrap = document.createElement('div');
  wrap.className = 'tnode'; wrap.dataset.key = l2k; wrap.dataset.level = '2';

  var row = document.createElement('div');
  row.className = 'nrow' + (selected === l2k ? ' sel' : '');
  row.style.borderLeftColor = selected === l2k ? color : 'transparent';

  var cbar = document.createElement('div');
  cbar.className = 'cbar'; cbar.style.background = color;

  var chev = document.createElement('div');
  var l3count = Object.keys(l2v.children || {}).length;
  chev.className = 'chev' + (openNodes[l2k] ? ' open' : '') + (l3count === 0 ? ' leaf' : '');
  chev.textContent = '▶';

  var badge = document.createElement('div');
  badge.className = 'lvlbadge b2'; badge.textContent = 'L2';

  var lbl = document.createElement('div');
  lbl.className = 'nlabel nl2'; lbl.dataset.full = l2k;
  lbl.textContent = labelName(l2k);

  var cnt = document.createElement('div');
  cnt.className = 'cbadge';
  cnt.textContent = countL3Terms(l2v);

  row.append(cbar, chev, badge, lbl, cnt);
  row.addEventListener('click', function(e) {
    e.stopPropagation();
    if (l3count > 0) toggleNode(l2k, wrap, chev);
    selectNode(l2k, l2v, 2, color, null);
  });
  wrap.appendChild(row);

  var ch = document.createElement('div');
  ch.className = 'nchildren' + (openNodes[l2k] ? '' : ' hidden');
  Object.entries(l2v.children || {}).forEach(function(entry) {
    ch.appendChild(makeL3(entry[0], entry[1], l2k, color));
  });
  wrap.appendChild(ch);
  return wrap;
}

function makeL3(l3k, l3v, l2k, color) {
  var wrap = document.createElement('div');
  wrap.className = 'tnode'; wrap.dataset.key = l3k; wrap.dataset.level = '3';

  var row = document.createElement('div');
  row.className = 'nrow' + (selected === l3k ? ' sel' : '');
  row.style.borderLeftColor = selected === l3k ? color : 'transparent';

  var chev = document.createElement('div');
  chev.className = 'chev leaf'; chev.textContent = '▶';

  var badge = document.createElement('div');
  badge.className = 'lvlbadge b3'; badge.textContent = 'L3';

  var lbl = document.createElement('div');
  lbl.className = 'nlabel nl3'; lbl.dataset.full = l3k;
  lbl.textContent = labelName(l3k);

  var cnt = document.createElement('div');
  cnt.className = 'cbadge'; cnt.textContent = (l3v.members || []).length;

  row.append(chev, badge, lbl, cnt);
  if (l3v.is_garbage) {
    var gtag = document.createElement('div');
    gtag.className = 'garbage-tag'; gtag.textContent = 'GARBAGE';
    row.appendChild(gtag);
  }
  row.addEventListener('click', function(e) {
    e.stopPropagation();
    selectNode(l3k, l3v, 3, color, l2k);
  });
  wrap.appendChild(row);
  return wrap;
}

function toggleNode(key, wrap, chevEl) {
  var ch = wrap.querySelector(':scope > .nchildren');
  if (!ch) return;
  if (openNodes[key]) {
    delete openNodes[key];
    ch.classList.add('hidden');
    chevEl.classList.remove('open');
  } else {
    openNodes[key] = true;
    ch.classList.remove('hidden');
    chevEl.classList.add('open');
  }
}

// ── Detail panel ──────────────────────────────────────────────
function selectNode(key, node, level, color, l2k) {
  selected = key;

  // Update sidebar selection
  document.querySelectorAll('.tnode').forEach(function(tn) {
    var row = tn.querySelector(':scope > .nrow');
    if (!row) return;
    var isSel = tn.dataset.key === key;
    row.classList.toggle('sel', isSel);
    row.style.borderLeftColor = isSel ? color : 'transparent';
  });

  var detail = document.getElementById('detail');
  var name = labelName(key);
  var desc = node.description || '';
  var levelLabel = level === 2 ? 'L2 — Category' : 'L3 — Fine-Grained Cluster';
  var levelClass = 'dl' + level;

  // Breadcrumb
  var bc = document.createElement('div'); bc.className = 'bc';
  if (level === 3 && l2k) {
    var b2 = document.createElement('span'); b2.className = 'bc-item';
    b2.textContent = labelName(l2k);
    b2.addEventListener('click', function() { navigateToKey(l2k); });
    var bsep = document.createElement('span'); bsep.className = 'bc-sep';
    bsep.textContent = '›';
    bc.append(b2, bsep);
  }
  var cur = document.createElement('span'); cur.className = 'bc-cur';
  cur.textContent = name;
  bc.appendChild(cur);

  var dtitle = document.createElement('div'); dtitle.className = 'dtitle';
  dtitle.textContent = name;
  var dlevel = document.createElement('div');
  dlevel.className = 'dlevel ' + levelClass; dlevel.textContent = levelLabel;
  var ddesc = document.createElement('div'); ddesc.className = 'ddesc';
  ddesc.textContent = desc;

  detail.innerHTML = '';
  detail.append(bc, dtitle, dlevel, ddesc);

  if (level === 3 && node.is_garbage) {
    var banner = document.createElement('div');
    banner.className = 'garbage-banner';
    banner.innerHTML = '<span>⚠</span><span>This cluster was flagged as <strong>garbage</strong> — it likely contains a significant proportion of non-methodological or unrelated terms.</span>';
    detail.appendChild(banner);
  }

  if (level === 3) {
    // Full member list
    var members = node.members || [];
    if (members.length) {
      var st = document.createElement('div'); st.className = 'sec-title';
      st.textContent = members.length + ' canonical terms';
      detail.appendChild(st);
      var chips = document.createElement('div'); chips.className = 'chips';
      members.forEach(function(m) {
        var chip = document.createElement('div'); chip.className = 'chip';
        chip.textContent = m;
        var f = FREQ[m];
        if (f) {
          var fr = document.createElement('span'); fr.className = 'chip-freq';
          fr.textContent = '\u00d7' + f;
          chip.appendChild(fr);
        }
        chips.appendChild(chip);
      });
      detail.appendChild(chips);
    }

  } else {
    // L2: show L3 children as cards
    var children = node.children || {};
    var childKeys = Object.keys(children);
    if (childKeys.length) {
      var st2 = document.createElement('div'); st2.className = 'sec-title';
      st2.textContent = childKeys.length + ' Fine-Grained Clusters (L3)';
      detail.appendChild(st2);
      var cards = document.createElement('div'); cards.className = 'cards';
      childKeys.forEach(function(ck) {
        var cv = children[ck];
        var card = document.createElement('div');
        card.className = 'card' + (cv.is_garbage ? ' is-garbage' : '');
        var bar = document.createElement('div');
        bar.className = 'card-bar';
        bar.style.background = cv.is_garbage ? '#e05555' : color;
        var t = document.createElement('div'); t.className = 'card-title';
        t.textContent = labelName(ck) + (cv.is_garbage ? ' ⚠' : '');
        var d = document.createElement('div'); d.className = 'card-desc';
        d.textContent = cv.description || '';
        var n = (cv.members || []).length;
        var meta = document.createElement('div'); meta.className = 'card-meta';
        meta.textContent = n + ' terms';
        card.append(bar, t, d, meta);
        card.addEventListener('click', function() { navigateToKey(ck); });
        cards.appendChild(card);
      });
      detail.appendChild(cards);
    }

    // Sample terms
    var sample = node.members_sample || [];
    if (sample.length) {
      var st3 = document.createElement('div'); st3.className = 'sec-title';
      st3.textContent = 'Sample terms';
      detail.appendChild(st3);
      var chips2 = document.createElement('div'); chips2.className = 'chips';
      sample.forEach(function(m) {
        var chip2 = document.createElement('div'); chip2.className = 'chip';
        chip2.textContent = m;
        var f2 = FREQ[m];
        if (f2) {
          var fr2 = document.createElement('span'); fr2.className = 'chip-freq';
          fr2.textContent = '\u00d7' + f2;
          chip2.appendChild(fr2);
        }
        chips2.appendChild(chip2);
      });
      detail.appendChild(chips2);
    }
  }
}

function navigateToKey(key) {
  // L2 lookup
  for (var i = 0; i < L2_KEYS.length; i++) {
    var l2k = L2_KEYS[i]; var l2v = T[l2k]; var color = PALETTE[i];
    if (l2k === key) {
      openNodes[l2k] = true; buildTree();
      selectNode(l2k, l2v, 2, color, null);
      scrollToKey(key); return;
    }
    // L3 lookup
    var l3entries = Object.entries(l2v.children || {});
    for (var j = 0; j < l3entries.length; j++) {
      var l3k = l3entries[j][0]; var l3v = l3entries[j][1];
      if (l3k === key) {
        openNodes[l2k] = true; buildTree();
        selectNode(l3k, l3v, 3, color, l2k);
        scrollToKey(key); return;
      }
    }
  }
}

function scrollToKey(key) {
  var node = document.querySelector(
    '.tnode[data-key="' + key.replace(/\\/g,'\\\\').replace(/"/g,'\\"') + '"] > .nrow'
  );
  if (node) node.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

// ── Search ────────────────────────────────────────────────────
document.getElementById('search').addEventListener('input', function() {
  filterTree(this.value.trim().toLowerCase());
});

function filterTree(q) {
  var nr = document.getElementById('noResults');
  if (!q) {
    document.querySelectorAll('.tnode').forEach(function(n) { n.style.display = ''; });
    nr.style.display = 'none';
    return;
  }

  var anyVisible = false;
  L2_KEYS.forEach(function(l2k) {
    var l2v = T[l2k];
    var l2node = document.querySelector(
      '#sidebar > .tnode[data-key="' + l2k.replace(/"/g,'\\"') + '"]'
    );
    if (!l2node) return;

    var l2Match = labelName(l2k).toLowerCase().includes(q) ||
                  (l2v.description || '').toLowerCase().includes(q);
    var anyL3 = false;

    Object.entries(l2v.children || {}).forEach(function(e3) {
      var l3k = e3[0]; var l3v = e3[1];
      var l3node = l2node.querySelector(
        ':scope > .nchildren > .tnode[data-key="' + l3k.replace(/"/g,'\\"') + '"]'
      );
      if (!l3node) return;
      var l3Match = labelName(l3k).toLowerCase().includes(q) ||
        (l3v.description || '').toLowerCase().includes(q) ||
        (l3v.members || []).some(function(m) { return m.toLowerCase().includes(q); });
      l3node.style.display = l3Match ? '' : 'none';
      if (l3Match) anyL3 = true;
    });

    var show2 = l2Match || anyL3;
    l2node.style.display = show2 ? '' : 'none';
    if (show2) {
      anyVisible = true;
      if (anyL3) {
        var ch = l2node.querySelector(':scope > .nchildren');
        if (ch) ch.classList.remove('hidden');
      }
    }
  });

  nr.style.display = anyVisible ? 'none' : 'block';
}

// ── Init ──────────────────────────────────────────────────────
buildTree();
</script>
</body>
</html>
"""


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    p = argparse.ArgumentParser(description="Generate standalone taxonomy explorer HTML")
    p.add_argument("--input",  default="taxonomy_descriptions.json",
                   help="Path to taxonomy_descriptions.json")
    p.add_argument("--csv",    default="taxonomy_results.csv",
                   help="Path to taxonomy_results.csv (for term frequencies)")
    p.add_argument("--output", default="taxonomy_explorer.html",
                   help="Output HTML file path")
    args = p.parse_args()

    base = Path(__file__).parent
    input_path  = Path(args.input)  if Path(args.input).is_absolute()  else base / args.input
    csv_path    = Path(args.csv)    if Path(args.csv).is_absolute()    else base / args.csv
    output_path = Path(args.output) if Path(args.output).is_absolute() else base / args.output

    print(f"Loading  : {input_path}")
    with open(input_path, encoding="utf-8") as f:
        taxonomy = json.load(f)

    print(f"Loading  : {csv_path}")
    freq = load_freq(csv_path)

    # Rimuovi L2 senza figli L3
    empty_l2 = [k for k, v in taxonomy.items() if not v.get("children")]
    if empty_l2:
        print(f"  Rimossi {len(empty_l2)} L2 vuoti: {', '.join(empty_l2)}")
        for k in empty_l2:
            del taxonomy[k]

    stats    = compute_stats(taxonomy)
    t_json   = json.dumps(taxonomy, ensure_ascii=False, separators=(",", ":"))
    f_json   = json.dumps(freq,     ensure_ascii=False, separators=(",", ":"))
    gen_date = datetime.now().strftime("%Y-%m-%d %H:%M")

    html = HTML_TEMPLATE
    html = html.replace("TAXONOMY_JSON", t_json)
    html = html.replace("FREQ_JSON",     f_json)
    html = html.replace("STAT_L2",       str(stats["l2"]))
    html = html.replace("STAT_L3",       str(stats["l3"]))
    html = html.replace("STAT_TERMS",    str(stats["terms"]))
    html = html.replace("STAT_GARBAGE",  str(stats["garbage"]))
    html = html.replace("GEN_DATE",      gen_date)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"Generated: {output_path}")
    print(f"  L2={stats['l2']}  L3={stats['l3']}  Terms={stats['terms']}")
    print(f"  File size: {output_path.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()