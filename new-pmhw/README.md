The intended way to compile this is `make connectal`. (See `Makefile`.)

Although, sometimes you might want to run testbenches, in which case, you can make other targets, like:
```
make ./build/sim/mkSummaryTest
make ./build/sim/mkPuppetmasterTest
```
and run those files. (They are executables.)
