// (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <vector>
#include <unistd.h>
#include <fcntl.h>
#include "heif.h"

#define MAX_HEIF_SIZE (64 * 1024)
#define MAX_HEIF_PIXELS (16ULL * 1024 * 1024)

/* Write the current input to a per-child crash file. If the child crashes,
   the destructor does not run and the file persists for triage. */
class CrashInput {
    char path_[128];
public:
    CrashInput(const uint8_t* data, size_t size) {
        snprintf(path_, sizeof(path_), "/data/local/tmp2/last_crash_input_heif_%d.bin", (int)getpid());
        int fd = open(path_, O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd >= 0) {
            (void)write(fd, data, size);
            (void)ftruncate(fd, size);
            close(fd);
        }
    }
    ~CrashInput() { unlink(path_); }
};

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size == 0 || size > MAX_HEIF_SIZE) return 0;

  CrashInput ci(data, size);

  heif_context* ctx = heif_context_alloc();
  if (!ctx) return 0;

  // cap decoded image dimensions to avoid huge allocations/swap
  heif_context_set_maximum_image_size_limit(ctx, 2048);

  heif_error err = heif_context_read_from_memory(ctx, data, size, nullptr);
  if (err.code != heif_error_Ok) {
    heif_context_free(ctx);
    return 0;
  }

  heif_image_handle* handle = nullptr;
  err = heif_context_get_primary_image_handle(ctx, &handle);
  if (err.code != heif_error_Ok || !handle) {
    heif_context_free(ctx);
    return 0;
  }

  int width = heif_image_handle_get_width(handle);
  int height = heif_image_handle_get_height(handle);
  if (width <= 0 || height <= 0 ||
      (unsigned long long)width * (unsigned long long)height > MAX_HEIF_PIXELS) {
    heif_image_handle_release(handle);
    heif_context_free(ctx);
    return 0;
  }

  heif_image* img = nullptr;
  err = heif_decode_image(handle, &img, heif_colorspace_undefined,
                          heif_chroma_undefined, nullptr);
  if (err.code == heif_error_Ok && img) {
    heif_image_release(img);
  }

  // Exercise thumbnails
  int n_thumbs = heif_image_handle_get_number_of_thumbnails(handle);
  if (n_thumbs > 0) {
    std::vector<heif_item_id> thumb_ids(n_thumbs);
    int got = heif_image_handle_get_list_of_thumbnail_IDs(handle, thumb_ids.data(), n_thumbs);
    for (int i = 0; i < got; ++i) {
      heif_image_handle* thumb = nullptr;
      err = heif_image_handle_get_thumbnail(handle, thumb_ids[i], &thumb);
      if (err.code == heif_error_Ok && thumb) {
        int tw = heif_image_handle_get_width(thumb);
        int th = heif_image_handle_get_height(thumb);
        if (tw > 0 && th > 0 &&
            (unsigned long long)tw * (unsigned long long)th <= MAX_HEIF_PIXELS) {
          heif_image* timg = nullptr;
          err = heif_decode_image(thumb, &timg, heif_colorspace_undefined,
                                  heif_chroma_undefined, nullptr);
          if (err.code == heif_error_Ok && timg) heif_image_release(timg);
        }
        heif_image_handle_release(thumb);
      }
    }
  }

  // Exercise auxiliary images (depth, alpha, etc.)
  int n_aux = heif_image_handle_get_number_of_auxiliary_images(handle, 0);
  if (n_aux > 0) {
    std::vector<heif_item_id> aux_ids(n_aux);
    int got = heif_image_handle_get_list_of_auxiliary_image_IDs(handle, 0, aux_ids.data(), n_aux);
    for (int i = 0; i < got; ++i) {
      heif_image_handle* aux = nullptr;
      err = heif_image_handle_get_auxiliary_image_handle(handle, aux_ids[i], &aux);
      if (err.code == heif_error_Ok && aux) {
        int aw = heif_image_handle_get_width(aux);
        int ah = heif_image_handle_get_height(aux);
        if (aw > 0 && ah > 0 &&
            (unsigned long long)aw * (unsigned long long)ah <= MAX_HEIF_PIXELS) {
          heif_image* aimg = nullptr;
          err = heif_decode_image(aux, &aimg, heif_colorspace_undefined,
                                  heif_chroma_undefined, nullptr);
          if (err.code == heif_error_Ok && aimg) heif_image_release(aimg);
        }
        heif_image_handle_release(aux);
      }
    }
  }

  // Exercise metadata blocks (Exif / XMP / etc.)
  int n_meta = heif_image_handle_get_number_of_metadata_blocks(handle, NULL);
  if (n_meta > 0) {
    std::vector<heif_item_id> meta_ids(n_meta);
    int got = heif_image_handle_get_list_of_metadata_block_IDs(handle, NULL,
                                                               meta_ids.data(), n_meta);
    for (int i = 0; i < got; ++i) {
      size_t ms = heif_image_handle_get_metadata_size(handle, meta_ids[i]);
      if (ms > 0 && ms <= 64 * 1024) {
        std::vector<uint8_t> mdata(ms);
        err = heif_image_handle_get_metadata(handle, meta_ids[i], mdata.data());
        (void)err;
        (void)heif_image_handle_get_metadata_type(handle, meta_ids[i]);
      }
    }
  }

  // Exercise color profile.
  (void)heif_image_handle_get_color_profile_type(handle);
  size_t rcp_size = heif_image_handle_get_raw_color_profile_size(handle);
  if (rcp_size > 0 && rcp_size <= 64 * 1024) {
    std::vector<uint8_t> cp_data(rcp_size);
    err = heif_image_handle_get_raw_color_profile(handle, cp_data.data());
    (void)err;
  }

  // Exercise depth images
  int n_depth = heif_image_handle_get_number_of_depth_images(handle);
  if (n_depth > 0) {
    std::vector<heif_item_id> depth_ids(n_depth);
    int got = heif_image_handle_get_list_of_depth_image_IDs(handle, depth_ids.data(), n_depth);
    for (int i = 0; i < got; ++i) {
      heif_image_handle* dh = nullptr;
      err = heif_image_handle_get_depth_image_handle(handle, depth_ids[i], &dh);
      if (err.code == heif_error_Ok && dh) {
        int dw = heif_image_handle_get_width(dh);
        int dhh = heif_image_handle_get_height(dh);
        if (dw > 0 && dhh > 0 &&
            (unsigned long long)dw * (unsigned long long)dhh <= MAX_HEIF_PIXELS) {
          heif_image* dimg = nullptr;
          err = heif_decode_image(dh, &dimg, heif_colorspace_undefined,
                                  heif_chroma_undefined, nullptr);
          if (err.code == heif_error_Ok && dimg) heif_image_release(dimg);
        }
        heif_image_handle_release(dh);
      }
    }
  }

  heif_image_handle_release(handle);
  heif_context_free(ctx);
  return 0;
}
