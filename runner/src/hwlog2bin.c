#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <stdatomic.h>

#include "pmlog.h"
#include "pmutils.h"

// Comparison function for sorting events by timestamp
static int compare_events(const void *a, const void *b) {
    const pmlog_evt_t *ea = (const pmlog_evt_t *)a;
    const pmlog_evt_t *eb = (const pmlog_evt_t *)b;
    if (ea->tsc < eb->tsc) return -1;
    if (ea->tsc > eb->tsc) return 1;
    return 0;
}

// Function to parse a line from the hardware log
static bool parse_hw_log_line(char* line, pmlog_evt_t* evt, int* puppet_id) {
    uint64_t timestamp;
    uint64_t txn_id;
    char event_type[32];
    *puppet_id = -1;  // Default invalid value
    
    // Extract timestamp, txn_id, and event type
    if (sscanf(line, "[%" SCNu64 "] txn_id=%" SCNu64 " %31s", &timestamp, &txn_id, event_type) != 3) {
        return false;  // Not a valid log line
    }
    
    evt->tsc = timestamp;
    evt->txn_id = txn_id;
    
    // Check event type and extract puppet_id if present
    if (strcmp(event_type, "submitted") == 0) {
        evt->kind = PMLOG_SUBMIT;
        evt->aux_data = 0;
        return true;
    } else if (strcmp(event_type, "scheduled") == 0) {
        evt->kind = PMLOG_SCHED_READY;
        if (sscanf(line, "[%" SCNu64 "] txn_id=%" SCNu64 " scheduled on puppet_id=%" SCNu64, 
                  &timestamp, &txn_id, &evt->aux_data) != 3) {
            return false;
        }
        *puppet_id = evt->aux_data;  // Save puppet_id for updating scheduled events
        return true;
    } else if (strncmp(event_type, "executing", 9) == 0) {
        evt->kind = PMLOG_WORK_RECV;
        if (sscanf(line, "[%" SCNu64 "] txn_id=%" SCNu64 " executing on puppet_id=%" SCNu64, 
                  &timestamp, &txn_id, &evt->aux_data) != 3) {
            return false;
        }
        *puppet_id = evt->aux_data;  // Save puppet_id for updating scheduled events
        return true;
    } else if (strncmp(event_type, "done", 4) == 0) {
        evt->kind = PMLOG_DONE;
        if (sscanf(line, "[%" SCNu64 "] txn_id=%" SCNu64 " done on puppet_id=%" SCNu64, 
                  &timestamp, &txn_id, &evt->aux_data) != 3) {
            return false;
        }
        return true;
    } else if (strcmp(event_type, "removed") == 0) {
        evt->kind = PMLOG_CLEANUP;
        evt->aux_data = 0;
        return true;
    }
    
    return false;  // Unknown event type
}

// Count the number of transaction events in a file
static int count_transaction_events(FILE *file) {
    int count = 0;
    char line[1024];
    
    // Go to beginning of file
    rewind(file);
    
    while (fgets(line, sizeof(line), file)) {
        // Count lines that contain transaction IDs
        if (strstr(line, "txn_id=") != NULL) {
            count++;
        }
    }
    
    // Go back to beginning of file
    rewind(file);
    
    return count;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <hw_log.txt> <output.bin> <fpga_freq_mhz>\n", argv[0]);
        return 1;
    }
    
    const char *input_file = argv[1];
    const char *output_file = argv[2];
    double fpga_freq = atof(argv[3]) * 1e6;  // Convert MHz to Hz
    
    FILE *input = fopen(input_file, "r");
    if (!input) {
        FATAL("Cannot open input file: %s", input_file);
    }
    
    // Count the number of transaction events to allocate appropriate buffer
    int event_count = count_transaction_events(input);
    INFO("Found %d transaction events in log file", event_count);
    
    // Initialize pmlog with the correct buffer size
    pmlog_init(event_count, 1, NULL);  // No live dump, collect all events
    
    // Parse the hardware log file
    char line[1024];
    int num_events = 0;
    uint64_t min_tsc = UINT64_MAX;
    
    // First pass: Collect all events and find minimum timestamp
    while (fgets(line, sizeof(line), input)) {
        // Skip non-transaction lines
        if (strstr(line, "txn_id=") == NULL) {
            continue;
        }
        
        pmlog_evt_t evt;
        int puppet_id;
        
        if (parse_hw_log_line(line, &evt, &puppet_id)) {
            // Track the earliest timestamp
            if (evt.tsc < min_tsc) {
                min_tsc = evt.tsc;
            }
            
            // Record the event in our buffer
            pmlog_evt_buf[num_events++] = evt;
        }
    }
    
    uint64_t base_tsc = 1;
    
    // Update all timestamps relative to base_tsc
    for (int i = 0; i < num_events; i++) {
        pmlog_evt_buf[i].tsc = pmlog_evt_buf[i].tsc - min_tsc + 1;
    }
    
    // irrelevant now
    // // Second pass: Update scheduled events with puppet_id information
    // for (int i = 0; i < num_events; i++) {
    //     if (pmlog_evt_buf[i].kind == PMLOG_WORK_RECV) {
    //         uint64_t txn_id = pmlog_evt_buf[i].txn_id;
    //         uint64_t puppet_id = pmlog_evt_buf[i].aux_data;
    //         
    //         // Find the corresponding SCHED_READY event
    //         for (int j = 0; j < num_events; j++) {
    //             if (pmlog_evt_buf[j].kind == PMLOG_SCHED_READY && 
    //                 pmlog_evt_buf[j].txn_id == txn_id) {
    //                 // Update with the puppet_id
    //                 pmlog_evt_buf[j].aux_data = puppet_id;
    //                 break;
    //             }
    //         }
    //     }
    // }
    
    // Set the number of events in the pmlog system
    atomic_store(&num_events, num_events);
    
    // Set base_tsc and cpu_freq in pmlog
    pmlog_start_timer(fpga_freq);
    
    // Write the binary log file
    FILE *output = fopen(output_file, "wb");
    if (!output) {
        FATAL("Cannot open output file: %s", output_file);
    }
    
    // Creating our own direct write instead of using pmlog_write to avoid issues
    // First sort events by timestamp
    qsort(pmlog_evt_buf, num_events, sizeof(pmlog_evt_t), compare_events);
    
    // Write header information
    fwrite(&num_events, sizeof(int), 1, output);
    fwrite(&base_tsc, sizeof(uint64_t), 1, output);
    fwrite(&fpga_freq, sizeof(double), 1, output);
    
    // Write all events
    size_t written = fwrite(pmlog_evt_buf, sizeof(pmlog_evt_t), num_events, output);
    if (written != num_events) {
        FATAL("Failed to write all events to output file. Wrote %zu of %d", written, num_events);
    }
    
    fclose(output);
    
    INFO("Converted %d events from hardware log to binary format", num_events);
    INFO("Binary log written to %s", output_file);
    
    // Cleanup
    fclose(input);
    pmlog_cleanup();
    
    return 0;
}

