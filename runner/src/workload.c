#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <stdio.h>
#include <string.h>

#include "pmhw.h"
#include "pmutils.h"
#include "workload.h"

/*
Parse CSV transaction
*/
static int count_lines(FILE *f) {
  int count = 0;
  char buf[1000];
  while (fgets(buf, sizeof(buf), f)) {
    if (strlen(buf) > 1) count++;
  }
  return count;
}

/*
Parse CSV transaction of format id,auxData,oid0,rw0,oid1,rw1,...
wherer rw flags are 0=read, 1=write
*/
static void parse_txn(txn_t *txn, const char *buf) {
  const char *p = buf;
  if (sscanf(p, "%u", &txn->id) != 1) {
    FATAL("Failed to parse id");
  }

  while (*p && *p != ',') p++;
  if (*p == ',') p++;

  uint64_t aux_data;
  if (sscanf(p, "%lu", &aux_data) != 1) {
    FATAL("Failed to parse aux_data");
  }
  txn->aux_data = aux_data;

  while (*p && *p != ',') p++;
  if (*p == ',') p++;

  txn->num_reads = 0;
  txn->num_writes = 0;

  txn_id_t objid;
  int writeflag;

  while (*p) {
    if (sscanf(p, "%u", &objid) != 1) {
      FATAL("Failed to parse objid");
    }
    while (*p && *p != ',') p++;
    if (*p == ',') p++;

    if (sscanf(p, "%d", &writeflag) != 1) {
      FATAL("Failed to parse writeflag");
    }
    while (*p && *p != ',') p++;
    if (*p == ',') p++;

    if (writeflag) {
      ASSERTF(txn->num_writes < MAX_TXN_OBJS, "Too many write objects");
      txn->writes[txn->num_writes++] = objid;
    } else {
      ASSERTF(txn->num_reads < MAX_TXN_OBJS, "Too many read objects");
      txn->reads[txn->num_reads++] = objid;
    }
  }
}

/*
Parse a workload from a CSV file and allocate buffer
*/
workload_t *parse_workload_csv(const char *filename) {
  FILE *f = fopen(filename, "r");
  if (!f) FATAL("Failed to open transaction file");

  // count number of lines so we know how much to allocate
  int num_txns = count_lines(f);
  rewind(f);
  workload_t *workload = (workload_t*) malloc(sizeof(workload_t) + sizeof(txn_t) * num_txns);
  if (!workload) FATAL("Failed to malloc txn_list");
  workload->num_txns = num_txns;

  char buf[1000];
  int i = 0;
  while (fgets(buf, sizeof(buf), f)) {
    buf[strcspn(buf, "\n")] = 0;
    if (strlen(buf) > 0) {
      parse_txn(&workload->txns[i], buf);
      i++;
    }
  }

  return workload;
}


/*
Parse a workload from a file and allocate buffer
*/
workload_t* parse_workload_bin(const char* filename) {
  FILE* f = fopen(filename, "rb");
  if (!f) FATAL("Failed to open binary workload file");

  uint32_t magic, version, max_objs, reserved;
  int num_txns;

  if (fread(&magic, sizeof(magic), 1, f) != 1 ||
      fread(&version, sizeof(version), 1, f) != 1 ||
      fread(&num_txns, sizeof(num_txns), 1, f) != 1 ||
      fread(&max_objs, sizeof(max_objs), 1, f) != 1 ||
      fread(&reserved, sizeof(reserved), 1, f) != 1) {
    FATAL("Failed to read workload header");
  }

  if (magic != TXN_BIN_MAGIC) {
    FATAL("Invalid workload file: wrong magic number");
  }

  if (version != TXN_BIN_VERSION) {
    FATAL("Unsupported workload version");
  }

  if (max_objs > MAX_TXN_OBJS) {
    WARN("Workload file uses max_txn_objs=%u but compiled MAX_TXN_OBJS=%d — truncating or rejecting", max_objs, MAX_TXN_OBJS);
    FATAL("Incompatible binary format");
  }

  INFO("Reading workload: magic=0x%x version=%u num_txns=%lu max_objs=%u",
       magic, version, num_txns, max_objs);

  workload_t* workload = malloc(sizeof(workload_t) + sizeof(txn_t) * num_txns);
  if (!workload) FATAL("Failed to allocate workload buffer");

  workload->num_txns = num_txns;

  for (uint64_t i = 0; i < num_txns; ++i) {
    txn_t* txn = &workload->txns[i];

    if (fread(&txn->id, sizeof(txn_id_t), 1, f) != 1 ||
      fread(&txn->aux_data, sizeof(aux_data_t), 1, f) != 1)
      FATAL("Failed to read transaction %lu header", i);

    if (fread(&txn->num_reads, sizeof(num_objs_t), 1, f) != 1 ||
      fread(&txn->num_writes, sizeof(num_objs_t), 1, f) != 1) {
      FATAL("Failed to read transaction %lu read/write counts", i);
    }

    if (txn->num_reads > MAX_TXN_OBJS || txn->num_writes > MAX_TXN_OBJS) {
      FATAL("Transaction %lu exceeds MAX_TXN_OBJS=%d", i, MAX_TXN_OBJS);
    }

    if (fread(txn->reads, sizeof(obj_id_t), MAX_TXN_OBJS, f) != MAX_TXN_OBJS ||
      fread(txn->writes, sizeof(obj_id_t), MAX_TXN_OBJS, f) != MAX_TXN_OBJS) {
      FATAL("Failed to read transaction %lu object data", i);
    }
  }

  fclose(f);
  return workload;
}

static const char *get_file_extension(const char *filename) {
  const char *dot = strrchr(filename, '.');
  return dot ? dot + 1 : "";
}

workload_t *parse_workload(const char *filename) {
  const char *ext = get_file_extension(filename);
  if (strcmp(ext, "csv") == 0) {
    return parse_workload_csv(filename);
  } else if (strcmp(ext, "bin") == 0) {
    return parse_workload_bin(filename);
  } else {
    FATAL("Unknown file extension: .%s", ext);
    return NULL;
  }
}
