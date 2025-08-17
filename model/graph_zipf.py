#!/usr/bin/env python3

from workload import *
import matplotlib.pyplot as plt
import numpy as np

def graph_zipf():
  plt.rcParams.update({'figure.autolayout': True})
  filename = "output-zipf-top-10.svg"
  plt.figure(figsize=(6 * 3/4, 4 * 3/4), dpi=200)
  plt.grid()

  # The figure in my thesis used 10_000_000
  num_records = 1000000
  top_k = int(num_records * 0.1)
  thetas = np.linspace(0.0, 1.3, num=100)
  top_k_fractions = []

  for theta in thetas:
    weights = make_zipf_weights(num_records, theta)
    weights /= weights.sum()
    top_k_fraction = weights[:top_k].sum()
    top_k_fractions.append(top_k_fraction)

  plt.plot(thetas, top_k_fractions)
  plt.xlabel("Zipf parameter θ")
  plt.ylabel("Fraction in top 10%")
  plt.ylim(0.0, 1.0)

  plt.savefig(filename, bbox_inches="tight")

if __name__ == "__main__":
  graph_zipf()

