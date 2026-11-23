/***************************************************************************************
* Copyright (c) 2020-2025 Institute of Computing Technology, Chinese Academy of Sciences
*
* DiffTest is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "waveform.h"
#include "common.h"

EmuWaveform::EmuWaveform(const TraceBindFunc &trace, uint64_t cycles)
    : EmuWaveform(trace, cycles, default_filename(cycles)) {}

EmuWaveform::EmuWaveform(const TraceBindFunc &trace, uint64_t cycles, const char *filename) : waveform_clock(cycles) {
#if LEMU_MODEL_TRACE == 1
  assert(filename != nullptr);
  LemuRt::traceEverOn(true);

#ifdef ENABLE_FST
  tfp = new LemuRtFstC;
#else
  tfp = new LemuRtVcdC;
#endif // ENABLE_FST

  trace(tfp, 99);
  tfp->open(filename);
  Info("dump wave to %s...\n", filename);
#endif // LEMU_MODEL_TRACE == 1
}

EmuWaveform::~EmuWaveform() {
#if LEMU_MODEL_TRACE == 1
  if (tfp != nullptr) {
    tfp->close();
    delete tfp;
    tfp = nullptr;
  }
#endif // LEMU_MODEL_TRACE == 1
}

const char *EmuWaveform::default_filename(uint64_t cycles) {
  char buf[64] = {};

  int cycle_len = 0;
  if (cycles > 0) {
    cycle_len = snprintf(buf, sizeof(buf), "_%" PRIu64, cycles);
    assert(cycle_len > 0 && static_cast<size_t>(cycle_len) < sizeof(buf));
  }

#ifdef ENABLE_FST
  const char *suffix = ".fst";
#else
  const char *suffix = ".vcd";
#endif // ENABLE_FST
  int suffix_len = snprintf(buf + cycle_len, sizeof(buf) - cycle_len, "%s", suffix);
  assert(suffix_len == static_cast<int>(strlen(suffix)));

  return create_noop_filename(buf);
}

void EmuWaveform::tick() {
#if LEMU_MODEL_TRACE == 1
  assert(tfp != nullptr);
  tfp->dump(waveform_clock);
  waveform_clock++;
#endif // LEMU_MODEL_TRACE == 1
}
