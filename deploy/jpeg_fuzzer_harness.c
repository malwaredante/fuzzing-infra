/* (c) Vladimir Garenitsa (MalwareDante), 2026. Original work. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <setjmp.h>
#include "jpeglib.h"

#define MAX_JPEG_PIXELS (8ULL * 1024 * 1024)
#define MAX_JPEG_ROWS_PER_CALL 4096

struct my_error_mgr {
  struct jpeg_error_mgr pub;
  jmp_buf setjmp_buffer;
};

static void my_error_exit(j_common_ptr cinfo) {
  struct my_error_mgr* myerr = (struct my_error_mgr*)cinfo->err;
  longjmp(myerr->setjmp_buffer, 1);
}

static void my_output_message(j_common_ptr cinfo) {
  (void)cinfo;
}

static void write_crash_input(const uint8_t *data, size_t size, const char *path) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
  if (fd >= 0) {
    (void)write(fd, data, size);
    (void)ftruncate(fd, size);
    close(fd);
  }
}

#ifdef __cplusplus
extern "C"
#endif
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  char crash_path[128];
  snprintf(crash_path, sizeof(crash_path), "/data/local/tmp2/last_crash_input_jpeg_%d.bin", (int)getpid());
  write_crash_input(data, size, crash_path);
  if (size < 2 || size > 4 * 1024 * 1024) goto cleanup;
  struct jpeg_decompress_struct cinfo;
  struct my_error_mgr jerr;
  JSAMPARRAY buffer;
  int row_stride;

  cinfo.err = jpeg_std_error(&jerr.pub);
  jerr.pub.error_exit = my_error_exit;
  jerr.pub.output_message = my_output_message;

  if (setjmp(jerr.setjmp_buffer)) {
    jpeg_destroy_decompress(&cinfo);
    goto cleanup;
  }

  jpeg_create_decompress(&cinfo);
  // Save all markers to exercise APP/COM/etc. parsing paths.
  for (int marker = 0; marker < 256; ++marker) {
    jpeg_save_markers(&cinfo, marker, 0xFFFF);
  }
  jpeg_mem_src(&cinfo, (unsigned char*)data, (unsigned long)size);
  if (jpeg_read_header(&cinfo, TRUE) != JPEG_HEADER_OK) {
    jpeg_destroy_decompress(&cinfo);
    goto cleanup;
  }
  unsigned long long pixels = (unsigned long long)cinfo.image_width * cinfo.image_height;
  if (pixels > MAX_JPEG_PIXELS) {
    jpeg_destroy_decompress(&cinfo);
    goto cleanup;
  }
  if (!jpeg_start_decompress(&cinfo)) {
    jpeg_destroy_decompress(&cinfo);
    goto cleanup;
  }

  // Exercise partial-decode skip path.
  if (cinfo.output_height > 4) {
    (void)jpeg_skip_scanlines(&cinfo, cinfo.output_height / 4);
  }

  row_stride = cinfo.output_width * cinfo.output_components;
  buffer = (*cinfo.mem->alloc_sarray)((j_common_ptr)&cinfo, JPOOL_IMAGE,
                                      row_stride, 1);
  unsigned int rows_read = 0;
  while (cinfo.output_scanline < cinfo.output_height) {
    (void)jpeg_read_scanlines(&cinfo, buffer, 1);
    if (++rows_read > MAX_JPEG_ROWS_PER_CALL) {
      jpeg_destroy_decompress(&cinfo);
      return 0;
    }
  }
  (void)jpeg_finish_decompress(&cinfo);
  jpeg_destroy_decompress(&cinfo);

  // Exercise JPEG compression paths using the input as raw RGB pixels.
  if (size >= 6) {
    struct jpeg_compress_struct cinfo_c;
    struct my_error_mgr jerr_c;
    cinfo_c.err = jpeg_std_error(&jerr_c.pub);
    jerr_c.pub.error_exit = my_error_exit;
    jerr_c.pub.output_message = my_output_message;
    if (setjmp(jerr_c.setjmp_buffer)) {
      jpeg_destroy_compress(&cinfo_c);
      goto cleanup;
    }

    int cw = 1 + ((data[0] | (data[1] << 8)) % 128);
    int ch = 1 + ((data[2] | (data[3] << 8)) % 128);
    int quality = data[4] % 101;
    size_t row_stride = (size_t)cw * 3;
    size_t header = 6;
    if (size <= header + row_stride) goto cleanup;
    size_t max_h = (size - header) / row_stride;
    if (max_h == 0) goto cleanup;
    if ((size_t)ch > max_h) ch = (int)max_h;

    jpeg_create_compress(&cinfo_c);
    unsigned char* outbuffer = NULL;
    unsigned long outsize = 0;
    jpeg_mem_dest(&cinfo_c, &outbuffer, &outsize);
    cinfo_c.image_width = (JDIMENSION)cw;
    cinfo_c.image_height = (JDIMENSION)ch;
    cinfo_c.input_components = 3;
    cinfo_c.in_color_space = JCS_RGB;
    jpeg_set_defaults(&cinfo_c);
    jpeg_set_quality(&cinfo_c, quality, TRUE);
    jpeg_start_compress(&cinfo_c, TRUE);
    while (cinfo_c.next_scanline < cinfo_c.image_height) {
      JSAMPROW row = (JSAMPROW)(data + header + cinfo_c.next_scanline * row_stride);
      (void)jpeg_write_scanlines(&cinfo_c, &row, 1);
    }
    jpeg_finish_compress(&cinfo_c);
    if (outbuffer) free(outbuffer);
    jpeg_destroy_compress(&cinfo_c);
  }

  goto cleanup;

cleanup:
  unlink(crash_path);
  return 0;
}
