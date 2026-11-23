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

#ifndef __WAVEFORM_H
#define __WAVEFORM_H

#include "lemurt.h"
#ifdef ENABLE_FST
#include <lemurt_fst_c.h>
#else
#include <lemurt_vcd_c.h>
#endif // ENABLE_FST
#include <cstdint>
#include <functional>

using TraceBindFunc = std::function<void(LemuRtTraceBaseC *, int)>;

class EmuWaveform {
private:
#ifdef ENABLE_FST
  LemuRtFstC *tfp = nullptr;
#else
  LemuRtVcdC *tfp = nullptr;
#endif // ENABLE_FST

  // Waveform time may differ from the CPU clock.
  uint64_t waveform_clock;

  static const char *default_filename(uint64_t cycles);

public:
  EmuWaveform(const TraceBindFunc &trace, uint64_t cycles);
  EmuWaveform(const TraceBindFunc &trace, uint64_t cycles, const char *filename);
  ~EmuWaveform();

  void tick();
};

#endif // __WAVEFORM_H
