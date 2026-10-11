/* (c) Vladimir Garenitsa (MalwareDante), 2026. Original work. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include "eas.h"

#define MAX_SONI_SIZE (1024 * 1024)

struct memsrc {
    const uint8_t* data;
    int size;
};

static int mem_readAt(void* handle, void* buf, int offset, int size) {
    struct memsrc* m = handle;
    if (offset < 0 || offset >= m->size) return 0;
    int n = m->size - offset;
    if (n > size) n = size;
    memcpy(buf, m->data + offset, (size_t)n);
    return n;
}

static int mem_size(void* handle) {
    return ((struct memsrc*)handle)->size;
}

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 8 || size > MAX_SONI_SIZE) return 0;

    char path[128];
    snprintf(path, sizeof(path), "/data/local/tmp2/last_crash_input_soni_%d.bin", (int)getpid());
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd >= 0) { (void)write(fd, data, size); (void)ftruncate(fd, size); close(fd); }

    EAS_DATA_HANDLE easData = NULL;
    if (EAS_Init(&easData) != EAS_SUCCESS) { unlink(path); return 0; }

    struct memsrc m = {data, (int)size};
    EAS_FILE file = {&m, mem_readAt, mem_size};

    EAS_HANDLE handle = NULL;
    if (EAS_OpenFile(easData, &file, &handle) == EAS_SUCCESS) {
        EAS_PCM pcmBuf[512];
        EAS_I32 generated = 0;
        EAS_STATE state = EAS_STATE_READY;
        for (int i = 0; i < 2048; i++) {
            if (EAS_Render(easData, pcmBuf, 128, &generated) != EAS_SUCCESS)
                break;
            if (generated <= 0) break;
            if (EAS_State(easData, handle, &state) != EAS_SUCCESS) break;
            if (state == EAS_STATE_STOPPING || state == EAS_STATE_STOPPED ||
                state == EAS_STATE_ERROR || state == EAS_STATE_PAUSED ||
                state == EAS_STATE_EMPTY)
                break;
        }
        EAS_CloseFile(easData, handle);
    }

    EAS_Shutdown(easData);
    unlink(path);
    return 0;
}
