// nb2_prevalence_gamma.stan
//
// Two-predictor negative-binomial regression separating training-corpus
// prevalence from post-2023 trajectory:
//
//   n_rec[i] ~ NegBin2(exp(alpha + b_pre * x_pre[i] + b_gamma * gamma[i]), phi)
//
// x_pre[i]   = log1p(pre-2023 literature count) for method i
// gamma[i]   = signed posterior mean gamma (post-2023 excess above trend)
//
// b_pre > 0   means the LLM recommends methods proportional to their
//             pre-2023 corpus footprint (training-data reflection).
// b_gamma > 0 means the LLM additionally favours methods that gained
//             share post-2023 beyond the pre-existing trend (mean-collapse).

data {
  int<lower=1> M;
  vector[M] x_pre;              // log1p(pre-2023 count) per method
  vector[M] gamma_signed;       // signed posterior mean gamma per method
  array[M] int<lower=0> n_rec;  // LLM recommendation count per method
}

parameters {
  real alpha;
  real b_pre;
  real b_gamma;
  real<lower=0> phi;
}

model {
  alpha   ~ normal(0, 2);
  b_pre   ~ normal(0, 1);
  b_gamma ~ normal(0, 1);
  phi     ~ exponential(1);

  for (i in 1:M)
    n_rec[i] ~ neg_binomial_2_log(
      alpha + b_pre * x_pre[i] + b_gamma * gamma_signed[i],
      phi
    );
}
