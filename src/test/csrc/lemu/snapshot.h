/***************************************************************************************
* Copyright (c) 2020-2023 Institute of Computing Technology, Chinese Academy of Sciences
* Copyright (c) 2020-2021 Peng Cheng Laboratory
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

#ifndef SNAPSHOT_H
#define SNAPSHOT_H

#include "VSimTop.h"
#include "compress.h"
#include "ram.h"
#include <lemurt_save.h>
#include <sys/mman.h>

class LemuRtSaveMem : public LemuRtSerialize {
private:
  size_t buf_size = 0;
  uint8_t *buf = nullptr;
  size_t size = 0;

  void release_buffer();

public:
  LemuRtSaveMem() = default;
  ~LemuRtSaveMem() override;

  void init(const char *filename);
  void unbuf_write(const void *__restrict datap, size_t write_size) LEMU_MT_UNSAFE_ONE;

  void close() override LEMU_MT_UNSAFE_ONE {}
  void flush() override LEMU_MT_UNSAFE_ONE;
  void save();
};

class LemuRtRestoreMem : public LemuRtDeserialize {
private:
  size_t buf_size = 0;
  uint8_t *buf = nullptr;
  size_t size = 0;
  size_t buf_ptr = 0;
  bool legacy_framing = false;

  void release_buffer();

public:
  LemuRtRestoreMem();
  ~LemuRtRestoreMem() override;

  void open(const char *filename) LEMU_MT_UNSAFE_ONE;
  void open(const std::string &filename) LEMU_MT_UNSAFE_ONE {
    open(filename.c_str());
  }

  long unbuf_read(uint8_t *dest, long read_size);

  void close() override LEMU_MT_UNSAFE_ONE;
  void flush() override LEMU_MT_UNSAFE_ONE {}
  void fill() override LEMU_MT_UNSAFE_ONE;
};

#endif // SNAPSHOT_H
