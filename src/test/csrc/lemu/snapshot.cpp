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

#include "snapshot.h"

#ifdef LEMU_MODEL_SAVABLE

#include <limits>

namespace {

// Keep the outer framing independent of Lemu's private save header.  Some
// Lemu releases ship an 11-byte header together with an alignment assert;
// these markers are deliberately aligned and are checked symmetrically by
// this adapter.
constexpr char kSnapshotHeader[] = "XiangShanLemu01\n";
constexpr char kSnapshotTrailer[] = "XiangShanLemu!01";
constexpr char kLegacySnapshotHeader[] = "lemusave02\n";
constexpr char kLegacySnapshotTrailer[] = "vltsaved";
static_assert((sizeof(kSnapshotHeader) - 1) % 8 == 0);
static_assert((sizeof(kSnapshotTrailer) - 1) % 8 == 0);

size_t snapshot_buffer_size() {
  assert(simMemory != nullptr);
  const uint64_t memory_size = simMemory->get_size();
#ifndef CONFIG_NO_DIFFTEST
  // Lemu snapshots also carry the REF golden memory and its per-byte flags.
  constexpr size_t memory_copies = 5;
#else
  constexpr size_t memory_copies = 3;
#endif
  assert(memory_size <= std::numeric_limits<size_t>::max() / memory_copies);
  return memory_copies * static_cast<size_t>(memory_size);
}

uint8_t *allocate_snapshot_buffer(size_t size, int mmap_flags) {
  assert(size > 0);
  void *mapping = mmap(nullptr, size, PROT_READ | PROT_WRITE, mmap_flags, -1, 0);
  if (mapping == MAP_FAILED) {
    fprintf(stderr, "Could not mmap 0x%zx bytes for a simulation snapshot: %s\n", size, strerror(errno));
    assert(mapping != MAP_FAILED);
    return nullptr;
  }
  return static_cast<uint8_t *>(mapping);
}

// Keep anonymous zero pages sparse without assuming either pointer is aligned.
void copy_nonzero_bytes(uint8_t *__restrict dest, const uint8_t *__restrict src, size_t size) {
  while (size >= sizeof(uint64_t)) {
    uint64_t word;
    memcpy(&word, src, sizeof(word));
    if (word != 0) {
      memcpy(dest, &word, sizeof(word));
    }
    dest += sizeof(word);
    src += sizeof(word);
    size -= sizeof(word);
  }
  if (size != 0) {
    memcpy(dest, src, size);
  }
}

} // namespace

LemuRtSaveMem::~LemuRtSaveMem() {
  release_buffer();
}

void LemuRtSaveMem::release_buffer() {
  if (buf != nullptr) {
    int rc = munmap(buf, buf_size);
    assert(rc == 0);
    buf = nullptr;
  }
  buf_size = 0;
  size = 0;
  m_isOpen = false;
}

void LemuRtSaveMem::init(const char *filename) {
  assert(filename != nullptr);
  release_buffer();

  buf_size = snapshot_buffer_size();
  buf = allocate_snapshot_buffer(buf_size, MAP_ANON | MAP_PRIVATE | MAP_NORESERVE);
  size = 0;
  m_cp = m_bufp;
  m_filename = filename;
  m_isOpen = true;
  write(kSnapshotHeader, sizeof(kSnapshotHeader) - 1);
}

void LemuRtSaveMem::unbuf_write(const void *__restrict datap, size_t write_size) LEMU_MT_UNSAFE_ONE {
  assert(buf != nullptr);
  assert(datap != nullptr || write_size == 0);
  assert(size <= buf_size);
  assert(write_size <= buf_size - size);
  if (write_size != 0) {
    copy_nonzero_bytes(buf + size, static_cast<const uint8_t *>(datap), write_size);
  }
  size += write_size;
}

void LemuRtSaveMem::flush() {
  assert(m_cp >= m_bufp);
  const size_t flush_size = static_cast<size_t>(m_cp - m_bufp);
  if (flush_size == 0) {
    return;
  }

  assert(buf != nullptr);
  assert(size <= buf_size);
  assert(flush_size <= buf_size - size);
  memcpy(buf + size, m_bufp, flush_size);
  size += flush_size;
  m_cp = m_bufp;
}

void LemuRtSaveMem::save() {
  if (size == 0 && m_cp == m_bufp) {
    return;
  }

  write(kSnapshotTrailer, sizeof(kSnapshotTrailer) - 1);
  flush();
  m_isOpen = false;

  std::string saved_filename = m_filename;
  bool saved = false;
#ifdef NO_GZ_COMPRESSION
  constexpr bool can_compress = false;
#else
  constexpr bool can_compress = true;
#endif
  if (!can_compress || size <= 512 * 1024 * 1024UL) {
    FILE *fp = fopen(saved_filename.c_str(), "wb");
    if (fp != nullptr) {
      saved = fwrite(buf, 1, size, fp) == size;
      saved = fclose(fp) == 0 && saved;
    }
  } else {
    saved_filename += ".gz";
    const long compressed_size = snapshot_compressToFile(buf, saved_filename.c_str(), static_cast<long>(size));
    saved = compressed_size >= static_cast<long>(size);
  }

  if (!saved) {
    fprintf(stderr, "Could not save simulation snapshot to %s\n", saved_filename.c_str());
    assert(saved);
    return;
  }

  size = 0;
  Info("save snapshot to %s...\n", saved_filename.c_str());
}

LemuRtRestoreMem::LemuRtRestoreMem() {
  buf_size = snapshot_buffer_size();
  buf = allocate_snapshot_buffer(buf_size, MAP_ANON | MAP_PRIVATE);
}

LemuRtRestoreMem::~LemuRtRestoreMem() {
  close();
  release_buffer();
}

void LemuRtRestoreMem::release_buffer() {
  if (buf != nullptr) {
    int rc = munmap(buf, buf_size);
    assert(rc == 0);
    buf = nullptr;
  }
  buf_size = 0;
  size = 0;
  buf_ptr = 0;
  legacy_framing = false;
  m_isOpen = false;
}

void LemuRtRestoreMem::fill() {
  m_assertOne.check();
  if (!isOpen()) {
    return;
  }

  uint8_t *read_ptr = m_bufp;
  for (uint8_t *src = m_cp; src < m_endp; *read_ptr++ = *src++) {}
  m_endp = m_bufp + (m_endp - m_cp);
  m_cp = m_bufp;

  while (true) {
    const ssize_t remaining = m_bufp + bufferSize() - m_endp;
    if (remaining == 0) {
      break;
    }

    errno = 0;
    const ssize_t got = unbuf_read(m_endp, remaining);
    if (got > 0) {
      m_endp += got;
    } else if (got < 0) {
      if (errno != EAGAIN && errno != EINTR) {
        const std::string msg = std::string(__func__) + ": " + strerror(errno);
        LEMU_FATAL_MT("", 0, "", msg.c_str());
        return;
      }
    } else {
      while (m_endp < m_bufp + bufferSize()) {
        *m_endp++ = '\0';
      }
      break;
    }
  }
}

void LemuRtRestoreMem::open(const char *filename) {
  m_assertOne.check();
  assert(filename != nullptr);
  if (isOpen()) {
    return;
  }

  LEMU_DEBUG_IF(LEMU_DBG_MSGF("- restore: opening restore file %s\n", filename););

  if (filename[0] == '|') {
    fprintf(stderr, "Snapshot input pipes are unsupported: %s\n", filename);
    assert(filename[0] != '|');
    return;
  }

  buf_ptr = 0;
  if (isGzFile(filename)) {
    const long loaded_size = readFromGz(buf, filename, static_cast<long>(buf_size), LOAD_SNAPSHOT);
    assert(loaded_size > 0);
    size = static_cast<size_t>(loaded_size);
  } else {
    FILE *fp = fopen(filename, "rb");
    assert(fp != nullptr);

    assert(fseek(fp, 0, SEEK_END) == 0);
    const long file_size = ftell(fp);
    assert(file_size > 0);
    assert(static_cast<size_t>(file_size) <= buf_size);
    rewind(fp);

    size = static_cast<size_t>(file_size);
    const bool loaded = fread(buf, 1, size, fp) == size;
    const bool closed = fclose(fp) == 0;
    assert(loaded && closed);
  }

  m_isOpen = true;
  m_filename = filename;
  m_cp = m_bufp;
  m_endp = m_bufp;
  legacy_framing = size >= sizeof(kLegacySnapshotHeader) - 1 &&
                   memcmp(buf, kLegacySnapshotHeader, sizeof(kLegacySnapshotHeader) - 1) == 0;
  if (legacy_framing) {
    readAssert(kLegacySnapshotHeader, sizeof(kLegacySnapshotHeader) - 1);
  } else {
    readAssert(kSnapshotHeader, sizeof(kSnapshotHeader) - 1);
  }
}

void LemuRtRestoreMem::close() {
  if (!isOpen()) {
    return;
  }
  if (legacy_framing) {
    readAssert(kLegacySnapshotTrailer, sizeof(kLegacySnapshotTrailer) - 1);
  } else {
    readAssert(kSnapshotTrailer, sizeof(kSnapshotTrailer) - 1);
  }
  flush();
  m_isOpen = false;
}

long LemuRtRestoreMem::unbuf_read(uint8_t *dest, long read_size) {
  assert(dest != nullptr);
  assert(read_size > 0);
  assert(buf_ptr <= size);

  const size_t remaining = size - buf_ptr;
  size_t actual_size = static_cast<size_t>(read_size);
  if (actual_size > remaining) {
    actual_size = remaining;
  }

  if (actual_size != 0) {
    memcpy(dest, buf + buf_ptr, actual_size);
  }
  buf_ptr += actual_size;
  return static_cast<long>(actual_size);
}

#endif // LEMU_MODEL_SAVABLE
