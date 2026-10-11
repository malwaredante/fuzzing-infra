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
#define MAX_HEIF_PIXELS (16ULL * 1024 * 1024)
#define MAX_ITEMS 16
#define MAX_METADATA_SIZE (1024 * 1024)
#define MAX_DEPTH 2

class CrashInput {
    char path_[128];
public:
    CrashInput(const uint8_t* data, size_t size) {
        snprintf(path_, sizeof(path_), "/data/local/tmp2/last_crash_input_heif_meta_%d.bin", (int)getpid());
        int fd = open(path_, O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd >= 0) {
            (void)write(fd, data, size);
            (void)ftruncate(fd, size);
            close(fd);
        }
    }
    ~CrashInput() { unlink(path_); }
};

static void decode_if_small(const heif_image_handle* handle) {
    int w = heif_image_handle_get_width(handle);
    int h = heif_image_handle_get_height(handle);
    if (w > 0 && h > 0 &&
        (unsigned long long)w * (unsigned long long)h <= MAX_HEIF_PIXELS) {
        heif_image* img = nullptr;
        heif_error err = heif_decode_image(handle, &img, heif_colorspace_undefined,
                                         heif_chroma_undefined, nullptr);
        if (err.code == heif_error_Ok && img) {
            heif_image_release(img);
        }
    }
}

static void inspect_handle(const heif_image_handle* handle, int depth) {
    if (!handle || depth > MAX_DEPTH) return;

    (void)heif_image_handle_is_primary_image(handle);
    (void)heif_image_handle_get_item_id(handle);
    (void)heif_image_handle_get_width(handle);
    (void)heif_image_handle_get_height(handle);
    (void)heif_image_handle_get_ispe_width(handle);
    (void)heif_image_handle_get_ispe_height(handle);
    (void)heif_image_handle_has_alpha_channel(handle);
    (void)heif_image_handle_is_premultiplied_alpha(handle);
    (void)heif_image_handle_get_luma_bits_per_pixel(handle);
    (void)heif_image_handle_get_chroma_bits_per_pixel(handle);

    heif_colorspace cs; heif_chroma ch;
    (void)heif_image_handle_get_preferred_decoding_colorspace(handle, &cs, &ch);

    uint32_t ah, av;
    (void)heif_image_handle_get_pixel_aspect_ratio(handle, &ah, &av);

    // tiling / grid path
    heif_image_tiling tiling;
    memset(&tiling, 0, sizeof(tiling));
    if (heif_image_handle_get_image_tiling(handle, 1, &tiling).code == heif_error_Ok) {
        heif_item_id tid = 0;
        (void)heif_image_handle_get_grid_image_tile_id(handle, 1, 0, 0, &tid);
        if (tiling.num_columns > 0 && tiling.num_rows > 0 &&
            tiling.num_columns <= 64 && tiling.num_rows <= 64 &&
            (unsigned long long)tiling.tile_width * tiling.tile_height <= MAX_HEIF_PIXELS) {
            heif_image* tile_img = nullptr;
            heif_error terr = heif_image_handle_decode_image_tile(
                handle, &tile_img, heif_colorspace_undefined,
                heif_chroma_undefined, nullptr, 0, 0);
            if (terr.code == heif_error_Ok && tile_img) {
                heif_image_release(tile_img);
            }
        }
    }

    // thumbnails
    int nthumb = heif_image_handle_get_number_of_thumbnails(handle);
    if (nthumb > 0 && nthumb <= MAX_ITEMS) {
        std::vector<heif_item_id> tids(nthumb);
        heif_image_handle_get_list_of_thumbnail_IDs(handle, tids.data(), nthumb);
        for (int i = 0; i < nthumb; i++) {
            heif_image_handle* th = nullptr;
            if (heif_image_handle_get_thumbnail(handle, tids[i], &th).code == heif_error_Ok && th) {
                decode_if_small(th);
                heif_image_handle_release(th);
            }
        }
    }

    // depth images
    if (heif_image_handle_has_depth_image(handle)) {
        int nd = heif_image_handle_get_number_of_depth_images(handle);
        if (nd > 0 && nd <= MAX_ITEMS) {
            std::vector<heif_item_id> dids(nd);
            heif_image_handle_get_list_of_depth_image_IDs(handle, dids.data(), nd);
            const heif_depth_representation_info* dinfo = nullptr;
            (void)heif_image_handle_get_depth_image_representation_info(handle, dids[0], &dinfo);
            if (dinfo) heif_depth_representation_info_free(dinfo);
            for (int i = 0; i < nd; i++) {
                heif_image_handle* dh = nullptr;
                if (heif_image_handle_get_depth_image_handle(handle, dids[i], &dh).code == heif_error_Ok && dh) {
                    decode_if_small(dh);
                    heif_image_handle_release(dh);
                }
            }
        }
    }

    // auxiliary images (alpha aux, hdr gainmaps, ...)
    int naux = heif_image_handle_get_number_of_auxiliary_images(handle, 0);
    if (naux > 0 && naux <= MAX_ITEMS) {
        const char* auxtype = nullptr;
        if (heif_image_handle_get_auxiliary_type(handle, &auxtype).code == heif_error_Ok) {
            heif_image_handle_release_auxiliary_type(handle, &auxtype);
        }
        std::vector<heif_item_id> aids(naux);
        heif_image_handle_get_list_of_auxiliary_image_IDs(handle, 0, aids.data(), naux);
        for (int i = 0; i < naux; i++) {
            heif_image_handle* ah = nullptr;
            if (heif_image_handle_get_auxiliary_image_handle(handle, aids[i], &ah).code == heif_error_Ok && ah) {
                heif_image_handle_release(ah);
            }
        }
    }

    // metadata blocks (Exif / XMP / mime / uri )
    int nmeta = heif_image_handle_get_number_of_metadata_blocks(handle, nullptr);
    if (nmeta > 0 && nmeta <= MAX_ITEMS) {
        std::vector<heif_item_id> mids(nmeta);
        heif_image_handle_get_list_of_metadata_block_IDs(handle, nullptr, mids.data(), nmeta);
        for (int i = 0; i < nmeta; i++) {
            (void)heif_image_handle_get_metadata_type(handle, mids[i]);
            (void)heif_image_handle_get_metadata_content_type(handle, mids[i]);
            (void)heif_image_handle_get_metadata_item_uri_type(handle, mids[i]);
            size_t msize = heif_image_handle_get_metadata_size(handle, mids[i]);
            if (msize > 0 && msize <= MAX_METADATA_SIZE) {
                void* buf = malloc(msize);
                if (buf) {
                    (void)heif_image_handle_get_metadata(handle, mids[i], buf);
                    free(buf);
                }
            }
        }
    }
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

    int ntop = heif_context_get_number_of_top_level_images(ctx);
    if (ntop <= 0 || ntop > MAX_ITEMS) {
        heif_context_free(ctx);
        return 0;
    }

    std::vector<heif_item_id> ids(ntop);
    heif_context_get_list_of_top_level_image_IDs(ctx, ids.data(), ntop);
    for (int i = 0; i < ntop; i++) {
        (void)heif_context_is_top_level_image_ID(ctx, ids[i]);
        heif_image_handle* handle = nullptr;
        if (heif_context_get_image_handle(ctx, ids[i], &handle).code == heif_error_Ok && handle) {
            inspect_handle(handle, 0);
            heif_image_handle_release(handle);
        }
    }

    int dbgfd = open("/dev/null", O_WRONLY);
    if (dbgfd >= 0) {
        heif_context_debug_dump_boxes_to_file(ctx, dbgfd);
        close(dbgfd);
    }

    heif_context_free(ctx);
    return 0;
}
