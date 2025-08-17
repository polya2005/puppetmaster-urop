#pragma once

#include "pmhw.h"

#define TXN_BIN_MAGIC 0x54584E53
#define TXN_BIN_VERSION 1

typedef struct {
  int num_txns;
  txn_t txns[];
} workload_t;

workload_t *parse_workload_csv(const char *filename);
workload_t *parse_workload_bin(const char *filename);
workload_t *parse_workload(const char *filename);
