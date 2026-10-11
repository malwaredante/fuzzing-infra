/* (c) Vladimir Garenitsa (MalwareDante), 2026. Original work. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <setjmp.h>
#include <sanitizer/common_interface_defs.h>
#include "png.h"
#include <zlib.h>

#define MAX_PNG_DIM 8192
#define MAX_PNG_ROWBUF (1024 * 1024)
#define MAX_PNG_ALLOC (8 * 1024 * 1024)

static void png_silent_warning(png_structp png, png_const_charp msg) {
  (void)png;
  (void)msg;
}

static png_voidp png_fuzzer_malloc(png_structp png, png_alloc_size_t size) {
  (void)png;
  if (size == 0 || size > MAX_PNG_ALLOC) return NULL;
  return malloc((size_t)size);
}

static void png_fuzzer_free(png_structp png, png_voidp ptr) {
  (void)png;
  free(ptr);
}

static void write_crash_input(const uint8_t *data, size_t size, const char *path) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
  if (fd >= 0) {
    (void)write(fd, data, size);
    (void)ftruncate(fd, size);
    close(fd);
  }
}

struct png_mem_io {
  const uint8_t* data;
  size_t size;
  size_t pos;
};

static void png_mem_read(png_structp png, png_bytep out, png_size_t len) {
  struct png_mem_io* io = (struct png_mem_io*)png_get_io_ptr(png);
  if (!io || len == 0) return;
  if (io->pos + len > io->size) png_error(png, "read past end");
  memcpy(out, io->data + io->pos, len);
  io->pos += len;
}

#ifdef __cplusplus
extern "C"
#endif
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  static png_bytep buffer = NULL;
  static png_bytepp row_pointers = NULL;
  png_structp png = NULL;
  png_infop info = NULL;

  buffer = NULL;
  row_pointers = NULL;

  char crash_path[128];
  snprintf(crash_path, sizeof(crash_path), "/data/local/tmp2/last_crash_input_png_%d.bin", (int)getpid());
  write_crash_input(data, size, crash_path);
  if (size < 8 || size > 4 * 1024 * 1024) goto cleanup;

  png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, png_silent_warning);
  if (!png) goto cleanup;
  info = png_create_info_struct(png);
  if (!info) {
    png_destroy_read_struct(&png, NULL, NULL);
    goto cleanup;
  }

  if (setjmp(png_jmpbuf(png))) {
    free(row_pointers);
    row_pointers = NULL;
    free(buffer);
    buffer = NULL;
    png_destroy_read_struct(&png, &info, NULL);
    goto cleanup;
  }

  png_set_user_limits(png, MAX_PNG_DIM, MAX_PNG_DIM);
  png_set_mem_fn(png, NULL, png_fuzzer_malloc, png_fuzzer_free);
  png_set_error_fn(png, NULL, NULL, png_silent_warning);
  png_set_chunk_malloc_max(png, 8 * 1024 * 1024);
  png_set_chunk_cache_max(png, 100);
  png_set_keep_unknown_chunks(png, PNG_HANDLE_CHUNK_NEVER, NULL, 0);

  struct png_mem_io io = { data, size, 0 };
  png_set_read_fn(png, &io, png_mem_read);

  png_read_info(png, info);

  png_uint_32 width = 0, height = 0;
  int bit_depth = 0, color_type = 0;
  png_get_IHDR(png, info, &width, &height, &bit_depth, &color_type, NULL, NULL, NULL);

  if (width == 0 || height == 0) {
    png_destroy_read_struct(&png, &info, NULL);
    goto cleanup;
  }

  png_read_update_info(png, info);
  size_t rowbytes = png_get_rowbytes(png, info);
  if (rowbytes == 0) {
    png_destroy_read_struct(&png, &info, NULL);
    goto cleanup;
  }

  unsigned long long total_size = (unsigned long long)rowbytes * (unsigned long long)height;
  if (total_size > MAX_PNG_ROWBUF) {
    png_destroy_read_struct(&png, &info, NULL);
    goto cleanup;
  }

  buffer = (png_bytep)malloc((size_t)total_size);
  if (!buffer) {
    png_destroy_read_struct(&png, &info, NULL);
    goto cleanup;
  }

  row_pointers = (png_bytepp)malloc(height * sizeof(png_bytep));
  if (!row_pointers) {
    free(buffer);
    buffer = NULL;
    png_destroy_read_struct(&png, &info, NULL);
    goto cleanup;
  }

  for (png_uint_32 y = 0; y < height; ++y) {
    row_pointers[y] = buffer + (size_t)y * rowbytes;
  }

  png_read_image(png, row_pointers);

  // Exercise the simplified PNG write path with the decoded image.
  int encode_fmt = 0, can_encode = 0;
  if (bit_depth == 8) {
    switch (color_type) {
      case PNG_COLOR_TYPE_GRAY: encode_fmt = PNG_FORMAT_GRAY; can_encode = 1; break;
      case PNG_COLOR_TYPE_GA:   encode_fmt = PNG_FORMAT_GA;   can_encode = 1; break;
      case PNG_COLOR_TYPE_RGB:  encode_fmt = PNG_FORMAT_RGB;  can_encode = 1; break;
      case PNG_COLOR_TYPE_RGBA: encode_fmt = PNG_FORMAT_RGBA; can_encode = 1; break;
    }
  }
  if (can_encode) {
    png_image image;
    memset(&image, 0, sizeof(image));
    image.version = PNG_IMAGE_VERSION;
    image.width = width;
    image.height = height;
    image.format = encode_fmt;
    png_alloc_size_t out_size = 0;
    if (png_image_write_to_memory(&image, NULL, &out_size, 0, buffer,
                                  (png_int_32)rowbytes, NULL)) {
      png_bytep out = (png_bytep)malloc((size_t)out_size);
      if (out) {
        if (png_image_write_to_memory(&image, out, &out_size, 0, buffer,
                                      (png_int_32)rowbytes, NULL)) {
          free(out);
        } else {
          free(out);
        }
      }
    }
  }

  png_read_end(png, NULL);

  free(row_pointers);
  row_pointers = NULL;
  free(buffer);
  buffer = NULL;
  png_destroy_read_struct(&png, &info, NULL);

cleanup:
  free(row_pointers);
  free(buffer);
  if (png) png_destroy_read_struct(&png, &info, NULL);
  unlink(crash_path);
  return 0;
}

static const uint8_t PNG_SIG[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};

static const uint8_t KNOWN_TYPES[][4] = {
    {'I','H','D','R'}, {'I','E','N','D'}, {'I','D','A','T'}, {'P','L','T','E'},
    {'t','R','N','S'}, {'g','A','M','A'}, {'c','H','R','M'}, {'s','R','G','B'},
    {'i','C','C','P'}, {'t','E','X','t'}, {'z','T','X','t'}, {'i','T','X','t'},
    {'b','K','G','D'}, {'p','H','Y','s'}, {'s','B','I','T'}, {'t','I','M','E'}
};
#define N_KNOWN (sizeof(KNOWN_TYPES) / sizeof(KNOWN_TYPES[0]))

static uint32_t xorshift32(uint32_t *s) {
    *s ^= *s << 13;
    *s ^= *s >> 17;
    *s ^= *s << 5;
    return *s;
}

static uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8)  |  (uint32_t)p[3];
}

static void write_be32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static uint32_t chunk_crc(const uint8_t *type, const uint8_t *data, uint32_t len) {
    uLong c = crc32(0L, Z_NULL, 0);
    c = crc32(c, type, 4);
    if (len) c = crc32(c, data, (uInt)len);
    return (uint32_t)c;
}

#ifdef __cplusplus
extern "C"
#endif
size_t LLVMFuzzerCustomMutator(uint8_t *Data, size_t Size, size_t MaxSize, unsigned int Seed) {
    if (MaxSize < 8) return Size;
    uint32_t rng = Seed ? Seed : 1;
    xorshift32(&rng);

    if (Size < 8 || memcmp(Data, PNG_SIG, 8) != 0) {
        size_t out = Size < 8 ? Size : 8;
        if (out >= 8) memcpy(Data, PNG_SIG, 8);
        return out;
    }

    struct chunk { const uint8_t *type; const uint8_t *data; uint8_t *crc; uint32_t len; };
    struct chunk chunks[64];
    int n = 0;
    size_t pos = 8;
    while (pos + 8 <= Size && n < 64) {
        uint32_t len = be32(Data + pos);
        size_t data_off = pos + 8;
        if (len > MaxSize || data_off + (size_t)len + 4 > Size) break;
        chunks[n].type = Data + pos + 4;
        chunks[n].data = Data + data_off;
        chunks[n].crc = Data + data_off + len;
        chunks[n].len = len;
        n++;
        pos = data_off + len + 4;
    }
    if (n == 0) return Size;

    int op = xorshift32(&rng) % 4;

    if (op == 0) {
        int idx = xorshift32(&rng) % n;
        if (chunks[idx].len > 0) {
            size_t off = xorshift32(&rng) % chunks[idx].len;
            uint8_t *target = (uint8_t*)chunks[idx].data + off;
            *target ^= (uint8_t)(xorshift32(&rng) | 1);
            write_be32(chunks[idx].crc, chunk_crc(chunks[idx].type, chunks[idx].data, chunks[idx].len));
        }
    } else if (op == 1) {
        int idx = xorshift32(&rng) % n;
        int t = xorshift32(&rng) % N_KNOWN;
        memcpy((uint8_t*)chunks[idx].type, KNOWN_TYPES[t], 4);
        write_be32(chunks[idx].crc, chunk_crc(chunks[idx].type, chunks[idx].data, chunks[idx].len));
    } else if (op == 2) {
        static const uint8_t ttype[4] = {'t','E','X','t'};
        static const uint8_t tdata[2] = {'x', '\0'};
        uint32_t tlen = 2;
        size_t need = 12 + tlen;
        if (Size + need <= MaxSize) {
            uint8_t *p = Data + Size;
            write_be32(p, tlen); p += 4;
            memcpy(p, ttype, 4); p += 4;
            memcpy(p, tdata, tlen); p += tlen;
            write_be32(p, chunk_crc(ttype, tdata, tlen));
            Size += need;
        }
    } else if (op == 3) {
        int idx = xorshift32(&rng) % n;
        size_t need = (size_t)chunks[idx].len + 12;
        if (Size + need <= MaxSize) {
            const uint8_t *src = chunks[idx].type - 4;
            memcpy(Data + Size, src, need);
            Size += need;
        }
    }
    return Size;
}
