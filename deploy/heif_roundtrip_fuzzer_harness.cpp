// (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <unistd.h>
#include <fcntl.h>
#include <vector>
#include "heif.h"

#define MAX_HEIF_SIZE (64 * 1024)
#define MAX_HEIF_PIXELS (4ULL * 1024 * 1024)
#define MAX_ENCODE_BYTES (8 * 1024 * 1024)

class CrashInput {
    char path_[128];
public:
    CrashInput(const uint8_t* data, size_t size) {
        snprintf(path_, sizeof(path_), "/data/local/tmp2/last_crash_input_heif_roundtrip_%d.bin", (int)getpid());
        int fd = open(path_, O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd >= 0) {
            (void)write(fd, data, size);
            (void)ftruncate(fd, size);
            close(fd);
        }
    }
    ~CrashInput() { unlink(path_); }
};

struct VecWriter {
    std::vector<uint8_t> buf;
};

static struct heif_error vec_write(struct heif_context*, const void* data,
                                   size_t size, void* userdata) {
    VecWriter* w = static_cast<VecWriter*>(userdata);
    if (w->buf.size() + size > MAX_ENCODE_BYTES) {
        struct heif_error err = {heif_error_Encoding_error,
                                 heif_suberror_Unspecified, "overflow"};
        return err;
    }
    w->buf.insert(w->buf.end(), (const uint8_t*)data, (const uint8_t*)data + size);
    struct heif_error ok = {heif_error_Ok, heif_suberror_Unspecified, nullptr};
    return ok;
}

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
    if (width <= 0 || height <= 0 ||
        (unsigned long long)width * (unsigned long long)height > MAX_HEIF_PIXELS) {
        heif_image_handle_release(handle);
        heif_context_free(ctx);
        return 0;
    }

    // decode → encode → serialize → re-parse → decode (roundtrip surface)
    heif_image* img = nullptr;
    err = heif_decode_image(handle, &img, heif_colorspace_undefined,
                            heif_chroma_undefined, nullptr);
    heif_image_handle_release(handle);
    heif_context_free(ctx);
    if (err.code != heif_error_Ok || !img) return 0;

    if (!heif_have_encoder_for_format(heif_compression_HEVC)) {
        heif_image_release(img);
        return 0;
    }

    heif_context* ctx2 = heif_context_alloc();
    heif_encoder* enc = nullptr;
    err = heif_context_get_encoder_for_format(ctx2, heif_compression_HEVC, &enc);
    if (err.code == heif_error_Ok && enc) {
        (void)heif_encoder_set_lossy_quality(enc, 50);
        heif_image_handle* out_handle = nullptr;
        err = heif_context_encode_image(ctx2, img, enc, nullptr, &out_handle);
        heif_encoder_release(enc);
        if (err.code == heif_error_Ok && out_handle) {
            heif_image_handle_release(out_handle);
            VecWriter vw;
            heif_writer writer;
            writer.writer_api_version = 1;
            writer.write = vec_write;
            err = heif_context_write(ctx2, &writer, &vw);
            if (err.code == heif_error_Ok && !vw.buf.empty()) {
                heif_context* ctx3 = heif_context_alloc();
                if (ctx3) {
                    heif_context_set_maximum_image_size_limit(ctx3, 2048);
                    err = heif_context_read_from_memory(ctx3, vw.buf.data(), vw.buf.size(), nullptr);
                    if (err.code == heif_error_Ok) {
                        heif_image_handle* h2 = nullptr;
                        if (heif_context_get_primary_image_handle(ctx3, &h2).code == heif_error_Ok && h2) {
                            heif_image* img2 = nullptr;
                            if (heif_decode_image(h2, &img2, heif_colorspace_undefined,
                                                  heif_chroma_undefined, nullptr).code == heif_error_Ok && img2) {
                                heif_image_release(img2);
                            }
                            heif_image_handle_release(h2);
                        }
                    }
                    heif_context_free(ctx3);
                }
            }
        }
    }

    heif_image_release(img);
    heif_context_free(ctx2);
    return 0;
}
