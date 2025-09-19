#!/usr/bin/env python3

import os
import subprocess
import itertools
from tqdm import tqdm
import argparse

OBJS_PER_TXN = [1, 2, 4, 8, 16]
WRITE_PROBS = [0.0, 0.25, 0.5, 0.75]
ZIPF_PARAMS = [0, 0.2, 0.4, 0.6, 0.8, 1.0]
ADDR_SPACE_SIZE = 20_000_000
NUM_TXNS = 1_000_000


def generate_filename(
    num_objs_per_txn, write_prob, zipf_param, addr_space, num_txns, is_split
):
    ret = f"size_{num_objs_per_txn}_write_{int(write_prob * 100):02d}_zipf_{int(zipf_param * 100):02d}_addr_{addr_space}_txns_{num_txns}.csv"
    if is_split:
        ret = "split_" + ret
    return ret


def generate_all_workloads(output_dir="workloads", use_binary=False, use_split=False):
    os.makedirs(output_dir, exist_ok=True)

    cases = list(itertools.product(ZIPF_PARAMS, WRITE_PROBS, OBJS_PER_TXN))
    cases.append((0, 0, 0))  # special zero-object case

    ext = ".bin" if use_binary else ".csv"
    mode = "bin" if use_binary else "csv"

    for zipf_param, write_prob, num_objs in tqdm(cases):
        filename_base = generate_filename(
            num_objs, write_prob, zipf_param, ADDR_SPACE_SIZE, NUM_TXNS, use_split
        )
        filepath = os.path.join(output_dir, filename_base.replace(".csv", ext))

        if not use_split:
            cmd = [
                "./bin/generate",
                mode,
                filepath,
                str(NUM_TXNS),
                str(num_objs),
                str(ADDR_SPACE_SIZE),
                str(zipf_param),
                str(write_prob),
            ]
        else:
            num_writes = int(num_objs * write_prob)
            num_reads = num_objs - num_writes
            cmd = [
                "./bin/generate",
                mode,
                filepath,
                str(NUM_TXNS),
                str(num_objs),
                str(ADDR_SPACE_SIZE),
                str(zipf_param),
                str(num_reads),
                str(num_writes),
            ]

        subprocess.run(cmd, check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--csv", action="store_true", help="Generate .csv files instead of .bin"
    )
    parser.add_argument(
        "--split",
        action="store_true",
        help="Generate transactions with exact read/write split",
    )
    parser.add_argument("--out", type=str, default="workloads", help="Output directory")
    args = parser.parse_args()

    generate_all_workloads(
        output_dir=args.out, use_binary=not args.csv, use_split=args.split
    )
