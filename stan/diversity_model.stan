functions {
  real dm_log(array[] int n, vector alpha) {
    real a0 = sum(alpha);
    int N = sum(n);
    return lgamma(a0) - lgamma(a0 + N)
         + sum(lgamma(alpha + to_vector(n))) - sum(lgamma(alpha));
  }
}

data {
  int<lower=1> N_groups;
  int<lower=1> N_years;
  int<lower=1> K_max;
  array[N_groups] int<lower=1> K_g;
  array[N_groups, N_years, K_max] int<lower=0> counts;
  real<lower=0> kappa;
  vector[N_years] year_std;
  array[N_years] int post_llm;
}

parameters {
  array[N_groups] vector[K_max] mu_raw;
  array[N_groups] vector[K_max] beta_method_raw;
  real<lower=0> sigma_beta;
  array[N_groups] vector[K_max] gamma_method_raw;
  real<lower=0> sigma_gamma;
}

transformed parameters {
  // Non-centred reparameterisation for both slope parameters
  array[N_groups] vector[K_max] beta_method;
  array[N_groups] vector[K_max] gamma_method;
  for (g in 1:N_groups) {
    beta_method[g]  = sigma_beta  * beta_method_raw[g];
    gamma_method[g] = sigma_gamma * gamma_method_raw[g];
  }
}

model {
  // Hyperpriors: tighter on gamma (post-LLM shift expected smaller)
  sigma_beta  ~ exponential(2);
  sigma_gamma ~ exponential(4);

  for (g in 1:N_groups) {
    int K = K_g[g];

    // Baseline log-weights: weakly informative + soft sum-to-zero
    mu_raw[g][1:K] ~ normal(0, 1);
    sum(mu_raw[g][1:K]) ~ normal(0, 0.001 * K);

    // Baseline linear slopes: non-centred hierarchy + soft sum-to-zero
    beta_method_raw[g][1:K] ~ normal(0, 1);
    sum(beta_method_raw[g][1:K]) ~ normal(0, 0.001 * K);

    // Post-LLM differential slopes: non-centred hierarchy + soft sum-to-zero
    gamma_method_raw[g][1:K] ~ normal(0, 1);
    sum(gamma_method_raw[g][1:K]) ~ normal(0, 0.001 * K);

    // Pin padding slots to near-zero
    if (K < K_max) {
      mu_raw[g][(K+1):K_max]           ~ normal(0, 0.001);
      beta_method_raw[g][(K+1):K_max]  ~ normal(0, 0.001);
      gamma_method_raw[g][(K+1):K_max] ~ normal(0, 0.001);
    }
  }

  for (g in 1:N_groups) {
    int K = K_g[g];
    for (t in 1:N_years) {
      if (sum(counts[g, t, 1:K]) == 0) continue;

      vector[K] eta   = mu_raw[g][1:K]
                        + beta_method[g][1:K]  * year_std[t]
                        + gamma_method[g][1:K] * post_llm[t];
      vector[K] alpha = softmax(eta) * kappa;
      array[K] int y  = counts[g, t, 1:K];

      target += dm_log(y, alpha);
    }
  }
}

generated quantities {
  matrix[N_groups, N_years] inv_simpson;
  matrix[N_groups, N_years] eff_N_shannon;

  for (g in 1:N_groups) {
    int K = K_g[g];
    for (t in 1:N_years) {
      vector[K] eta = mu_raw[g][1:K]
                      + beta_method[g][1:K]  * year_std[t]
                      + gamma_method[g][1:K] * post_llm[t];

      int N_gt = sum(counts[g, t, 1:K]);
      vector[K] p;

      if (N_gt > 0) {
        vector[K] y_k;
        for (k in 1:K) y_k[k] = counts[g, t, k];
        p = dirichlet_rng(softmax(eta) * kappa + y_k);
      } else {
        p = softmax(eta);
      }

      inv_simpson[g, t]   = 1.0 / dot_self(p);
      eff_N_shannon[g, t] = exp(-dot_product(p, log(p)));
    }
  }
}
