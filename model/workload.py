from typing import *
from dataclasses import dataclass
from bloom_filter import Set, make_parallel_bloom_filter_family
import itertools
import random
import numpy as np
import matplotlib.pyplot as plt
from tqdm import tqdm
import os
import csv
import struct
from multiprocessing import Pool, cpu_count

@dataclass(frozen=True)
class Transaction:
  ids: frozenset[int]
  read_set: frozenset[int]
  write_set: frozenset[int]

  def compat(ts1: Self, ts2: Self) -> bool:
    r1w2_set = ts1.read_set & ts2.write_set
    w1r2_set = ts1.write_set & ts2.read_set
    w1w2_set = ts1.write_set & ts2.write_set
    conflicts = r1w2_set | w1r2_set | w1w2_set
    return not bool(conflicts)

  def merge(ts1: Self, ts2: Self) -> Self:
    assert ts1.compat(ts2), "Can only merge compatible transactions"
    return Transaction(
      ids = ts1.ids | ts2.ids,
      read_set = ts1.read_set | ts2.read_set,
      write_set = ts1.write_set | ts2.write_set
    )

def make_zipf_weights(n: int, alpha: float, cache={}) -> np.array:
  key = (n, alpha)
  if key not in cache:
    cache[key] = 1.0 / (np.arange(n) + 1)**alpha
  return cache[key]

def _build_single_txn(args):
  txn_id, objs, writes = args
  write_set = frozenset(obj for obj, write in zip(objs, writes) if write)
  read_set = frozenset(obj for obj, write in zip(objs, writes) if not write)
  return Transaction(ids=frozenset({txn_id}), read_set=read_set, write_set=write_set)

def make_workload(addr_space: np.array, num_txn: int, num_elems_per_txn: int, zipf_param: float, write_probability: float) -> List[Transaction]:
  if num_elems_per_txn == 0:
    # Special case: return empty read/write sets
    return [Transaction(ids=frozenset({i}), read_set=frozenset(), write_set=frozenset()) for i in range(num_txn)]

  zipf = make_zipf_weights(len(addr_space), zipf_param)
  total_objs = num_txn * num_elems_per_txn

  all_objs = random.choices(population=addr_space, weights=zipf, k=total_objs)
  all_writes = random.choices(population=[False, True], weights=[1 - write_probability, write_probability], k=total_objs)

  obj_matrix = np.array(all_objs).reshape((num_txn, num_elems_per_txn))
  write_matrix = np.array(all_writes).reshape((num_txn, num_elems_per_txn))

  args = [(i, obj_matrix[i], write_matrix[i]) for i in range(num_txn)]

  with Pool(processes=cpu_count()) as pool:
    txns = pool.map(_build_single_txn, args)

  return txns

def compress_transaction(transaction: Transaction, family: Callable[[], Set]) -> Transaction:
  """
  Compress transaction from exact set representation into bloom filter representation
  """
  read_set = family()
  for obj in transaction.read_set:
    read_set.add(obj)
  write_set = family()
  for obj in transaction.write_set:
    write_set.add(obj)
  new_txn = Transaction(ids=transaction.ids, read_set=read_set, write_set=write_set)
  return new_txn

def compress_workload(workload: list[Transaction], family: Callable[[], Set]) -> list[Transaction]:
  """
  Compress a workload from exact set representation into bloom filter representation
  """
  return [compress_transaction(txn, family) for txn in workload]

def export_workload_to_csv(transactions: List[Transaction], filename: str):
  with open(filename, mode='w', newline='') as f:
    writer = csv.writer(f)
    for txn_id, txn in enumerate(transactions):
      row = [txn_id, 0]
      for obj in txn.read_set:
        row.extend([obj, 0])
      for obj in txn.write_set:
        row.extend([obj, 1])
      writer.writerow(row)

def generate_filename(num_objs_per_txn: int, write_prob: float, zipf_param: float,
                      addr_space: int, num_txns: int) -> str:
  return f"size_{num_objs_per_txn}_write_{int(write_prob * 100):02d}_zipf_{int(zipf_param * 100):02d}_addr_{addr_space}_txns_{num_txns}.csv"

OBJS_PER_TXN = [8, 16]
WRITE_PROBS = [0.05, 0.5]
ZIPF_PARAMS = [0, 0.6, 0.8]
ADDR_SPACE_SIZE = 20_000_000
NUM_TXNS = 1_000_000

def generate_all_workloads(output_dir: str = "workloads"):
  os.makedirs(output_dir, exist_ok=True)
  addr_space = np.arange(ADDR_SPACE_SIZE)

  cases = list(itertools.product(ZIPF_PARAMS, WRITE_PROBS, OBJS_PER_TXN))
  cases.append((0, 0, 1))  # special zero-object case

  for zipf_param, write_prob, num_objs in tqdm(cases):
    txns = make_workload(addr_space, NUM_TXNS, num_objs, zipf_param, write_prob)
    filename = generate_filename(num_objs, write_prob, zipf_param, ADDR_SPACE_SIZE, NUM_TXNS)
    filepath = os.path.join(output_dir, filename)

    export_workload_to_csv(txns, filepath)

if __name__ == "__main__":
  generate_all_workloads()
