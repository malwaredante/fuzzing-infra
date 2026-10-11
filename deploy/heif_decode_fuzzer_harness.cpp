// (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <unistd.h>
#include <fcntl.h>
#include "heif.h"

#define MAX_HEIF_SIZE (64 * 1024)
#define MAX_HEIF_PIXELS (16ULL * 1024 * 1024)

class CrashInput {
    char path_[128];
public:
    CrashInput(const uint8_t* data, size_t size) {
        snprintf(path_, sizeof(path_), "/data/local/tmp2/last_crash_input_heif_decode_%d.bin", (int)getpid());
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
    if (width > 0 && height > 0 &&
        (unsigned long long)width * (unsigned long long)height <= MAX_HEIF_PIXELS) {
        heif_image* img = nullptr;
        err = heif_decode_image(handle, &img, heif_colorspace_undefined,
                                heif_chroma_undefined, nullptr);
        if (err.code == heif_error_Ok && img) {
            heif_image_release(img);
        }
    }

    heif_image_handle_release(handle);
    heif_context_free(ctx);
    return 0;
}
