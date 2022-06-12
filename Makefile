CRYSTAL_PATH ?= $(shell pwd)/share/crystal-ic/src
CRYSTAL_CONFIG_PATH ?= '$$ORIGIN/../share/crystal-ic/src'

COMPILER ?= crystal
FLAGS ?= --progress
RELEASE_FLAGS ?= --progress --static

ENV ?= CRYSTAL_CONFIG_PATH=$(CRYSTAL_CONFIG_PATH) CRYSTAL_PATH=$(CRYSTAL_PATH)
SOURCES := $(shell find src -name '*.cr')
O := bin/ic

# LLVM:
LLVM_EXT_DIR := $(CRYSTAL_PATH)/llvm/ext
LLVM_EXT_OBJ := $(LLVM_EXT_DIR)/llvm_ext.o
LLVM_CONFIG ?= $(shell $(CRYSTAL_PATH)/llvm/ext/find-llvm-config)

# INSTALL:
DESTDIR ?= /usr/local
BINDIR ?= $(DESTDIR)/bin
DATADIR ?= $(DESTDIR)/share/crystal-ic
INSTALL ?= /usr/bin/install

all: $(O)

$(O): $(LLVM_EXT_OBJ) $(SOURCES)
	mkdir -p bin
	$(ENV) $(COMPILER) build $(FLAGS) src/ic.cr -o $(O)

.PHONY: release
release: $(LLVM_EXT_OBJ)
	mkdir -p bin
	$(ENV) $(COMPILER) build $(RELEASE_FLAGS) src/ic.cr -o $(O)

$(LLVM_EXT_OBJ): $(LLVM_EXT_DIR)/llvm_ext.cc
	$(CXX) -c $(CXXFLAGS) -o $@ $< $(shell $(LLVM_CONFIG) --cxxflags)

.PHONY: spec
spec: $(LLVM_EXT_OBJ)
	mkdir -p bin
	$(ENV) $(COMPILER) spec $(FLAGS) --order random

.PHONY: install
install: $(O) ## Install the compiler at DESTDIR
	$(INSTALL) -d -m 0755 "$(BINDIR)/"
	$(INSTALL) -m 0755 "$(O)" "$(BINDIR)/ic"

	$(INSTALL) -d -m 0755 "$(DATADIR)"
	cp -av share/crystal-ic/src "$(DATADIR)/"
	rm -rf "$(DATADIR)/$(LLVM_EXT_OBJ)" # Don't install llvm_ext.o

	$(INSTALL) -d -m 0755 "$(DESTDIR)/share/licenses/ic/"
	$(INSTALL) -m 644 LICENSE "$(DESTDIR)/share/licenses/ic/LICENSE"

# TODO make uninstall

.PHONY: uninstall
uninstall: ## Uninstall the compiler from DESTDIR
	rm -f "$(BINDIR)/ic"
	rm -rf "$(DATADIR)/src"
	rm -f "$(DESTDIR)/share/licenses/ic/LICENSE"

.PHONY: clean
clean:
	rm $(LLVM_EXT_OBJ)
	rm $(O)

