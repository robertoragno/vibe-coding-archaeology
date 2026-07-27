# helpers.R
# Shared functions sourced by the analysis scripts.
# Assumes the sourcing script has already attached dplyr.

# Effective number of equally-frequent methods (Inverse Simpson).
inv_simpson <- function(p) 1 / sum(p^2)

# Numerically stable softmax.
softmax_r <- function(x) {
  ex <- exp(x - max(x))
  ex / sum(ex)
}

# Build per-profile L3 recommendation count vectors from an experiment CSV.
# Returns a named list: novice, intermediate, expert, and overall (their sum).
# Only rows with a consistent L3 mapping are counted.
build_rec_vectors <- function(csv_path, l3_levels) {
  raw <- read.csv(csv_path, stringsAsFactors = FALSE)
  con <- raw |> filter(toupper(as.character(l3_mapping_consistent)) == "TRUE")

  profiles <- c("novice", "intermediate", "expert")
  result   <- list()
  for (prof in profiles) {
    df  <- con |> filter(profile == prof) |> count(l3 = l3_mapping, name = "n")
    vec <- setNames(rep(0L, length(l3_levels)), l3_levels)
    matched <- df$l3[df$l3 %in% l3_levels]
    vec[matched] <- df$n[match(matched, df$l3)]
    result[[prof]] <- vec
  }
  result[["overall"]] <- result[["novice"]] + result[["intermediate"]] + result[["expert"]]
  result
}
