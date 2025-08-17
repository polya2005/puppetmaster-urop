## Build 

`deps/wrapper/` is set up as a symlink to the `wrapper/` project. Make sure it's not broken.
(I probably should've just made a variable like `PMHW_DIR` though. This gets confusing too quickly.)

Then, you can build by running `make all`. Usually, you'll use `BOARD=sim`.

## Generate workloads

Script `scripts/generate.py` is for generating multiple workloads.
It dispatches `bin/generate` which efficiently generates a single workload.

I didn't quite properly set up a way to automatically set environmental variables, so you'll probably get a complaint that `pmhw.so` is missing.
See `run` or `analyze` shell script for how I addressed it (i.e., set `LD_LIBRARY_PATH`).

Then, once you have the workloads, you can run `./run`. It will tell you how to run with correct arguments.

Example of what I usually do:
```
./run --log log.bin --status --input workloads/size_16_write_50_zipf_60_addr_20000000_txns_100.bin --work-us 5
```

Then, I run this analyzer:
```
./analyze workloads/size_16_write_50_zipf_60_addr_20000000_txns_100.bin log.bin 8 5
```

This will generate a bunch of cool numbers and graphics.
