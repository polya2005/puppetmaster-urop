#!/usr/bin/env python3
import argparse
import csv
import dotenv
import os
from rich import print
from rich.progress import track
from visualize import read_binary_output, generate_pdf_report

dotenv.load_dotenv()

PROJECT_ROOT = os.getenv("PROJECT_ROOT")
RUNNER_PATH = f"{PROJECT_ROOT}/runner"

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Summarize analysis results into a CSV file."
    )
    parser.add_argument(
        "analysis_dir", type=str, help="Directory containing analysis files"
    )
    args = parser.parse_args()
    os.chdir(args.analysis_dir)
    if not os.path.exists("summary"):
        os.mkdir("summary")
    with open("summary/analysis_summary.csv", "w", newline="") as csvfile:
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
        for analysis_file in track(
            sorted(os.listdir(".")), description="Processing analysis files..."
        ):
            if not analysis_file.endswith(".bin"):
                continue
            print(f"Summarizing {analysis_file}...")

            analysis_data = read_binary_output(analysis_file)
            writer.writerow(analysis_data | {"analysis_file": analysis_file})

            print(f"Generating PDF report for {analysis_file}...")
            generate_pdf_report(
                analysis_data, f"summary/{analysis_file[:-4]}_report.pdf"
            )
        print("Summary written to summary/analysis_summary.csv")
