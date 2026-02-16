# How to run verilator benchmark

- If not already, set the `BOARD` environment variable to `verilator`:
```bash
export BOARD=verilator
```
- Don't forget to regenerate the connectal files after editing the bsv files:
```bash
make -C deps/wrapper generate
make -C deps/wrapper
```
- Recompile the simulation:
```bash
PMHW_DIR=../new-pmhw make
```
- Run the simulation:
```bash
scripts/run_all_workloads.py --hw [--latency] [workloads_dir]
```
- Generate summary:
```bash
scripts/summarize_analysis.py [analysis_dir]
```
Where `analysis_dir` is the output folder from the previous step.