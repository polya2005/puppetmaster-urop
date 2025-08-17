#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <memory>
#include "pmhw.h"
#include "pmutils.h"
#include <queue>
#include <mutex>
#include <condition_variable>

/*
Connectal-required wrappers
*/
#include "GeneratedTypes.h"
#include "S2HMessage.h"
#include "H2SMessage.h"

class H2SMessage : public H2SMessageWrapper {
public:
  std::queue<TopConfig> cfg;
  std::mutex mutex;
  std::condition_variable cv;

  void configData(const TopConfig c) {
    std::unique_lock guard{mutex};
    cfg.push(c);
    cv.notify_all();
  }

  void transactionScheduled(const TransactionId txnId) {
    FATAL("Not expecting to use this");
  }

  H2SMessage(int id) : H2SMessageWrapper(id), cfg(), mutex(), cv() {}
};

/*
Singleton representing active Puppetmaster instance
*/
static struct pmhw_singleton_t {
  bool initialized = false;
  int numPuppets = 0;
  std::unique_ptr<S2HMessageProxy> s2h = nullptr;
  std::unique_ptr<H2SMessage> h2s = nullptr;
} pmhw;

/*
Interfaces
*/

void pmhw_init(int num_clients, int num_puppets) {
  pmhw.initialized = true;
  pmhw.s2h = std::make_unique<S2HMessageProxy>(IfcNames_S2HMessageS2H);
  pmhw.h2s = std::make_unique<H2SMessage>(IfcNames_H2SMessageH2S);
  pmhw.numPuppets = num_puppets;

  pmhw.s2h->systemReset();
  pmhw.s2h->setConfig((TopConfig){
    .useSimulatedTxnDriver = true,
    .useSimulatedPuppets = true,
    .numPuppets = (uint16_t)(num_puppets),
    .puppetSimCycles = 0,
    .txnDriverWaitCycles = 0
  });
}

void pmhw_set_config(const pm_config_t *cfg) {
  pmhw.s2h->setConfig((TopConfig){
    .useSimulatedTxnDriver = cfg->sim_driver,
    .useSimulatedPuppets = cfg->sim_puppets,
    .numPuppets = (uint16_t)pmhw.numPuppets,
    .puppetSimCycles = (Timestamp)cfg->sim_cycles,
    .txnDriverWaitCycles = (Timestamp)cfg->driver_wait_cycles
  });
}

void pmhw_get_config(pm_config_t *ret) {
  pmhw.s2h->fetchConfig();
  TopConfig cfg;
  {
    std::unique_lock guard{pmhw.h2s->mutex};
    pmhw.h2s->cv.wait(guard, [] {
      return !pmhw.h2s->cfg.empty();
    });
    cfg = pmhw.h2s->cfg.front();
    pmhw.h2s->cfg.pop();
  }
  *ret = (pm_config_t){
    .sim_driver = (bool)cfg.useSimulatedTxnDriver,
    .sim_puppets = (bool)cfg.useSimulatedPuppets,
    .sim_cycles = (int)cfg.puppetSimCycles,
    .driver_wait_cycles = (int)cfg.txnDriverWaitCycles
  };
}

void pmhw_shutdown() {
  pmhw.initialized = false;
  pmhw.s2h = nullptr;
  pmhw.h2s = nullptr;
}

void pmhw_schedule(int client_id, const txn_t *txn) {
  ASSERT(pmhw.initialized);

  ASSERT(txn->num_reads <= 8);
  ASSERT(txn->num_writes <= 8);

  pmhw.s2h->addTransaction(
    txn->id,
    txn->aux_data,
    txn->num_reads,
    txn->reads[0], txn->reads[1], txn->reads[2], txn->reads[3],
    txn->reads[4], txn->reads[5], txn->reads[6], txn->reads[7],
    txn->num_writes,
    txn->writes[0], txn->writes[1], txn->writes[2], txn->writes[3],
    txn->writes[4], txn->writes[5], txn->writes[6], txn->writes[7]
  );
}

void pmhw_trigger_input_driver() {
  ASSERT(pmhw.initialized);
  pmhw.s2h->triggerDriver();
}

bool pmhw_poll_scheduled(int puppet_id, txn_id_t *txn_id) {
  FATAL("Not expecting to use this");
}

void pmhw_report_done(int puppet_id, txn_id_t txn_id) {
  FATAL("Not expecting to use this");
}
