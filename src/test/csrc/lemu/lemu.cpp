/***************************************************************************************
* Copyright (c) 2025 Institute of Computing Technology, Chinese Academy of Sciences
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

#include "simulator.h"
#include <memory>

LemuSim::LemuSim() : dut(new VSimTop) {}

LemuSim::~LemuSim() {
#if LEMU_MODEL_TRACE == 1
  delete waveform;
  waveform = nullptr;
#endif // LEMU_MODEL_TRACE == 1

#ifdef LEMU_MODEL_SAVABLE
  delete[] snapshot_slot;
  snapshot_slot = nullptr;
#endif // LEMU_MODEL_SAVABLE

  delete dut;
  dut = nullptr;
}

void LemuSim::configure_clocks(uint32_t core_half_period, uint32_t accelerator_half_period) {
#ifdef CONFIG_HAS_ACCELERATOR_CLOCK
  core_clock_half_period = core_half_period;
  accelerator_clock_half_period = accelerator_half_period;
  set_accelerator_clock(0);
#endif // CONFIG_HAS_ACCELERATOR_CLOCK
  // Settle reset and the low clock before the first rising edge.
  set_reset(1);
  set_clock(0);
  step();
}

void LemuSim::half_cycle(unsigned core_clock_level) {
#ifdef CONFIG_HAS_ACCELERATOR_CLOCK
  bool accelerator_edge_at_core_edge = false;
  accelerator_clock_phase += core_clock_half_period;
  while (accelerator_clock_phase >= accelerator_clock_half_period) {
    accelerator_clock_phase -= accelerator_clock_half_period;
    accelerator_clock_level ^= 1;
    set_accelerator_clock(accelerator_clock_level);

    if (accelerator_clock_phase == 0) {
      // Both clock edges occur at the same simulated time. Update both inputs
      // before a single evaluation to avoid imposing an accelerator-first order.
      set_clock(core_clock_level);
      step();
      accelerator_edge_at_core_edge = true;
    } else {
      step();
    }
  }

  if (!accelerator_edge_at_core_edge) {
    set_clock(core_clock_level);
    step();
  }
#else
  set_clock(core_clock_level);
  step();
#endif // CONFIG_HAS_ACCELERATOR_CLOCK
}

void LemuSim::single_cycle(const std::function<void()> &memory_tick, const std::function<bool()> &should_dump,
                           const std::function<bool()> &should_dump_full) {
  half_cycle(1);
  if (should_dump())
    waveform_tick();
  memory_tick();
  step_uart();
  half_cycle(0);
  if (should_dump_full())
    waveform_tick();
}

void LemuSim::reset_cycle(bool dump) {
  set_reset(1);
  half_cycle(1);
  if (dump)
    waveform_tick();
  half_cycle(0);
  if (dump)
    waveform_tick();
  set_reset(0);
  step();
}

#ifdef CONFIG_HAS_ACCELERATOR_CLOCK
void LemuSim::save_extra_state(const std::function<void(void *, size_t)> &write) {
  write(&accelerator_clock_phase, sizeof(accelerator_clock_phase));
  write(&accelerator_clock_level, sizeof(accelerator_clock_level));
}

void LemuSim::load_extra_state(const std::function<void(void *, size_t)> &read) {
  read(&accelerator_clock_phase, sizeof(accelerator_clock_phase));
  unsigned saved_accelerator_clock_level = 0;
  read(&saved_accelerator_clock_level, sizeof(saved_accelerator_clock_level));
  accelerator_clock_level = get_accelerator_clock();
  if (accelerator_clock_phase >= accelerator_clock_half_period ||
      saved_accelerator_clock_level != accelerator_clock_level) {
    printf("Invalid accelerator clock snapshot: phase=%" PRIu64 " level=%u, DUT level=%u, half-period=%" PRIu32 "\n",
           accelerator_clock_phase, saved_accelerator_clock_level, accelerator_clock_level,
           accelerator_clock_half_period);
    assert(0);
  }
}
#endif // CONFIG_HAS_ACCELERATOR_CLOCK

void LemuSim::atClone() {
  dut->atClone();
}

#if LEMU_MODEL_TRACE == 1
void LemuSim::waveform_init(uint64_t cycles) {
  delete waveform;
  waveform = new EmuWaveform(trace_bind, cycles);
}

void LemuSim::waveform_init(uint64_t cycles, const char *filename) {
  delete waveform;
  waveform = new EmuWaveform(trace_bind, cycles, filename);
}
#endif // LEMU_MODEL_TRACE == 1

void LemuSim::waveform_tick() {
#if LEMU_MODEL_TRACE == 1
  assert(waveform != nullptr);
  waveform->tick();
#else
  report_waveform_error();
#endif // LEMU_MODEL_TRACE == 1
}

#ifdef LEMU_MODEL_SAVABLE
void LemuSim::snapshot_init() {
  delete[] snapshot_slot;
  snapshot_slot = new LemuRtSaveMem[2];
  next_snapshot_slot = 0;
}

void LemuSim::snapshot_save(int index) {
  if (snapshot_slot == nullptr) {
    return;
  }

  if (index >= 0) {
    if (index >= 2) {
      assert(index < 2);
      return;
    }
    snapshot_slot[index].save();
  } else if (index == -1) {
    Info("Saving snapshots to file system. Please wait.\n");
    snapshot_slot[0].save();
    snapshot_slot[1].save();
    Info("Please remove unused snapshots manually\n");
  }
}

std::function<void(void *, size_t)> LemuSim::snapshot_take() {
  assert(snapshot_slot != nullptr);

  LemuRtSaveMem &stream = snapshot_slot[next_snapshot_slot];
  next_snapshot_slot ^= 1;

  stream.init(create_noop_filename(".snapshot"));
  stream << *dut;
  stream.flush();

  return [&stream](void *datap, size_t size) { stream.unbuf_write(datap, size); };
}

std::function<void(void *, size_t)> LemuSim::snapshot_load(const char *filename) {
  auto stream = std::make_shared<LemuRtRestoreMem>();
  stream->open(filename);
  *stream >> *dut;

  return [stream](void *datap, size_t size) { stream->read(datap, size); };
}
#endif // LEMU_MODEL_SAVABLE
