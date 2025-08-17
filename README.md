# Thesis artifacts

The thesis page is <https://tcpc.me/meng-thesis>.

## Setup

See `setup/README.md`.

## Notes

There are tutorials I wrote up in `notes/`. Comb through them if you have some questions about Bluespec.

## Python model

I generated a bunch of cool appendix figures in `model/`. The scripts are straightforward. Just run them directly and observe the output in the folder.

## Flow summary

If you just want to run things, do this:
1. Go to `wrapper/` and run `BOARD=sim make generate`
2. Then `BOARD=sim make`. Observe `wrapper/output/`.
3. Go to `runner/` and run `BOARD=sim make`.
4. Follow instructions in `README.md` there.

## New Puppetmaster implementation

See `new-pmhw/`. This follows Connectal's required project structure.

You can run testbenches in there (see the readme inside). This is not where you would compile things end-to-end, though.

## Puppetmaster software interface (wrapper)

I created an implementation-agnostic interface in `wrapper/`. This way, the fact that Puppetmaster was implemented using Connectal
could be abstracted away. The entire Connectal folder structure is abstracted away. Instead, Puppetmaster can be called through the provided `pmhw.h`.

This is what we're supposedly trying to provide as a convenient interface. Read readme for details.

## Artificial runner

The folder `runner/` is the entry point for running end-to-end (HW-SW) integration tests. It contains the `main.c` implementation.
It sets up parsing workloads, logging, fake executors, etc. (A real runner would have actual workload.)

`runner/` also contains a bunch of useful scripts for analyzing the logs/results. See readme in there.
