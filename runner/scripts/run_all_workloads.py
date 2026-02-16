#!/usr/bin/env python3

import argparse
import asyncio
import dotenv
import itertools
import os
from datetime import datetime
from rich import print
from rich.progress import track
from dataclasses import dataclass
from typing import Optional, IO


dotenv.load_dotenv()

PROJECT_ROOT = os.getenv("PROJECT_ROOT")
RUNNER_PATH = f"{PROJECT_ROOT}/runner"
DEFAULT_NUM_PUPPETS = 8
DEFAULT_WORK_US = 0

START_TIME = datetime.now().isoformat(timespec="seconds")


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
SIM_OPTIONS = [
    Options(work_us=5, sample_shift=8, worker_threads=16),
    Options(work_us=5, sample_shift=8, worker_threads=4),
]

HW_OPTIONS = [Options(timeout=30)]


async def stream_output(stream, file: Optional[IO[str]] = None) -> None:
    """Read async stream line by line and forward via tqdm.write()."""
    while True:
        line = await stream.readline()
        if not line:
            break
        print(line.decode().strip(), file=file)


async def execute_command(cmd, stream_stdout_to: Optional[IO[str]] = None) -> None:
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    await asyncio.gather(
        stream_output(proc.stdout, file=stream_stdout_to), stream_output(proc.stderr)
    )
    await proc.wait()


async def run_sim(workload_file: str, log_file: str, options: Options) -> None:
    cmd = [
        f"{RUNNER_PATH}/run",
        "--input",
        workload_file,
        "--log",
        log_file,
    ] + options.to_args()
    await execute_command(cmd)


async def run_hw(
    workload_file: str, log_file: str, options: Options, throttle: bool = False
) -> None:
    cmd = [
        f"{RUNNER_PATH}/hw_test",
        workload_file,
        "0" if throttle else "625",
        "100" if throttle else "0",
        str(options.timeout) if options.timeout is not None else "60",
    ]
    with open("hw_log.txt", "w") as hw_log:
        await execute_command(cmd, stream_stdout_to=hw_log)

    cmd = [
        f"{RUNNER_PATH}/hwlog2bin",
        "hw_log.txt",
        log_file,
        "125",  # fpga frequency in MHz
    ]
    await execute_command(cmd)


async def run_workload(
    workload_file: str, log_file: str, options: Options, use_hw: bool = False, throttle: bool = False
) -> None:
    analyzed_file = f"{RUNNER_PATH}/analysis/{START_TIME}/analyzed_{log_file}"
    log_file = f"{RUNNER_PATH}/logs/{START_TIME}/{log_file}"
    if use_hw:
        await run_hw(workload_file, log_file, options, throttle=throttle)
    else:
        await run_sim(workload_file, log_file, options)
    cmd = [
        f"{RUNNER_PATH}/analyze",
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


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "workloads_dir", type=str, help="Directory containing workload files"
    )
    parser.add_argument("--hw", action="store_true", default=False, help="Run workloads with hw_test")
    parser.add_argument(
        "--latency", action="store_true", default=False, help="Throttle to measure latency"
    )
    args = parser.parse_args()

    workload_files = [
        file for file in os.listdir(args.workloads_dir) if file.endswith(".bin")
    ]

    os.mkdir(f"{RUNNER_PATH}/analysis/{START_TIME}")
    os.mkdir(f"{RUNNER_PATH}/logs/{START_TIME}")

    options = HW_OPTIONS if args.hw else SIM_OPTIONS
    for workload_file, options in track(
        itertools.product(workload_files, options),
        total=len(workload_files) * len(options),
        description="Running and analyzing workloads",
    ):
        workload_path = os.path.join(args.workloads_dir, workload_file)
        await run_workload(
            workload_path,
            f"log_{workload_file[:-4]}{options.to_filename_suffix()}.bin",
            options,
            use_hw=args.hw,
            throttle=args.latency,
        )


if __name__ == "__main__":
    asyncio.run(main())
