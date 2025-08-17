#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <pthread.h>
#include <unistd.h>

#include "pmhw.h"
#include "workload.h"

typedef struct {
  txn_t* txns;
  int start;
  int end;
  const double* cdf;
  int addr_space;
  int num_objs_per_txn;
  double write_prob;
  int num_reads;
  int num_writes;
  unsigned int seed;
} worker_arg_t;

double* make_zipf_weights(int n, double alpha) {
  double* weights = malloc(sizeof(double) * n);
  for (int i = 0; i < n; ++i) {
    weights[i] = 1.0 / pow((double)(i + 1), alpha);
  }
  double total = 0.0;
  for (int i = 0; i < n; ++i) total += weights[i];
  for (int i = 0; i < n; ++i) weights[i] /= total;
  for (int i = 1; i < n; ++i) weights[i] += weights[i - 1];
  return weights;
}

int sample_zipf(const double* cdf, int n, unsigned int* seed) {
  double r = (double)rand_r(seed) / RAND_MAX;
  int lo = 0, hi = n - 1;
  while (lo < hi) {
    int mid = (lo + hi) / 2;
    if (r <= cdf[mid]) hi = mid;
    else lo = mid + 1;
  }
  return lo;
}

void* worker_fn(void* arg) {
  worker_arg_t* a = (worker_arg_t*)arg;
  for (int i = a->start; i < a->end; ++i) {
    txn_t* txn = &a->txns[i];
    txn->id = i;
    txn->aux_data = 0;
    txn->num_reads = 0;
    txn->num_writes = 0;
    if (a->num_reads == 0 && a->num_writes == 0) {
      for (int j = 0; j < a->num_objs_per_txn; ++j) {
        obj_id_t obj = (obj_id_t)sample_zipf(a->cdf, a->addr_space, &a->seed);
        bool is_write = ((double)rand_r(&a->seed) / RAND_MAX) < a->write_prob;
        if (is_write) {
          ASSERT(txn->num_writes < MAX_TXN_OBJS);
          txn->writes[txn->num_writes++] = obj;
        } else {
          ASSERT(txn->num_reads < MAX_TXN_OBJS);
          txn->reads[txn->num_reads++] = obj;
        }
      }
    } else {
      for (int j = 0; j < a->num_reads; ++j) {
        obj_id_t obj = (obj_id_t)sample_zipf(a->cdf, a->addr_space, &a->seed);
        txn->reads[txn->num_reads++] = obj;
      }
      for (int j = 0; j < a->num_reads; ++j) {
        obj_id_t obj = (obj_id_t)sample_zipf(a->cdf, a->addr_space, &a->seed);
        txn->writes[txn->num_writes++] = obj;
      }
    }
  }
  return NULL;
}

void generate_workload(txn_t* txns, int num_txns, int num_objs_per_txn, int addr_space,
                       double zipf_alpha, double write_prob, int num_reads, int num_writes) {
  double* cdf = make_zipf_weights(addr_space, zipf_alpha);
  int num_threads = sysconf(_SC_NPROCESSORS_ONLN);
  pthread_t threads[num_threads];
  worker_arg_t args[num_threads];

  for (int t = 0; t < num_threads; ++t) {
    int start = (num_txns * t) / num_threads;
    int end = (num_txns * (t + 1)) / num_threads;
    args[t] = (worker_arg_t){
      .txns = txns,
      .start = start,
      .end = end,
      .cdf = cdf,
      .addr_space = addr_space,
      .num_objs_per_txn = num_objs_per_txn,
      .write_prob = write_prob,
      .num_reads = num_reads,
      .num_writes = num_writes,
      .seed = (unsigned int)(time(NULL) ^ (t * 7919))
    };
    pthread_create(&threads[t], NULL, worker_fn, &args[t]);
  }

  for (int t = 0; t < num_threads; ++t) {
    pthread_join(threads[t], NULL);
  }

  free(cdf);
}

void write_csv(const char* filename, txn_t* txns, int num_txns) {
  FILE* f = fopen(filename, "w");
  for (int i = 0; i < num_txns; ++i) {
    fprintf(f, "%u,0", txns[i].id);
    for (uint64_t j = 0; j < txns[i].num_reads; ++j) {
      fprintf(f, ",%u,0", txns[i].reads[j]);
    }
    for (uint64_t j = 0; j < txns[i].num_writes; ++j) {
      fprintf(f, ",%u,1", txns[i].writes[j]);
    }
    fprintf(f, "\n");
  }
  fclose(f);
}

void write_bin(const char* filename, txn_t* txns, int num_txns) {
  FILE* f = fopen(filename, "wb");
  uint32_t magic = TXN_BIN_MAGIC;
  uint32_t version = TXN_BIN_VERSION;
  uint32_t reserved = 0;
  uint32_t max_objs = MAX_TXN_OBJS;
  fwrite(&magic, sizeof(magic), 1, f);
  fwrite(&version, sizeof(version), 1, f);
  fwrite(&num_txns, sizeof(num_txns), 1, f);
  fwrite(&max_objs, sizeof(max_objs), 1, f);
  fwrite(&reserved, sizeof(reserved), 1, f);

  for (int i = 0; i < num_txns; ++i) {
    fwrite(&txns[i].id, sizeof(txn_id_t), 1, f);
    fwrite(&txns[i].aux_data, sizeof(aux_data_t), 1, f);
    fwrite(&txns[i].num_reads, sizeof(num_objs_t), 1, f);
    fwrite(&txns[i].num_writes, sizeof(num_objs_t), 1, f);
    fwrite(txns[i].reads, sizeof(obj_id_t), MAX_TXN_OBJS, f);
    fwrite(txns[i].writes, sizeof(obj_id_t), MAX_TXN_OBJS, f);
  }
  fclose(f);
}

int main(int argc, char** argv) {
  if (argc != 8 && argc != 9) {
    fprintf(stderr, "Usage: %s <csv|bin> <filename> <num_txns> <num_objs> <addr_space> <zipf_param> (<write_prob> | <num_reads> <num_writes>)\n", argv[0]);
    return 1;
  }

  const char* mode = argv[1];
  const char* filename = argv[2];
  int num_txns = atoi(argv[3]);
  int num_objs = atoi(argv[4]);
  int addr_space = atoi(argv[5]);
  double zipf_param = atof(argv[6]);
  double write_prob;
  int num_reads = 0, num_writes = 0;
  if (argc == 8) {
    write_prob = atof(argv[7]);
  } else {
    num_reads = atoi(argv[7]);
    num_writes = atoi(argv[8]);
    ASSERT(num_reads + num_writes == num_objs);
  }
  ASSERT(num_objs <= MAX_TXN_OBJS);

  txn_t* txns = malloc(sizeof(txn_t) * num_txns);
  generate_workload(txns, num_txns, num_objs, addr_space, zipf_param, write_prob, num_reads, num_writes);

  if (strcmp(mode, "csv") == 0) {
    write_csv(filename, txns, num_txns);
  } else if (strcmp(mode, "bin") == 0) {
    write_bin(filename, txns, num_txns);
  } else {
    fprintf(stderr, "Invalid mode: %s (must be 'csv' or 'bin')\n", mode);
    free(txns);
    return 1;
  }

  free(txns);
  return 0;
}
