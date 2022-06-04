CRYSTAL_PATH ?= $(shell pwd)/crystal-i/src
CRYSTAL_CONFIG_PATH ?= $(CRYSTAL_PATH)
COMPILER ?= crystal
FLAGS ?= -p

ENV := CRYSTAL_CONFIG_PATH=$(CRYSTAL_CONFIG_PATH) CRYSTAL_PATH=$(CRYSTAL_PATH)
SOURCES := $(shell find src -name '*.cr')

# LLVM:
LLVM_EXT_DIR = $(CRYSTAL_PATH)/llvm/ext
LLVM_EXT_OBJ = $(LLVM_EXT_DIR)/llvm_ext.o
LLVM_CONFIG := $(shell $(CRYSTAL_PATH)/llvm/ext/find-llvm-config)

all: ic

ic: $(LLVM_EXT_OBJ) $(SOURCES)
	$(ENV) $(COMPILER) build $(FLAGS) src/main.cr -o ic

.PHONY: release
release: $(LLVM_EXT_OBJ)
	$(ENV) $(COMPILER) build $(FLAGS) --release src/main.cr -o ic

$(LLVM_EXT_OBJ): $(LLVM_EXT_DIR)/llvm_ext.cc
	$(CXX) -c $(CXXFLAGS) -o $@ $< $(shell $(LLVM_CONFIG) --cxxflags)

.PHONY: spec
spec: $(LLVM_EXT_OBJ)
	$(ENV) $(COMPILER) spec $(FLAGS) --order random

.PHONY: clean
clean:
	rm ic

