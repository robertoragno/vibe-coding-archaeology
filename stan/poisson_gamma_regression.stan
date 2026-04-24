// poisson_gamma_regression.stan
//
// Bayesian negative-binomial regression:
//   n_rec[i] ~ NegBin2(exp(alpha + beta * gamma_signed[i]), phi)
//
// gamma_signed[i] = mean_gamma[i] from the main two-slope model posterior
// (signed, not absolute value). Using signed gamma is the correct test of the
// mean-collapse hypothesis: beta > 0 means LLMs specifically recommend methods
// that *gained* share post-2023, which is the directional prediction.
//
// Using the posterior mean directly (rather than a latent variable layer)
// avoids the non-identifiability that arose when 186 free gamma_true parameters
// were jointly estimated with beta.
//
// Key estimand: beta > 0 means LLMs preferentially recommend methods gaining
// post-2023 share; beta < 0 means they favour declining methods; beta ≈ 0
// means recommendations are indifferent to post-2023 trajectory.

data {
  int<lower=1> M;
  vector[M] gamma_signed;               // mean_gamma per method (signed)
  array[M] int<lower=0> n_rec;          // LLM recommendation count per method
}

parameters {
  real alpha;                           // log-rate intercept
  real beta;                            // effect of signed mean_gamma on log rate
  real<lower=0> phi;                    // NB overdispersion (larger = less dispersed)
}

model {
  alpha ~ normal(0, 2);
  beta  ~ normal(0, 1);
  phi   ~ exponential(1);

  for (i in 1:M)
    n_rec[i] ~ neg_binomial_2_log(alpha + beta * gamma_signed[i], phi);
}
