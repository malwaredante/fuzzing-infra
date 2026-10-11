// (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <unistd.h>
#include <fcntl.h>
#include <vector>
#include "heif.h"
#include "heif_sequences.h"

#define MAX_HEIF_SIZE (128 * 1024)
#define MAX_HEIF_PIXELS (16ULL * 1024 * 1024)
#define MAX_TRACKS 8
#define MAX_SAMPLES 6
#define MAX_TRACK_ID_COUNT 4096

class CrashInput {
    char path_[128];
public:
    CrashInput(const uint8_t* data, size_t size) {
        snprintf(path_, sizeof(path_), "/data/local/tmp2/last_crash_input_heif_seq_%d.bin", (int)getpid());
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
    if (size < 16 || size > MAX_HEIF_SIZE) return 0;

    CrashInput ci(data, size);

    heif_context* ctx = heif_context_alloc();
    if (!ctx) return 0;

    heif_context_set_maximum_image_size_limit(ctx, 2048);

    heif_error err = heif_context_read_from_memory(ctx, data, size, nullptr);
    if (err.code != heif_error_Ok) {
        heif_context_free(ctx);
        return 0;
    }

    if (!heif_context_has_sequence(ctx)) {
        heif_context_free(ctx);
        return 0;
    }

    (void)heif_context_get_sequence_timescale(ctx);
    (void)heif_context_get_sequence_duration(ctx);

    int real_ntracks = heif_context_number_of_sequence_tracks(ctx);
    if (real_ntracks <= 0 || real_ntracks > MAX_TRACK_ID_COUNT) {
        heif_context_free(ctx);
        return 0;
    }

    std::vector<uint32_t> ids((size_t)real_ntracks);
    heif_context_get_track_ids(ctx, ids.data());

    int ntracks = real_ntracks > MAX_TRACKS ? MAX_TRACKS : real_ntracks;
    for (int i = 0; i < ntracks; i++) {
        heif_track* track = heif_context_get_track(ctx, ids[i]);
        if (!track) continue;

        (void)heif_track_get_id(track);
        (void)heif_track_get_track_handler_type(track);
        (void)heif_track_get_timescale(track);
        (void)heif_track_get_number_of_repetitions(track);
        (void)heif_track_has_alpha_channel(track);
        (void)heif_track_get_auxiliary_info_type(track);
        (void)heif_track_get_auxiliary_info_type_urn(track);
        (void)heif_track_get_sample_entry_type_of_first_cluster(track);

        uint16_t w = 0, h = 0;
        (void)heif_track_get_image_resolution(track, &w, &h);

        const char* uri = nullptr;
        if (heif_track_get_urim_sample_entry_uri_of_first_cluster(track, &uri).code == heif_error_Ok && uri) {
            heif_string_release(uri);
        }

        if ((unsigned long long)w * (unsigned long long)h <= MAX_HEIF_PIXELS) {
            for (int s = 0; s < MAX_SAMPLES; s++) {
                heif_image* img = nullptr;
                heif_error derr = heif_track_decode_next_image(track, &img,
                    heif_colorspace_undefined, heif_chroma_undefined, nullptr);
                if (derr.code != heif_error_Ok || !img) break;
                (void)heif_image_get_duration(img);
                heif_image_release(img);
            }
        }

        for (int s = 0; s < MAX_SAMPLES; s++) {
            heif_raw_sequence_sample* smp = nullptr;
            heif_error serr = heif_track_get_next_raw_sequence_sample(track, &smp);
            if (serr.code != heif_error_Ok || !smp) break;
            size_t ssz = 0;
            (void)heif_raw_sequence_sample_get_data(smp, &ssz);
            (void)heif_raw_sequence_sample_get_data_size(smp);
            (void)heif_raw_sequence_sample_get_duration(smp);
            heif_raw_sequence_sample_release(smp);
        }

        heif_track_release(track);
    }

    int dbgfd = open("/dev/null", O_WRONLY);
    if (dbgfd >= 0) {
        heif_context_debug_dump_boxes_to_file(ctx, dbgfd);
        close(dbgfd);
    }

    heif_context_free(ctx);
    return 0;
}
