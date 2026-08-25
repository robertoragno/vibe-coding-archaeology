# concentration_cluster_bootstrap.R
# How much do the concentration intervals (06_concentration.R) widen once we
# stop pretending every recommendation is independent?
#
# The main concentration analysis treats each L3 count as an independent
# multinomial draw. It is not: a single LLM response lists ~7-10 methods at
# once, and a single paper contributes several methods. Counts that travel in
# bundles carry less information than the same number of independent counts, so
# the reported credible intervals are too narrow.
#
# To measure by how much, we hold the estimator fixed (a nonparametric
# bootstrap of the inverse Simpson index) and change only the resampling unit:
#   - independent bootstrap: resample individual recommendations / paper-method
#     rows. This reproduces the independence assumption of the main analysis.
#   - cluster bootstrap: resample whole responses (LLM) or whole papers
#     (literature), keeping each bundle intact. This respects the correlation.
# The widening factor is the ratio of the two interval widths; the design
# effect (deff) is the ratio of the two variances, and the interval widens by
# about sqrt(deff).
#
# Reads:  experiment CSVs, vocab.rds, stan_data.rds, the two taxonomy_v3 files.
# Writes: data/output/sensitivity/concentration_cluster_bootstrap.csv

suppressPackageStartupMessages({
  library(here)
  library(readxl)
  library(dplyr)
})

source(here("R/helpers.R"))  # inv_simpson

set.seed(42)
N_BOOT <- 2000

QWEN_CSV   <- here("experiment/analysis/experiment_results_QWEN.csv")
GEMMA_CSV  <- here("experiment/analysis/experiment_results_GEMMA.csv")
VOCAB_RDS  <- here("data/output/vocab.rds")
SCOPUS_XLSX   <- here("data/input/taxonomy_v3/df_cleaned.xlsx")
TAXONOMY_CSV  <- here("data/input/taxonomy_v3/taxonomy_abstract_join.csv")
OUT_CSV    <- here("data/output/sensitivity/concentration_cluster_bootstrap.csv")
dir.create(dirname(OUT_CSV), recursive = TRUE, showWarnings = FALSE)

vocab     <- readRDS(VOCAB_RDS)
l3_levels <- (vocab$l3_vocab |> arrange(g, k_local))$l3
K         <- length(l3_levels)

# Turn a vector of L3 labels into an inverse Simpson value over the fixed
# K-method vocabulary. Labels outside the vocabulary are ignored.
inv_simpson_from_labels <- function(labels) {
  tab <- table(factor(labels, levels = l3_levels))
  p   <- as.numeric(tab) / sum(tab)
  inv_simpson(p)
}

# One bootstrap distribution of the inverse Simpson index, resampling either
# the individual rows ("indep") or the cluster ids ("cluster"). `cluster` is a
# vector of cluster ids aligned with `labels`.
boot_inv_simpson <- function(labels, cluster, unit = c("indep", "cluster")) {
  unit <- match.arg(unit)
  out  <- numeric(N_BOOT)
  if (unit == "indep") {
    n <- length(labels)
    for (b in seq_len(N_BOOT)) {
      idx    <- sample.int(n, n, replace = TRUE)
      out[b] <- inv_simpson_from_labels(labels[idx])
    }
  } else {
    by_cluster <- split(labels, cluster)
    ids        <- names(by_cluster)
    m          <- length(ids)
    for (b in seq_len(N_BOOT)) {
      drawn  <- sample.int(m, m, replace = TRUE)
      out[b] <- inv_simpson_from_labels(unlist(by_cluster[drawn], use.names = FALSE))
    }
  }
  out
}

# Summarise one source: point estimate, both bootstrap intervals, and the
# widening factor (cluster interval width / independent interval width).
summarise_source <- function(name, labels, cluster) {
  point     <- inv_simpson_from_labels(labels)
  d_indep   <- boot_inv_simpson(labels, cluster, "indep")
  d_cluster <- boot_inv_simpson(labels, cluster, "cluster")
  ci_indep  <- quantile(d_indep,   c(0.05, 0.95))
  ci_clust  <- quantile(d_cluster, c(0.05, 0.95))
  w_indep   <- diff(ci_indep)
  w_clust   <- diff(ci_clust)
  data.frame(
    source        = name,
    n_obs         = length(labels),
    n_clusters    = length(unique(cluster)),
    inv_simpson   = round(point, 1),
    ci_indep      = sprintf("[%.1f, %.1f]", ci_indep[1], ci_indep[2]),
    ci_cluster    = sprintf("[%.1f, %.1f]", ci_clust[1], ci_clust[2]),
    deff          = round(var(d_cluster) / var(d_indep), 2),
    widen_factor  = round(w_clust / w_indep, 2),
    row.names     = NULL
  )
}

# LLM sources: cluster = one response (iteration x profile)

read_llm <- function(csv_path, model_name) {
  raw <- read.csv(csv_path, stringsAsFactors = FALSE) |>
    filter(toupper(as.character(l3_mapping_consistent)) == "TRUE",
           l3_mapping %in% l3_levels)
  out <- list()
  for (prof in c("novice", "intermediate", "expert")) {
    sub <- raw |> filter(profile == prof)
    out[[paste(model_name, prof)]] <-
      summarise_source(paste(model_name, "-", prof), sub$l3_mapping, sub$iteration)
  }
  # Overall pools the three profiles; a response is then iteration x profile.
  out[[paste(model_name, "overall")]] <-
    summarise_source(paste(model_name, "- overall"),
                     raw$l3_mapping, paste(raw$iteration, raw$profile))
  bind_rows(out)
}

# Literature sources: cluster = one paper (eid)
# Rebuild the same paper-method table 00_data_prep.R feeds to Stan, so the
# bootstrap runs on exactly the corpus the reported intervals come from.

build_literature <- function() {
  scopus <- read_excel(SCOPUS_XLSX) |> select(eid, Year = year)
  tax    <- read.csv(TAXONOMY_CSV, stringsAsFactors = FALSE) |>
    filter(is_garbage == "False") |>
    select(eid, l2, l3)
  scopus |>
    inner_join(tax, by = "eid") |>
    filter(Year >= 2010, Year <= 2025) |>
    distinct(eid, Year, l2, l3) |>
    filter(l3 %in% l3_levels)   # drops singleton-L2 methods absent from the vocab
}

lit <- build_literature()
lit_pre  <- lit |> filter(Year <  2023)
lit_post <- lit |> filter(Year >= 2023)

results <- bind_rows(
  read_llm(QWEN_CSV,  "Qwen3"),
  read_llm(GEMMA_CSV, "Gemma"),
  summarise_source("Pre-2023 literature",  lit_pre$l3,  lit_pre$eid),
  summarise_source("Post-2023 literature", lit_post$l3, lit_post$eid)
)

cat("\n=== Concentration intervals: independent vs response/paper clustering ===\n")
print(results, row.names = FALSE)

rng <- range(results$widen_factor)
cat(sprintf("\nWidening factor across all sources: %.2f-%.2f\n", rng[1], rng[2]))

write.csv(results, OUT_CSV, row.names = FALSE)
cat("Saved:", OUT_CSV, "\n")
