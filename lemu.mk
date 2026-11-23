#***************************************************************************************
# Copyright (c) 2020-2025 Institute of Computing Technology, Chinese Academy of Sciences
# Copyright (c) 2025 Beijing Institute of Open Source Chip (BOSC)
# Copyright (c) 2020-2021 Peng Cheng Laboratory
#
# DiffTest is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#          http://license.coscl.org.cn/MulanPSL2
#
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
#
# See the Mulan PSL v2 for more details.
#***************************************************************************************

LEMU_BUILD_DIR = $(abspath $(BUILD_DIR)/lemu-compile)
LEMU_TARGET = $(LEMU_BUILD_DIR)/$(EMU_ELF_NAME)

########## Lemu Configuration Options ##########
LEMU_FLAGS = $(SIM_VFLAGS)

LEMU_CSRC_DIR = $(abspath ./src/test/csrc/lemu)
LEMU_CXXFILES = $(EMU_CXXFILES) $(shell find $(LEMU_CSRC_DIR) -name "*.cpp" 2> /dev/null)
LEMU_CXXFLAGS = $(EMU_CXXFLAGS) -I$(LEMU_CSRC_DIR) -DLEMU --std=c++17
LEMU_LDFLAGS  = $(SIM_LDFLAGS) -ldl

# The trace-enabled generated model can exceed the x86-64 small code model.
# Keep the large-code-model linker workaround opt-in: normal Lemu builds use
# the generated makefile and linker defaults unchanged.  Enable it with
# `make ... LEMU_LARGE_MODEL=1` when the generated model needs the high-address
# model island (typically with a large partitioned waveform build).
LEMU_LARGE_MODEL ?= 0
LEMU_LARGE_MODEL_MK = $(abspath $(LEMU_CSRC_DIR)/large-model.mk)
LEMU_LARGE_MODEL_LINKER_SCRIPT ?= $(abspath $(LEMU_CSRC_DIR)/large-model.ld)
LEMU_LARGE_MODEL_DEPS = $(if $(filter 1,$(LEMU_LARGE_MODEL)),$(LEMU_LARGE_MODEL_MK) $(LEMU_LARGE_MODEL_LINKER_SCRIPT))
LEMU_LARGE_MODEL_MAKE_ARGS = $(if $(filter 1,$(LEMU_LARGE_MODEL)),LEMU_LARGE_MODEL_TARGET="$(LEMU_TARGET)" LEMU_LARGE_MODEL_LINKER_SCRIPT="$(LEMU_LARGE_MODEL_LINKER_SCRIPT)")
# GNU find avoids expanding tens of thousands of partitioned-object names into
# one command.  Keep the old glob as a fallback for find implementations that
# do not support -maxdepth (for example the BSD default on macOS).
LEMU_CLEAN_OBJECTS = if find "$(LEMU_BUILD_DIR)" -maxdepth 0 -type d >/dev/null 2>&1; then find "$(LEMU_BUILD_DIR)" -maxdepth 1 -type f \( -name '*.o' -o -name '*.d' -o -name '*.gch' -o -name '*.a' \) -delete; else rm -f "$(LEMU_BUILD_DIR)"/*.o "$(LEMU_BUILD_DIR)"/*.gch "$(LEMU_BUILD_DIR)"/*.a; fi

# Lemu installation.  LEMU_BIN is resolved through PATH by default (matching
# GSIM_BIN).  When an optional LEMU_ROOT is supplied, use the binary from that
# installation unless LEMU_BIN was explicitly overridden.
LEMU_ROOT ?=
LEMU_BIN ?= $(if $(strip $(LEMU_ROOT)),$(LEMU_ROOT)/bin/lemu,lemu)
LEMU_BIN_PATH = $(if $(findstring /,$(LEMU_BIN)),$(abspath $(LEMU_BIN)),$(LEMU_BIN))
# The Lemu Perl wrapper uses LEMU_BIN as the name of its *inner* binary.  A
# make command-line variable with the same name would otherwise be exported
# and make the wrapper invoke itself recursively.
LEMU_ENV = env -u LEMU_BIN $(if $(strip $(LEMU_ROOT)),LEMU_ROOT="$(LEMU_ROOT)")
LEMU_ROOT_MAKE_ARG = $(if $(strip $(LEMU_ROOT)),LEMU_ROOT="$(LEMU_ROOT)")

# Lemu versions use multiple versioning schemes (for example 5.024 and
# 26.07.01).  Compare the first two numeric components instead of flattening
# the complete version string as is commonly done for Verilator.
LEMU_VERSION_TEXT := $(shell $(LEMU_ENV) "$(LEMU_BIN_PATH)" --version 2> /dev/null)
LEMU_VERSION_COMPONENTS := $(shell $(LEMU_ENV) "$(LEMU_BIN_PATH)" --version 2> /dev/null \
	| sed -n '1{s/^[^0-9]*\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p;}')
LEMU_VERSION_MAJOR := $(word 1,$(LEMU_VERSION_COMPONENTS))
LEMU_VERSION_MINOR := $(word 2,$(LEMU_VERSION_COMPONENTS))

LEMU_4_210 := $(shell if [ -n "$(LEMU_VERSION_MAJOR)" ] && \
	{ [ "$(LEMU_VERSION_MAJOR)" -gt 4 ] || \
	  { [ "$(LEMU_VERSION_MAJOR)" -eq 4 ] && [ "$(LEMU_VERSION_MINOR)" -ge 210 ]; }; }; \
	then echo 1; else echo 0; fi)
ifeq ($(LEMU_4_210),1)
LEMU_CXXFLAGS += -DLEMU_4_210
LEMU_FLAGS += --instr-count-dpi 1
endif

LEMU_5_000 := $(shell if [ -n "$(LEMU_VERSION_MAJOR)" ] && \
	[ "$(LEMU_VERSION_MAJOR)" -ge 5 ]; then echo 1; else echo 0; fi)
ifeq ($(LEMU_5_000),1)
LEMU_FLAGS += --no-timing +define+LEMU_5
else
LEMU_FLAGS += +define+LEMU_LEGACY
endif

LEMU_5_024 := $(shell if [ -n "$(LEMU_VERSION_MAJOR)" ] && \
	{ [ "$(LEMU_VERSION_MAJOR)" -gt 5 ] || \
	  { [ "$(LEMU_VERSION_MAJOR)" -eq 5 ] && [ "$(LEMU_VERSION_MINOR)" -ge 24 ]; }; }; \
	then echo 1; else echo 0; fi)
ifeq ($(LEMU_5_024),1)
LEMU_FLAGS += --quiet-stats
endif

ifneq (,$(filter $(EMU_TRACE),1 vcd VCD))
LEMU_FLAGS += --trace
endif
ifneq (,$(filter $(EMU_TRACE),fst FST))
LEMU_FLAGS += --trace-fst
LEMU_CXXFLAGS += -DENABLE_FST
endif

ifeq ($(EMU_TRACE_ALL),1)
LEMU_FLAGS += --trace-underscore
endif

# Lemu native debug/waveform flags forwarded verbatim to lemu (for example
# LEMU_DEBUG=--debug_access, LEMU_DEBUG=--debug_access+r, or
# LEMU_DEBUG=--debug-live-read).  Enable FST driver bindings automatically when
# debug_access or FST tracing is requested.
LEMU_DEBUG ?=
ifneq ($(strip $(LEMU_DEBUG)),)
LEMU_FLAGS += $(LEMU_DEBUG)
ifneq (,$(filter --debug_access% --trace-fst%,$(LEMU_DEBUG)))
LEMU_CXXFLAGS += -DENABLE_FST
endif
endif

ifneq ($(EMU_THREADS),0)
LEMU_FLAGS += --threads $(EMU_THREADS) --threads-dpi all
endif

ifeq ($(EMU_SNAPSHOT),1)
LEMU_FLAGS += --savable
LEMU_CXXFLAGS += -DLEMU_MODEL_SAVABLE
endif

ifeq ($(EMU_COVERAGE),1)
LEMU_FLAGS += --coverage-line --coverage-toggle
endif

# Lemu's static scheduling/partition count.  Partitioned models currently do
# not emit the top-level serialization operators required by --savable, so a
# snapshot build defaults to an unpartitioned model.  Set this to an empty
# value explicitly to omit --ss-test in other configurations.
ifeq ($(EMU_SNAPSHOT),1)
LEMU_SS_TEST ?=
else
LEMU_SS_TEST ?= 96
endif
LEMU_SPLIT_VAR ?= 1
ifneq ($(strip $(LEMU_SS_TEST)),)
LEMU_FLAGS += --ss-test $(LEMU_SS_TEST)
ifeq ($(LEMU_SPLIT_VAR),1)
LEMU_FLAGS += --split-var
endif
endif

# This is intentionally last so installations can add Lemu-specific tuning
# options (for example --ss-test-j or --reuse-part-result).  Model feature
# switches must use the variables above so their matching C++ configuration
# and compatibility checks cannot be bypassed.
LEMU_FLAGS_EXTRA ?=
LEMU_FLAGS += $(LEMU_FLAGS_EXTRA)
LEMU_INVALID_EXTRA_FLAGS := $(filter \
	--ss-test -ss-test --ss-test=% -ss-test=% --no-ss-test% -no-ss-test% \
	--split-var -split-var --split-var=% -split-var=% --no-split-var% -no-split-var% \
	--savable% -savable% --no-savable% -no-savable% \
	--coverage -coverage --coverage=% -coverage=% \
	--coverage-line -coverage-line --coverage-line=% -coverage-line=% \
	--coverage-toggle -coverage-toggle --coverage-toggle=% -coverage-toggle=% \
	--coverage-expr -coverage-expr --coverage-expr=% -coverage-expr=% \
	--coverage-underscore -coverage-underscore --coverage-underscore=% -coverage-underscore=% \
	--coverage-user -coverage-user --coverage-user=% -coverage-user=% \
	--no-coverage% -no-coverage% \
	--trace -trace --trace=% -trace=% --trace-vcd -trace-vcd --trace-vcd=% -trace-vcd=% \
	--trace-fst -trace-fst --trace-fst=% -trace-fst=% --trace-saif -trace-saif \
	--trace-saif=% -trace-saif=% --no-trace -no-trace --no-trace=% -no-trace=% \
	--no-trace-vcd -no-trace-vcd --no-trace-vcd=% -no-trace-vcd=% \
	--no-trace-fst -no-trace-fst --no-trace-fst=% -no-trace-fst=% \
	--no-trace-saif -no-trace-saif --no-trace-saif=% -no-trace-saif=% \
	--threads -threads --threads=% -threads=% --threads-dpi -threads-dpi \
	--threads-dpi=% -threads-dpi=% --no-threads --no-threads=% -no-threads -no-threads=% \
	--hierarchical-threads -hierarchical-threads --hierarchical-threads=% -hierarchical-threads=% \
	--timing -timing --timing=% -timing=% --no-timing -no-timing --no-timing=% -no-timing=% \
	--instr-count-dpi -instr-count-dpi --instr-count-dpi=% -instr-count-dpi=% \
	--no-instr-count-dpi -no-instr-count-dpi --no-instr-count-dpi=% -no-instr-count-dpi=% \
	+define+LEMU% -DLEMU% -ULEMU%, \
	$(LEMU_FLAGS_EXTRA))

# C optimization.  verilator.mk is included earlier in emu.mk and sets
# OPT_FAST ?= -O3 -fno-tree-slp-vectorize, so only inherit OPT_FAST when it
# was explicitly overridden outside the Makefile files.
LEMU_OPT_FAST ?= $(if $(filter-out file,$(origin OPT_FAST)),$(OPT_FAST),-O3)

########## Lemu Build Recipes ##########
LEMU_FLAGS_ALL =                     \
  --exe $(EMU_OPTIMIZE)              \
  --cc --top-module $(EMU_TOP)       \
  +define+LEMU=1                     \
  +define+SYNTHESIS                  \
  +define+PRINTF_COND=1              \
  +define+RANDOMIZE_REG_INIT         \
  +define+RANDOMIZE_MEM_INIT         \
  +define+RANDOMIZE_GARBAGE_ASSIGN   \
  +define+RANDOMIZE_DELAY=0          \
  -Wno-STMTDLY -Wno-WIDTH            \
  -Wno-UNSIGNED                      \
  --max-num-width 150000             \
  --assert --x-assign unique         \
  --output-split 30000               \
  --output-split-cfuncs 30000        \
  -I$(abspath $(RTL_DIR))            \
  -I$(abspath $(GEN_VSRC_DIR))       \
  -CFLAGS "$(LEMU_CXXFLAGS)"         \
  -LDFLAGS "$(LEMU_LDFLAGS)"         \
  -CFLAGS "\$$(PGO_CFLAGS)"          \
  -LDFLAGS "\$$(PGO_LDFLAGS)"        \
  -o $(LEMU_TARGET)                  \
  $(LEMU_FLAGS)

LEMU_MK = $(LEMU_BUILD_DIR)/V$(EMU_TOP).mk
LEMU_CONFIG_STAMP = $(LEMU_BUILD_DIR)/.lemu-config
LEMU_HEADERS := $(EMU_HEADERS) $(shell find $(LEMU_CSRC_DIR) -name "*.h" 2> /dev/null)
LEMU_PGO_WORKLOAD_DEP := $(if $(strip $(PGO_WORKLOAD)),$(PGO_WORKLOAD))

lemu-config-check:
	@case "$(LEMU_LARGE_MODEL)" in \
		0|1) ;; \
		*) echo "Error: LEMU_LARGE_MODEL must be 0 or 1 (got '$(LEMU_LARGE_MODEL)')." >&2; exit 1 ;; \
	esac
	@if [ "$(EMU_SNAPSHOT)" = "1" ] && [ "$(EMU_COVERAGE)" = "1" ]; then \
		echo "Error: Lemu does not support EMU_SNAPSHOT=1 together with EMU_COVERAGE=1." >&2; \
		exit 1; \
	fi
	@if [ "$(EMU_SNAPSHOT)" = "1" ] && [ -n "$(strip $(LEMU_SS_TEST))" ]; then \
		echo "Error: Lemu snapshot builds require an unpartitioned model; set LEMU_SS_TEST= (empty)." >&2; \
		exit 1; \
	fi
	@case "$(strip $(LEMU_SS_TEST))" in \
		'') ;; \
		*[!0-9]*|0*) \
			echo "Error: LEMU_SS_TEST must be a positive integer or empty." >&2; \
			exit 1 ;; \
	esac
	@if [ -n "$(strip $(EMU_TRACE))" ] && [ -n "$(strip $(filter --debug_access% --trace%,$(LEMU_DEBUG)))" ]; then \
		echo "Error: EMU_TRACE cannot be combined with waveform flags in LEMU_DEBUG." >&2; \
		exit 1; \
	fi
	@if [ -n "$(strip $(LEMU_INVALID_EXTRA_FLAGS))" ]; then \
		echo "Error: use EMU_* or LEMU_SS_TEST for model feature switches; remove from LEMU_FLAGS_EXTRA: $(LEMU_INVALID_EXTRA_FLAGS)" >&2; \
		exit 1; \
	fi
	@mkdir -p "$(LEMU_BUILD_DIR)"
# A large partitioned model can produce tens of thousands of objects; use
# find rather than expanding the cleanup glob into one ARG_MAX-sized command.
	@tmp="$(LEMU_CONFIG_STAMP).tmp.$$$$"; \
	{ printf '%s\n' \
		'LEMU_BIN=$(LEMU_BIN_PATH)' \
		'LEMU_ROOT=$(LEMU_ROOT)' \
		'LEMU_VERSION=$(LEMU_VERSION_TEXT)' \
		'EMU_TOP=$(EMU_TOP)' \
		'EMU_OPTIMIZE=$(EMU_OPTIMIZE)' \
		'LEMU_OPT_FAST=$(LEMU_OPT_FAST)' \
		'PGO_CFLAGS=$(PGO_CFLAGS)' \
		'PGO_LDFLAGS=$(PGO_LDFLAGS)' \
		'PGO_WORKLOAD=$(PGO_WORKLOAD)' \
		'PGO_MAX_CYCLE=$(PGO_MAX_CYCLE)' \
		'PGO_EMU_ARGS=$(PGO_EMU_ARGS)' \
		'PGO_BOLT=$(PGO_BOLT)' \
		'LLVM_BOLT=$(LLVM_BOLT)' \
		'LLVM_PROFDATA=$(LLVM_PROFDATA)' \
		'LEMU_TARGET=$(LEMU_TARGET)' \
		'RTL_DIR=$(RTL_DIR)' \
		'GEN_VSRC_DIR=$(GEN_VSRC_DIR)' \
		'SIM_TOP_V=$(SIM_TOP_V)' \
		'SIM_VSRC=$(SIM_VSRC)' \
		'LEMU_CXXFILES=$(LEMU_CXXFILES)' \
		'EMU_TRACE=$(EMU_TRACE)' \
		'EMU_TRACE_ALL=$(EMU_TRACE_ALL)' \
		'LEMU_DEBUG=$(LEMU_DEBUG)' \
		'EMU_THREADS=$(EMU_THREADS)' \
		'EMU_SNAPSHOT=$(EMU_SNAPSHOT)' \
		'EMU_COVERAGE=$(EMU_COVERAGE)' \
		'LEMU_SS_TEST=$(LEMU_SS_TEST)' \
		'LEMU_SPLIT_VAR=$(LEMU_SPLIT_VAR)' \
		'LEMU_LARGE_MODEL=$(LEMU_LARGE_MODEL)' \
		'LEMU_LARGE_MODEL_LINKER_SCRIPT=$(LEMU_LARGE_MODEL_LINKER_SCRIPT)' \
		'LEMU_FLAGS_EXTRA=$(LEMU_FLAGS_EXTRA)' \
		'LEMU_FLAGS=$(LEMU_FLAGS)' \
		'LEMU_CXXFLAGS=$(LEMU_CXXFLAGS)' \
		'LEMU_LDFLAGS=$(LEMU_LDFLAGS)'; \
	} > "$$tmp"; \
	if test -r "$(LEMU_CONFIG_STAMP)" && cmp -s "$$tmp" "$(LEMU_CONFIG_STAMP)"; then \
		rm -f "$$tmp"; \
	else \
		$(LEMU_CLEAN_OBJECTS); \
		rm -f "$(LEMU_TARGET)" "$(LEMU_MK)"; \
		mv -f "$$tmp" "$(LEMU_CONFIG_STAMP)"; \
	fi

$(LEMU_CONFIG_STAMP): lemu-config-check
	@:

$(LEMU_MK): $(SIM_TOP_V) $(SIM_VSRC) $(LEMU_CONFIG_STAMP) | $(LEMU_CXXFILES)
	@if ! command -v "$(LEMU_BIN_PATH)" > /dev/null 2>&1; then \
		echo "Error: Lemu executable '$(LEMU_BIN)' was not found. Set LEMU_BIN/LEMU_ROOT or add lemu to PATH." >&2; \
		exit 1; \
	fi
ifeq ($(EMU_COVERAGE),1)
	@python3 ./scripts/coverage/vtransform.py $(RTL_DIR)
endif
	@mkdir -p $(@D)
	@printf '\n[lemu] Generating C++ files...\n' >> $(TIMELOG)
	@date -R | tee -a $(TIMELOG)
	@cd $(@D) && $(TIME_CMD) $(LEMU_ENV) "$(LEMU_BIN_PATH)" $(LEMU_FLAGS_ALL) \
		--Mdir $(@D) $(abspath $(SIM_TOP_V)) $(SIM_VSRC) $(LEMU_CXXFILES) || \
		{ status=$$?; rm -f "$@"; exit $$status; }
	@sed -i -e 's/$(subst /,\/,$(NOOP_HOME))/$$(NOOP_HOME)/g' \
	       -e '/^default:/i\NOOP_HOME ?= $(subst /,\/,$(NOOP_HOME))\n' $@ || \
		{ status=$$?; rm -f "$@"; exit $$status; }
ifneq ($(LEMU_5_000),1)
	@sed -i 's/private/public/g' $(LEMU_BUILD_DIR)/V$(EMU_TOP).h || { status=$$?; rm -f "$@"; exit $$status; }
	@sed -i 's/const lemuSymsp/lemuSymsp/g' $(LEMU_BUILD_DIR)/V$(EMU_TOP).h || { status=$$?; rm -f "$@"; exit $$status; }
	@sed -i 's/LemuRtThreadPool\* const/LemuRtThreadPool*/g' $(LEMU_BUILD_DIR)/V$(EMU_TOP)__Syms.h || { status=$$?; rm -f "$@"; exit $$status; }
endif
ifeq ($(LEMU_LARGE_MODEL),1)
	@printf '\n# XiangShan large-code-model link configuration (opt-in)\ninclude $$(NOOP_HOME)/difftest/src/test/csrc/lemu/large-model.mk\n' >> "$@"
endif

LEMU_COMPILE_FILTER =
# 2> $(BUILD_DIR)/g++.err.log | tee $(BUILD_DIR)/g++.out.log | grep 'g++' | awk '{print "Compiling/Generating", $$NF}'

lemu-build-emu: $(SIM_EXTRA_OBJS)
ifeq ($(REMOTE),localhost)
	@sync -d $(BUILD_DIR) $(LEMU_BUILD_DIR)
	$(TIME_CMD) $(MAKE) -s LEMU_MODEL_PARALLEL_BUILDS=1 OPT_SLOW="-O0" \
						$(LEMU_LARGE_MODEL_MAKE_ARGS) \
						OPT_FAST="$(LEMU_OPT_FAST)" \
						PGO_CFLAGS="$(PGO_CFLAGS)" \
						PGO_LDFLAGS="$(PGO_LDFLAGS)" \
						OBJCACHE="$(OBJCACHE)" \
						$(LEMU_ROOT_MAKE_ARG) \
						-C $(LEMU_BUILD_DIR) -f $(LEMU_MK) $(LEMU_COMPILE_FILTER)
	@sync -d $(BUILD_DIR) $(LEMU_BUILD_DIR)
else
	ssh -tt $(REMOTE) 'export NOOP_HOME=$(NOOP_HOME); \
					   $(MAKE) -C $(NOOP_HOME)/difftest lemu-build-emu \
					   -j `nproc` \
					   LEMU_LARGE_MODEL="$(LEMU_LARGE_MODEL)" \
					   LEMU_LARGE_MODEL_LINKER_SCRIPT="$(LEMU_LARGE_MODEL_LINKER_SCRIPT)" \
					   OPT_FAST="'"$(LEMU_OPT_FAST)"'" \
					   PGO_CFLAGS="'"$(PGO_CFLAGS)"'" \
					   PGO_LDFLAGS="'"$(PGO_LDFLAGS)"'" \
					   OBJCACHE="'"$(OBJCACHE)"'" \
					   $(LEMU_ROOT_MAKE_ARG)'
endif

$(LEMU_TARGET): $(LEMU_MK) $(SIM_VSRC) $(LEMU_CXXFILES) $(LEMU_HEADERS) $(SIM_EXTRA_OBJS) $(LEMU_PGO_WORKLOAD_DEP) $(LEMU_LARGE_MODEL_DEPS)
	@printf '\n[c++] Compiling C++ files...\n' >> $(TIMELOG)
	@date -R | tee -a $(TIMELOG)
ifdef PGO_WORKLOAD
ifeq ($(PGO_BOLT),1)
	@$(MAKE) lemu-clean-obj
endif
	$(MAKE) pgo-build \
		PGO_CLEAN_OBJ=lemu-clean-obj \
		PGO_BUILD_TARGET=lemu-build-emu \
		PGO_TARGET=$(LEMU_TARGET) \
		PGO_EMU_DIR=$(LEMU_BUILD_DIR) \
		PGO_MAX_CYCLE=$(PGO_MAX_CYCLE)
else
	@$(MAKE) lemu-build-emu
endif # ifdef PGO_WORKLOAD

lemu-emu: $(LEMU_TARGET)
lemu-emu-mk: $(LEMU_MK)

LEMU_COVERAGE_BIN ?= $(if $(strip $(LEMU_ROOT)),$(LEMU_ROOT)/bin/lemu_coverage,lemu_coverage)
lemu-coverage:
	@if ! command -v "$(LEMU_COVERAGE_BIN)" > /dev/null 2>&1; then \
		echo "Error: Lemu coverage tool '$(LEMU_COVERAGE_BIN)' was not found." >&2; \
		exit 1; \
	fi
	@"$(LEMU_COVERAGE_BIN)" --annotate $(COVERAGE_DIR) --annotate-min 1 $(COVERAGE_DATA)
	@python3 scripts/coverage/coverage.py $(COVERAGE_DIR)
	@python3 scripts/coverage/statistics.py $(COVERAGE_DIR) > $(COVERAGE_DIR)/coverage_$(SIM_TOP).log
	@mv $(COVERAGE_DATA) $(COVERAGE_DIR)

lemu-clean-obj:
	$(LEMU_CLEAN_OBJECTS)
	rm -f "$(LEMU_TARGET)"

.PHONY: lemu-config-check lemu-build-emu lemu-clean-obj
