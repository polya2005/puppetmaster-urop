#!/usr/bin/env python3

import time
import itertools
import sys
import numpy as np
import matplotlib.pyplot as plt
import functools

from typing import *
from concurrent.futures import ProcessPoolExecutor

from workload import Transaction, make_workload
from scheduler import Scheduler, GreedyScheduler, TournamentScheduler

SchedType = Literal["greedy", "tournament"]
SCHED_TYPES = ["greedy", "tournament"]

NUM_OBJS_PER_TXN = 8  # For my thesis figures, I manually ran with 8 and then with 16.
NUM_TXNS = 2**10      # For my thesis figures, I used 2**12.
LOG_SIM_BOUND = 12    # For my thesis figures, I used 25. It takes a very long time, but makes the plots more accurate.

def _get_num_txns_scheduled(mem_size: int, zipf_param: float, write_prob: float, sched_type: SchedType):
  addr_space = np.arange(mem_size)
  workload = list(make_workload(addr_space, NUM_TXNS, NUM_OBJS_PER_TXN, zipf_param, write_prob))

  s: Scheduler
  if sched_type == "greedy":
    s = GreedyScheduler()
  elif sched_type == "tournament":
    s = TournamentScheduler()

  return len(s.schedule(workload))

def get_num_txns_scheduled(mem_size: float, zipf_param: float, write_prob: float, sched_type: SchedType):
  num_trials = 10
  with ProcessPoolExecutor() as exec:
    y = list(exec.map(_get_num_txns_scheduled,
                      [mem_size] * num_trials,
                      [zipf_param] * num_trials,
                      [write_prob] * num_trials,
                      [sched_type] * num_trials))
  return np.mean(y, axis=0)

def graph_scale_num_objs():
  plt.rcParams.update({'figure.autolayout': True})

  for workload_type, omega in [('Read-heavy', 0.05), ('Write-heavy', 0.50)]:
    filename = f"output-scheduler-{workload_type.lower()}-{NUM_TXNS}x{NUM_OBJS_PER_TXN}.svg"
    print(f"Rendering: {filename}", file=sys.stderr)
    begin = time.time()
    plt.figure(figsize=(6 * 3/4, 4 * 3/4), dpi=200)
    plt.title(f"{workload_type}: {NUM_OBJS_PER_TXN} objs/txn, $\\omega = {omega:.2f}$")
    plt.xlabel("Number of records ($N$)")
    plt.ylabel(f"Scheduled (max: {NUM_TXNS})")
    plt.xscale("log", base=2)
    plt.yscale("linear")
    plt.grid()

    for sched_type, line in zip(SCHED_TYPES, ["--", "-"]):
      for theta in [0.0, 0.6, 0.8]:
        x = 2**np.arange(10,LOG_SIM_BOUND,1)
        y = np.array(list(map(get_num_txns_scheduled,
                              x,
                              itertools.repeat(theta),
                              itertools.repeat(omega),
                              itertools.repeat(sched_type))))
        plt.plot(x, y, line, label=f"$\\theta = {theta}$, {sched_type}")

    plt.legend()
    end = time.time()
    print(f"Done: {filename} {end-begin} seconds", file=sys.stderr)
    plt.savefig(filename, bbox_inches="tight")

if __name__ == "__main__":
  graph_scale_num_objs()
