// poisson_gamma_regression.stan
// Bayesian Poisson regression: LLM recommendation count ~ |gamma_true|
//
// gamma_true is a latent variable with a Normal prior centred on the
// posterior summary (mean_gamma, sd_gamma) from the main Stan model.
// This propagates predictor uncertainty into the posterior of beta via
// sequential Bayesian updating: stage-1 posterior becomes stage-2 prior.
//
// The key estimand is beta: a positive value means methods with larger
// post-2023 deviation are recommended more often by LLMs.

data {
  int<lower=1> M;                      // number of L3 methods
  vector[M] gamma_mean;                // posterior mean gamma from main model
  vector<lower=0>[M] gamma_sd;         // posterior SD  gamma from main model
  array[M] int<lower=0> n_rec;         // LLM recommendation count per method
}

parameters {
  real alpha;                          // Poisson log-rate intercept
  real beta;                           // effect of |gamma_true| on log recommendation rate
  vector[M] gamma_true;                // latent true gamma per method
}

model {
  // Weakly informative priors on regression coefficients
  alpha ~ normal(0, 2);
  beta  ~ normal(0, 1);

  // Normal approximation to stage-1 gamma posterior as prior on gamma_true
  gamma_true ~ normal(gamma_mean, gamma_sd);

  // Poisson likelihood
  for (i in 1:M)
    n_rec[i] ~ poisson_log(alpha + beta * fabs(gamma_true[i]));
}
