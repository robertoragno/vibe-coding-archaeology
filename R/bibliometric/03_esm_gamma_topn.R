# Compact gamma dotplot for the ESM: the 20 L3 methods with the largest
# posterior mean |gamma|. The full 241-method version is a 36-inch strip and
# unusable in the PDF; this shows the methods that come closest to a credible
# post-2023 shift, and their 90% intervals still all cover zero.

suppressPackageStartupMessages(library(ggplot2))

GAMMA_CSV <- here::here("data/output/phi_free/gamma_results.csv")
OUT_PNG   <- here::here("data/output/figures/l2_l3/esm_gamma_top20.png")
N_SHOW    <- 20

g <- read.csv(GAMMA_CSV, stringsAsFactors = FALSE)

g$label <- sub("^L3-[0-9]+: ", "", g$l3)
g <- g[order(-abs(g$mean_gamma)), ]
top <- head(g, N_SHOW)
top <- top[order(top$mean_gamma), ]
top$label <- factor(top$label, levels = top$label)

n_cross <- sum(top$lo90 <= 0 & top$hi90 >= 0)
stopifnot(n_cross == N_SHOW)

p <- ggplot(top, aes(x = mean_gamma, y = label)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey55", linewidth = 0.4) +
  geom_errorbarh(aes(xmin = lo90, xmax = hi90), height = 0.3,
                 colour = "grey40", linewidth = 0.4) +
  geom_point(size = 1.8, colour = "black") +
  labs(x = expression("Posterior mean " * gamma * " (post-2023 differential slope)"),
       y = NULL) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.major.y = element_blank(),
        panel.grid.minor.x = element_blank())

ggsave(OUT_PNG, p, width = 8, height = 5, units = "in", dpi = 300, bg = "white")
cat("Saved", OUT_PNG, "\n")
cat("All", N_SHOW, "shown methods have a 90% CI covering zero:", n_cross == N_SHOW, "\n")
