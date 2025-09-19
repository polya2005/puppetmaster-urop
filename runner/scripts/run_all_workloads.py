#!/usr/bin/env python3

import argparse
import asyncio
import dotenv
import itertools
import os
from tqdm import tqdm
from dataclasses import dataclass
import dataclasses
from typing import Optional


dotenv.load_dotenv()

PROJECT_ROOT = os.getenv("PROJECT_ROOT")
RUNNER_PATH = f"{PROJECT_ROOT}/runner"
DEFAULT_NUM_PUPPETS = 8
DEFAULT_WORK_US = 0


@dataclass
class Options:
    timeout: Optional[int] = None
    work_us: Optional[int] = None
    client_threads: Optional[int] = None
    worker_threads: Optional[int] = None
    limit_throughput: bool = False
    sample_shift: Optional[int] = None
    dump_file: Optional[str] = None
    stderr_status: bool = False
    live_dump: bool = False

    def to_args(self) -> list[str]:
        args: list[str] = []
        if self.timeout is not None:
            args += ["--timeout", str(self.timeout)]
        if self.work_us is not None:
            args += ["--work-us", str(self.work_us)]
        if self.client_threads is not None:
            args += ["--clients", str(self.client_threads)]
        if self.worker_threads is not None:
            args += ["--puppets", str(self.worker_threads)]
        if self.limit_throughput:
            args.append("--limit")
        if self.sample_shift is not None:
            args += ["--sample-shift", str(self.sample_shift)]
        if self.dump_file is not None:
            args += ["--dump", self.dump_file]
        if self.stderr_status:
            args.append("--status")
        if self.live_dump:
            args.append("--live-dump")
        return args

    def to_filename_suffix(self) -> str:
        parts = []
        if self.timeout is not None:
            parts.append(f"t{self.timeout}")
        if self.work_us is not None:
            parts.append(f"w{self.work_us}")
        if self.client_threads is not None:
            parts.append(f"c{self.client_threads}")
        if self.worker_threads is not None:
            parts.append(f"p{self.worker_threads}")
        if self.limit_throughput:
            parts.append("l")
        if self.sample_shift is not None:
            parts.append(f"s{self.sample_shift}")
        if self.dump_file is not None:
            parts.append(f"d")
        if self.stderr_status:
            parts.append("e")
        if self.live_dump:
            parts.append("ld")
        return "_" + "_".join(parts) if parts else ""


BASE_OPTIONS = Options(stderr_status=True, work_us=5)

# OPTIONS = [BASE_OPTIONS, dataclasses.replace(BASE_OPTIONS, sample_shift=8)]
OPTIONS = [Options(work_us=5, sample_shift=8, worker_threads=16), Options(work_us=5, sample_shift=8, worker_threads=4)]


async def stream_output(stream) -> None:
    """Read async stream line by line and forward via tqdm.write()."""
    while True:
        line = await stream.readline()
        if not line:
            break
        tqdm.write(line.decode().strip())


async def run_workload(workload_file: str, log_file: str, options: Options) -> None:
    analyzed_file = f"{RUNNER_PATH}/analysis/analyzed_{log_file}"
    log_file = f"{RUNNER_PATH}/logs/{log_file}"
    cmd = [
        f"{RUNNER_PATH}/run",
        "--input",
        workload_file,
        "--log",
        log_file,
    ] + options.to_args()
    await execute_command(cmd)
    cmd = [
        f"{RUNNER_PATH}/bin/analyze",
        workload_file,
        log_file,
        str(
            DEFAULT_NUM_PUPPETS
            if options.worker_threads is None
            else options.worker_threads
        ),
        str(DEFAULT_WORK_US if options.work_us is None else options.work_us),
    ]
    await execute_command(cmd)
    os.rename("analyzed.bin", analyzed_file)


async def execute_command(cmd):
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    await asyncio.gather(stream_output(proc.stdout), stream_output(proc.stderr))
    await proc.wait()


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "workloads_dir", type=str, help="Directory containing workload files"
    )
    args = parser.parse_args()

    workload_files = [
        file for file in os.listdir(args.workloads_dir) if file.endswith(".bin")
    ]

    for workload_file, options in tqdm(
        itertools.product(workload_files, OPTIONS),
        total=len(workload_files) * len(OPTIONS),
        desc="Running and analyzing workloads",
    ):
        workload_path = os.path.join(args.workloads_dir, workload_file)
        await run_workload(
            workload_path,
            f"log_{workload_file}{options.to_filename_suffix()}.bin",
            options,
        )


if __name__ == "__main__":
    asyncio.run(main())
