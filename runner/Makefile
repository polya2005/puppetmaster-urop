WRAPPER_DIR = deps/wrapper
GENERATED_DIR = $(WRAPPER_DIR)/output/$(BOARD)
PMHW_FILES = $(addprefix $(GENERATED_DIR)/, pmhw.h pmhw.so)

INCLUDE_DIR = ./include
SRC_DIR = ./src
BIN_DIR = ./bin

DEFINES = 

CXXFLAGS += -I$(INCLUDE_DIR) -I$(GENERATED_DIR) -L$(GENERATED_DIR) -O3 -Wall -lm -pthread $(DEFINES) -g2 -flto -std=c++17
CFLAGS += -I$(INCLUDE_DIR) -I$(GENERATED_DIR) -L$(GENERATED_DIR) -O3 -Wall -lm -pthread $(DEFINES) -g2 -flto -std=c17

LIB_DEPS = -l:pmhw.so

SIM_TYPES = sim

ifneq ($(BOARD), $(filter $(BOARD), $(SIM_TYPES)))
LIB_DEPS += -l:connectal.so
endif

ifeq ($(BOARD), verilator)
LIB_DEPS += -l:libconnectal-sim.so
endif

ALL_TARGET_NAMES = main analyze readlog generate
ifeq ($(BOARD), verilator)
ALL_TARGET_NAMES += hw_test hwlog2bin
endif

ALL_TARGETS = $(addprefix $(BIN_DIR)/, $(ALL_TARGET_NAMES))

.PHONY: all
all: $(ALL_TARGETS)

MAIN_SOURCES = $(addprefix $(SRC_DIR)/, main.c workload.c)

ifeq ($(BOARD), )
.PHONY: $(BIN_DIR)/main
$(BIN_DIR)/main:
	$(error BOARD variable is not defined, aborting build)
else
$(BIN_DIR)/main: $(MAIN_SOURCES) $(PMHW_FILES) $(BIN_DIR)/board.txt 
	mkdir -p bin
	$(CC) $(CFLAGS) $(MAIN_SOURCES) $(LIB_DEPS) -o $@
endif

# Check whether BOARD equals existing board.txt. If not, make this target PHONY to force it to run,
# causing $(BIN_MAIN)/main to also be re-run.
ifneq ($(BOARD), $(shell [ -f $(BIN_DIR)/board.txt ] && cat $(BIN_DIR)/board.txt))
.PHONY: $(BIN_DIR)/board.txt
endif
$(BIN_DIR)/board.txt:
	mkdir -p bin
	echo $(BOARD) > $(BIN_DIR)/board.txt

ifeq ($(BOARD), )
.PHONY: $(BIN_DIR)/analyze
$(BIN_DIR)/analyze:
	$(error BOARD variable is not defined, aborting build)
else
$(BIN_DIR)/analyze: $(SRC_DIR)/analyze.c $(SRC_DIR)/workload.c
	mkdir -p bin
	$(CC) $(CFLAGS) $^ $(LIB_DEPS) -o $@
endif

ifeq ($(BOARD), )
.PHONY: $(BIN_DIR)/generate
$(BIN_DIR)/generate:
	$(error BOARD variable is not defined, aborting build)
else
$(BIN_DIR)/generate: $(SRC_DIR)/generate.c
	mkdir -p bin
	$(CC) $(CFLAGS) $^ $(LIB_DEPS) -o $@
endif

ifeq ($(BOARD), )
.PHONY: $(BIN_DIR)/readlog
$(BIN_DIR)/readlog:
	$(error BOARD variable is not defined, aborting build)
else
$(BIN_DIR)/readlog: $(SRC_DIR)/readlog.c
	mkdir -p bin
	$(CC) $(CFLAGS) $^ $(LIB_DEPS) -o $@
endif

ifeq ($(BOARD), verilator)
$(BIN_DIR)/hw_test: $(SRC_DIR)/hw_test.c $(PMHW_FILES)
	mkdir -p bin
	$(CC) $(CFLAGS) $^ $(SRC_DIR)/workload.c $(LIB_DEPS) -o $@
else
.PHONY: $(BIN_DIR)/hw_test
$(BIN_DIR)/hw_test:
	$(error hw_test is only available for BOARD=verilator)
endif

ifeq ($(BOARD), verilator)
$(BIN_DIR)/hwlog2bin: $(SRC_DIR)/hwlog2bin.c
	mkdir -p bin
	$(CC) $(CFLAGS) $^ $(SRC_DIR)/workload.c $(LIB_DEPS) -o $@
else
.PHONY: $(BIN_DIR)/hwlog2bin
$(BIN_DIR)/hwlog2bin:
	$(error hwlog2bin is only available for BOARD=verilator)
endif

$(PMHW_FILES):
	$(error Manually "BOARD=... make -C deps/wrapper" to generate the necessary files before running this)

.PHONY: clean
clean:
	rm -fR $(BIN_DIR)
	rm -f SWSOCK*

