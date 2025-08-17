touch log.bin
touch analyzed.bin

srcdir="output"
dstdir="thesis-figures"

do_run () {
  # make sure to load the transaction first
  txns=$1
  name=$2
  workus=$3
  extras=$4
  rm -f transactions.bin
  ln -f workloads/$txns transactions.bin

  # two runs (one for warmup)
  sudo chrt -f 99 ./run --input transactions.bin --work-us $workus --clients 1 --puppets 8 --sample-shift 14 --log log.bin $extras

  # analyze and visualize
  ./analyze transactions.bin log.bin 8 0

  # copy the results
  mkdir -p $dstdir/$name
  cp $srcdir/* $dstdir/$name/
}

## Finalized
# 
# ## Max throughput
# 
# rm -f transactions.bin
# ln -f workloads/size_0_write_00_zipf_00_addr_20000000_txns_10000000.bin transactions.bin
# sudo chrt -f 99 ./run --input transactions.bin --work-us 0 --clients 1 --puppets 8 --sample-shift 14 --log log.bin
# sudo chrt -f 99 ./run --input transactions.bin --work-us 0 --clients 1 --puppets 8 --sample-shift 14 --log log.bin
# ./analyze transactions.bin log.bin 8 0
# # Expecting about 10M txn/s and 5-8us
# 
# mkdir -p thesis-figures/free-unthrottled/
# cp output/* thesis-figures/free-unthrottled/
# 
# cp output/latency-e2e.svg thesis-figures/free-unthrottled-latency.svg
# cp output/throughput-done.svg thesis-figures/free-unthrottled-throughput.svg
# cp output/report.pdf thesis-figures/free-unthrottled-report.pdf
# 
# ## Min latency, throttled
# 
# rm -f transactions.bin
# ln -f workloads/size_0_write_00_zipf_00_addr_20000000_txns_10000000.bin transactions.bin
# sudo chrt -f 99 ./run --input transactions.bin --work-us 0 --clients 1 --puppets 8 --sample-shift 14 --log log.bin --limit
# sudo chrt -f 99 ./run --input transactions.bin --work-us 0 --clients 1 --puppets 8 --sample-shift 14 --log log.bin --limit
# ./analyze transactions.bin log.bin 8 0
# 
# mkdir -p thesis-figures/free-throttled/
# cp output/* thesis-figures/free-throttled/
# 
# cp output/latency-e2e.svg thesis-figures/free-throttled-latency.svg
# cp output/throughput-done.svg thesis-figures/free-throttled-throughput.svg
# cp output/report.pdf thesis-figures/free-throttled-report.pdf

## Real workload

## Finalized
#
# do_run size_8_write_05_zipf_00_addr_20000000_txns_10000000.bin small-read-low 5
# do_run size_8_write_05_zipf_60_addr_20000000_txns_10000000.bin small-read-med 5
# do_run size_8_write_05_zipf_80_addr_20000000_txns_10000000.bin small-read-high 5
# do_run size_8_write_50_zipf_00_addr_20000000_txns_10000000.bin small-write-low 5
# do_run size_8_write_50_zipf_60_addr_20000000_txns_10000000.bin small-write-med 5
# do_run size_8_write_50_zipf_80_addr_20000000_txns_10000000.bin small-write-high 5
#
# do_run size_8_write_05_zipf_00_addr_20000000_txns_1000000.bin small-read-low-throttled 5 --limit
# do_run size_8_write_05_zipf_60_addr_20000000_txns_1000000.bin small-read-med-throttled 5 --limit
# do_run size_8_write_05_zipf_80_addr_20000000_txns_1000000.bin small-read-high-throttled 5 --limit
# do_run size_8_write_50_zipf_00_addr_20000000_txns_1000000.bin small-write-low-throttled 5 --limit
# do_run size_8_write_50_zipf_60_addr_20000000_txns_1000000.bin small-write-med-throttled 5 --limit
# do_run size_8_write_50_zipf_80_addr_20000000_txns_1000000.bin small-write-high-throttled 5 --limit

do_run size_16_write_05_zipf_00_addr_20000000_txns_1000000.bin large-read-low 20
do_run size_16_write_05_zipf_60_addr_20000000_txns_1000000.bin large-read-med 20
do_run size_16_write_05_zipf_80_addr_20000000_txns_1000000.bin large-read-high 20
do_run size_16_write_50_zipf_00_addr_20000000_txns_1000000.bin large-write-low 20
do_run size_16_write_50_zipf_60_addr_20000000_txns_1000000.bin large-write-med 20
do_run size_16_write_50_zipf_80_addr_20000000_txns_1000000.bin large-write-high 20

do_run size_16_write_05_zipf_00_addr_20000000_txns_100000.bin large-read-low-throttled 20 --limit
do_run size_16_write_05_zipf_60_addr_20000000_txns_100000.bin large-read-med-throttled 20 --limit
do_run size_16_write_05_zipf_80_addr_20000000_txns_100000.bin large-read-high-throttled 20 --limit
do_run size_16_write_50_zipf_00_addr_20000000_txns_100000.bin large-write-low-throttled 20 --limit
do_run size_16_write_50_zipf_60_addr_20000000_txns_100000.bin large-write-med-throttled 20 --limit
do_run size_16_write_50_zipf_80_addr_20000000_txns_100000.bin large-write-high-throttled 20 --limit

