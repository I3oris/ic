DEBUG ?= false
ENV := \
CRYSTAL_CONFIG_LIBRARY_PATH=$(shell crystal env CRYSTAL_LIBRARY_PATH)\
CRYSTAL_CONFIG_PATH=$(shell crystal env CRYSTAL_PATH)

all: ic

ic: src/*
ifeq "$(DEBUG)" "true"
	@$(ENV) crystal build -p src/ic.cr -D_debug
else
	@$(ENV) crystal build -p src/ic.cr # --release
endif

.PHONY: spec
spec:
	@$(ENV) crystal spec -p --order random

.PHONY: clean
clean:
	rm ic

