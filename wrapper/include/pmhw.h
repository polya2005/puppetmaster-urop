#pragma once

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <stdbool.h>
#include <stdint.h>
#include "pmutils.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
Supported sizes
*/
#define MAX_CLIENTS 1
#define MAX_PUPPETS 16
#define SCHEDULER_CORE_ID 0
#define MAX_PENDING_PER_CLIENT 64
#define MAX_ACTIVE_PER_PUPPET 8

/*
Maximum number of objects per transaction
*/
#define MAX_TXN_OBJS 16

/*
Object representation, supports up to 2^64 addresses
Use the top bit to identify whether it's a read or a write object
*/
typedef uint32_t num_objs_t;
typedef uint32_t obj_id_t;
typedef uint32_t txn_id_t;
typedef uint32_t aux_data_t;

typedef struct {
  txn_id_t id;
  aux_data_t aux_data;
  num_objs_t num_reads;
  num_objs_t num_writes;
  obj_id_t reads[MAX_TXN_OBJS];
  obj_id_t writes[MAX_TXN_OBJS];
  char _pad[(256 - sizeof(txn_id_t) - sizeof(aux_data_t) - 2*sizeof(size_t) - 2*MAX_TXN_OBJS*sizeof(obj_id_t)) % 64];
} txn_t;

static inline bool check_txn_conflict(const txn_t *a, const txn_t *b) {
  for (size_t i = 0; i < a->num_reads; ++i) {
    for (size_t j = 0; j < b->num_writes; ++j) {
      if (a->reads[i] == b->writes[j]) return true;
    }
  }
  for (size_t i = 0; i < a->num_writes; ++i) {
    for (size_t j = 0; j < b->num_reads; ++j) {
      if (a->writes[i] == b->reads[j]) return true;
    }
  }
  for (size_t i = 0; i < a->num_writes; ++i) {
    for (size_t j = 0; j < b->num_writes; ++j) {
      if (a->writes[i] == b->writes[j]) return true;
    }
  }
  return false;
}

static inline void dump_txn(FILE *f, const txn_t *txn) {
  fprintf(f, "txn_t(id=%d, aux_data=%d, reads={", txn->id, txn->aux_data);
  for (size_t i = 0; i < txn->num_reads; ++i) {
    fprintf(f, "%u,", txn->reads[i]);
  }
  fprintf(f, "}, writes={");
  for (size_t i = 0; i < txn->num_writes; ++i) {
    fprintf(f, "%u,", txn->writes[i]);
  }
  fprintf(f, "})\n");
}

typedef struct {
  bool sim_driver;
  bool sim_puppets;
  int sim_cycles;
  int driver_wait_cycles;
} pm_config_t;

/*
Interfaces
*/

/*
Initialize Puppetmaster. Must be called before any other operations.
*/
void pmhw_init(int num_clients, int num_puppets);

/*
Set configuration for testing.
*/
void pmhw_set_config(const pm_config_t *cfg);

/*
Get configuration for testing.
*/
void pmhw_get_config(pm_config_t *ret);

/*
Clean up Puppetmaster.
*/
void pmhw_shutdown();

/*
Submit a new transaction descriptor to Puppetmaster.
*/
void pmhw_schedule(int client_id, const txn_t *txn);

/*
Trigger input stream. For experimental uses.
*/ 
void pmhw_trigger_input_driver(void);

/*
Poll for a scheduled transaction assigned to a puppet.
If a transaction becomes ready, fills in transactionId and puppetId.
Return false if the system shut down.
*/
bool pmhw_poll_scheduled(int puppet_id, txn_id_t *txn_id);

/*
Report that a previously assigned transaction has been completed by a puppet.
This signals the scheduler that the puppet is now idle and ready for new work.
*/
void pmhw_report_done(int puppet_id, txn_id_t txn_id);

#ifdef __cplusplus
}
#endif

