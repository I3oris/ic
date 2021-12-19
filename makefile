CRYSTAL_PATH ?= $(shell pwd)/crystal-i/src
CRYSTAL_CONFIG_PATH ?= $(CRYSTAL_PATH)
COMPILER ?= crystal
FLAGS ?= -p

ENV := CRYSTAL_CONFIG_PATH=$(CRYSTAL_CONFIG_PATH) CRYSTAL_PATH=$(CRYSTAL_PATH)

all: ic

.PHONY: ic
ic: crystal-i-llvm
	$(ENV) $(COMPILER) build $(FLAGS) src/ic.cr

.PHONY: crystal-i-llvm
crystal-i-llvm:
	cd ./crystal-i && make src/llvm/ext/llvm_ext.o

.PHONY: spec
spec:
	$(ENV) $(COMPILER) spec $(FLAGS) --order random

.PHONY: clean
clean:
	rm ic

