#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "pmutils.h"
#include "pmhw.h"
#include "workload.h"

int main(int argc, char *argv[]) {
  if (argc != 5) {
    fprintf(stderr, "Usage: %s <transactions.csv> <sim_cycles> <txn_cycles> <wait_s>\n", argv[0]);
    return 1;
  }
  workload_t *wl = parse_workload(argv[1]);
  int sim_cycles = atoi(argv[2]);
  int txn_cycles = atoi(argv[3]);
  int shutdown_time = atoi(argv[4]);

  double freq = 125e6;
  double sim_time = sim_cycles / freq * 1e6;
  double txn_time = txn_cycles / freq * 1e6;

  INFO("Simulating %.1f us of work (%d cycles) with %.1f us (%d cycles) between transactions", sim_time, sim_cycles, txn_time, txn_cycles);
  INFO("This will run for %d seconds", shutdown_time);

  pmhw_init(1, 8);
  pm_config_t cfg;
  pmhw_get_config(&cfg);
  cfg.sim_cycles = sim_cycles;
  cfg.driver_wait_cycles = txn_cycles;
  pmhw_set_config(&cfg);

  for (int i = 0; i < wl->num_txns; ++i) {
    pmhw_schedule(0, &wl->txns[i]);
  }
  INFO("Inserted %d transactions", wl->num_txns);
  sleep(2);

  INFO("Triggering input driver");
  pmhw_trigger_input_driver();

  sleep(shutdown_time);

  free(wl);
  INFO("Done!");
  return 0;
}
