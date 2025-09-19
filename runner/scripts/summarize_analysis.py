#!/usr/bin/env python3
import csv
import dotenv
import os
from visualize import read_binary_output

dotenv.load_dotenv()

PROJECT_ROOT = os.getenv("PROJECT_ROOT")
RUNNER_PATH = f"{PROJECT_ROOT}/runner"

if __name__ == "__main__":
    with open(f"{RUNNER_PATH}/analysis_summary.csv", "w", newline="") as csvfile:
        fieldnames = [
            "analysis_file",
            "total_txns",
            "complete_txns",
            "filtered_count",
            "num_buckets",
            "cpu_freq",
            "num_puppets",
            "average_throughput",
            "num_throughput_windows",
            "window_seconds",
            "submit_throughput",
            "sched_throughput",
            "recv_throughput",
            "done_throughput",
            "cleanup_throughput",
            "e2e_unit",
            "submit_sched_unit",
            "sched_recv_unit",
            "recv_done_unit",
            "done_cleanup_unit",
            "e2e_histogram",
            "submit_sched_histogram",
            "sched_recv_histogram",
            "recv_done_histogram",
            "done_cleanup_histogram",
        ]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

        writer.writeheader()
        for analysis_file in sorted(os.listdir(f"{RUNNER_PATH}/analysis")):
            if not analysis_file.endswith(".bin"):
                continue
            print(f"Summarizing {analysis_file}...")

            writer.writerow(
                read_binary_output(f"{RUNNER_PATH}/analysis/{analysis_file}")
                | {"analysis_file": analysis_file}
            )
