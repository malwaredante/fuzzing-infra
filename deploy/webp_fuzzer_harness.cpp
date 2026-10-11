// (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
/* libFuzzer harness for libwebp: decode, demux, mux and animation paths */
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <fcntl.h>
#include <unistd.h>
#include "webp/decode.h"
#include "webp/mux_types.h"
#include "webp/demux.h"
#include "webp/encode.h"
#include "webp/mux.h"

#define MAX_WEBP_DIM 2048

/* Write the current input to a per-child crash file. If the child crashes,
   the destructor does not run and the file persists for triage. */
class CrashInput {
    char path_[64];
public:
    CrashInput(const uint8_t* data, size_t size) {
        snprintf(path_, sizeof(path_), "/data/local/tmp2/last_crash_input_webp_%d.bin", (int)getpid());
        int fd = open(path_, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            (void)write(fd, data, size);
            (void)ftruncate(fd, size);
            close(fd);
        }
    }
    ~CrashInput() { unlink(path_); }
};

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    int w = 0, h = 0;

    if (size == 0 || size > (1u << 22)) return 0;  /* ignore empty/huge inputs */

    CrashInput ci(data, size);

    int info_ok = WebPGetInfo(data, size, &w, &h);
    if (!info_ok) return 0;
    if (w > MAX_WEBP_DIM || h > MAX_WEBP_DIM) return 0;
    if ((size_t)w * (size_t)h > (size_t)MAX_WEBP_DIM * MAX_WEBP_DIM) return 0;

    uint8_t *out = WebPDecodeRGBA(data, size, &w, &h);
    if (out) WebPFree(out);

    // Exercise incremental decoder.
    WebPIDecoder* idec = WebPINewDecoder(NULL);
    if (idec) {
        (void)WebPIAppend(idec, data, size);
        WebPIDelete(idec);
    }

    WebPData webp_data = { data, size };
    WebPDemuxer* dmux = WebPDemux(&webp_data);
    if (dmux) {
        (void)WebPDemuxGetI(dmux, WEBP_FF_FORMAT_FLAGS);
        WebPDemuxDelete(dmux);
    }

    WebPMux* mux = WebPMuxCreate(&webp_data, 0);
    if (mux) {
        WebPData chunk;
        (void)WebPMuxGetChunk(mux, "ICCP", &chunk);
        (void)WebPMuxGetChunk(mux, "XMP ", &chunk);
        (void)WebPMuxGetChunk(mux, "EXIF", &chunk);
        WebPMuxDelete(mux);
    }

    WebPAnimDecoderOptions dec_opts;
    if (WebPAnimDecoderOptionsInit(&dec_opts)) {
        WebPAnimDecoder* dec = WebPAnimDecoderNew(&webp_data, &dec_opts);
        if (dec) {
            WebPAnimInfo anim_info;
            (void)WebPAnimDecoderGetInfo(dec, &anim_info);
            uint8_t* frame = NULL;
            int timestamp = 0;
            if (WebPAnimDecoderHasMoreFrames(dec)) {
                (void)WebPAnimDecoderGetNext(dec, &frame, &timestamp);
            }
            WebPAnimDecoderDelete(dec);
        }
    }

    // Encode a synthetic image from the input, then re-mux it.
    if (size >= 6) {
        int ew = 1 + ((int)data[0] | ((int)data[1] << 8)) % 64;
        int eh = 1 + ((int)data[2] | ((int)data[3] << 8)) % 64;
        if ((size_t)ew * (size_t)eh > 4096) eh = 4096 / ew;
        if (eh < 1) eh = 1;
        size_t needed = 6 + (size_t)ew * (size_t)eh * 3;
        if (needed <= size) {
            float q = (float)(data[4] % 101);
            uint8_t* enc = NULL;
            size_t enc_size = WebPEncodeRGB(data + 6, ew, eh, ew * 3, q, &enc);
            if (enc && enc_size > 0) {
                WebPData enc_data = { enc, enc_size };
                WebPMux* emux = WebPMuxCreate(&enc_data, 0);
                if (emux) {
                    WebPData assembled;
                    if (WebPMuxAssemble(emux, &assembled) == WEBP_MUX_OK) {
                        WebPDataClear(&assembled);
                    }
                    WebPMuxDelete(emux);
                }
                WebPFree(enc);
            }
        }
    }
    return 0;
}
