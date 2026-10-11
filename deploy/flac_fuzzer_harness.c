/* (c) Vladimir Garenitsa (MalwareDante), 2026. Original work. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include "FLAC/stream_decoder.h"

#define MAX_FLAC_SIZE (256 * 1024)

struct memsrc {
    const uint8_t* data;
    size_t size;
    size_t pos;
};

static FLAC__StreamDecoderReadStatus rcb(const FLAC__StreamDecoder* d,
                                         FLAC__byte buffer[], size_t* bytes,
                                         void* client_data) {
    struct memsrc* m = client_data;
    (void)d;
    if (*bytes == 0) return FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
    if (m->pos >= m->size) {
        *bytes = 0;
        return FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM;
    }
    size_t n = m->size - m->pos;
    if (n > *bytes) n = *bytes;
    memcpy(buffer, m->data + m->pos, n);
    m->pos += n;
    *bytes = n;
    return FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
}

static FLAC__StreamDecoderSeekStatus scb(const FLAC__StreamDecoder* d,
                                         FLAC__uint64 offset, void* client_data) {
    struct memsrc* m = client_data;
    (void)d;
    if (offset > m->size) return FLAC__STREAM_DECODER_SEEK_STATUS_ERROR;
    m->pos = (size_t)offset;
    return FLAC__STREAM_DECODER_SEEK_STATUS_OK;
}

static FLAC__StreamDecoderTellStatus tcb(const FLAC__StreamDecoder* d,
                                         FLAC__uint64* offset, void* client_data) {
    struct memsrc* m = client_data;
    (void)d;
    *offset = m->pos;
    return FLAC__STREAM_DECODER_TELL_STATUS_OK;
}

static FLAC__StreamDecoderLengthStatus lcb(const FLAC__StreamDecoder* d,
                                           FLAC__uint64* len, void* client_data) {
    struct memsrc* m = client_data;
    (void)d;
    *len = m->size;
    return FLAC__STREAM_DECODER_LENGTH_STATUS_OK;
}

static FLAC__bool ecb(const FLAC__StreamDecoder* d, void* client_data) {
    struct memsrc* m = client_data;
    (void)d;
    return m->pos < m->size;
}

static FLAC__StreamDecoderWriteStatus wcb(const FLAC__StreamDecoder* d,
                                          const FLAC__Frame* frame,
                                          const FLAC__int32* const buffer[],
                                          void* client_data) {
    (void)d; (void)frame; (void)buffer; (void)client_data;
    return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void mcb(const FLAC__StreamDecoder* d, const FLAC__StreamMetadata* m,
                void* client_data) {
    (void)d; (void)m; (void)client_data;
}

static void ecb2(const FLAC__StreamDecoder* d, FLAC__StreamDecoderErrorStatus s,
                 void* client_data) {
    (void)d; (void)s; (void)client_data;
}

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 4 || size > MAX_FLAC_SIZE) return 0;

    char path[128];
    snprintf(path, sizeof(path), "/data/local/tmp2/last_crash_input_flac_%d.bin", (int)getpid());
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd >= 0) { (void)write(fd, data, size); (void)ftruncate(fd, size); close(fd); }

    struct memsrc m = {data, size, 0};
    FLAC__StreamDecoder* dec = FLAC__stream_decoder_new();
    if (!dec) { unlink(path); return 0; }

    FLAC__stream_decoder_set_metadata_respond_all(dec);
    FLAC__StreamDecoderInitStatus st = FLAC__stream_decoder_init_stream(
        dec, rcb, scb, tcb, lcb, ecb, wcb, mcb, ecb2, &m);
    if (st == FLAC__STREAM_DECODER_INIT_STATUS_OK) {
        FLAC__stream_decoder_process_until_end_of_stream(dec);
    }
    FLAC__stream_decoder_delete(dec);
    unlink(path);
    return 0;
}
