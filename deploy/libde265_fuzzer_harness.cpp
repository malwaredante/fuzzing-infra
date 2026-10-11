// (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <unistd.h>
#include <fcntl.h>
#include "libde265/de265.h"

#define MAX_NAL_SIZE (64 * 1024)
#define MAX_DECODE_LOOPS 32

class CrashInput {
    char path_[128];
public:
    CrashInput(const uint8_t* data, size_t size) {
        snprintf(path_, sizeof(path_), "/data/local/tmp2/last_crash_input_de265_%d.bin", (int)getpid());
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
    if (size == 0 || size > MAX_NAL_SIZE) return 0;

    CrashInput ci(data, size);

    de265_decoder_context* ctx = de265_new_decoder();
    if (!ctx) return 0;

    de265_error err = de265_push_data(ctx, data, (int)size, 0, nullptr);
    if (err == DE265_OK) {
        (void)de265_flush_data(ctx);
        int more = 0;
        int loops = 0;
        do {
            err = de265_decode(ctx, &more);
        } while (more && ++loops < MAX_DECODE_LOOPS);
    }

    de265_free_decoder(ctx);
    return 0;
}
