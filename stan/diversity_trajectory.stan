data {
  int<lower=1> N_groups;
  int<lower=1> N_years;
  vector[N_years] year_std;
  array[N_years] int post_llm;
  matrix[N_groups, N_years] obs_diversity;
  matrix[N_groups, N_years] meas_sd;
}

parameters {
  vector[N_groups] alpha;
  vector[N_groups] beta_raw;
  real<lower=0> sigma_beta;
  vector[N_groups] gamma_raw;
  real<lower=0> sigma_gamma;
  real<lower=0> sigma_resid;
}

transformed parameters {
  vector[N_groups] beta  = sigma_beta  * beta_raw;
  vector[N_groups] gamma = sigma_gamma * gamma_raw;
}

model {
  alpha ~ normal(0, 1);
  beta_raw  ~ normal(0, 1);
  gamma_raw ~ normal(0, 1);
  sigma_beta  ~ normal(0, 0.5);
  sigma_gamma ~ normal(0, 0.5);
  sigma_resid ~ normal(0, 0.5);

  for (g in 1:N_groups) {
    for (t in 1:N_years) {
      if (obs_diversity[g, t] > 0) {
        real mu = alpha[g] + beta[g] * year_std[t]
                  + gamma[g] * post_llm[t];
        real total_sd = sqrt(square(meas_sd[g, t]) + square(sigma_resid));
        obs_diversity[g, t] ~ normal(mu, total_sd);
      }
    }
  }
}
