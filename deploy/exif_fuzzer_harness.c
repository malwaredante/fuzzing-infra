/* (c) Vladimir Garenitsa (MalwareDante), 2026. Original work. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <libexif/exif-data.h>
#include <libexif/exif-entry.h>
#include <libexif/exif-content.h>
#include <libexif/exif-tag.h>
#include <libexif/exif-format.h>
#include <libexif/exif-loader.h>

#define MAX_EXIF_SIZE (512 * 1024)

static void entry_cb(ExifEntry* e, void* user) {
    char buf[1024];
    (void)user;
    /* Value formatting is the historically buggy path. */
    exif_entry_get_value(e, buf, sizeof(buf));
    (void)exif_tag_get_name(e->tag);
    (void)exif_format_get_name(e->format);
}

static void content_cb(ExifContent* c, void* user) {
    exif_content_foreach_entry(c, entry_cb, user);
}

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < 4 || size > MAX_EXIF_SIZE) return 0;

    char path[128];
    snprintf(path, sizeof(path), "/data/local/tmp2/last_crash_input_exif_%d.bin", (int)getpid());
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd >= 0) { (void)write(fd, data, size); (void)ftruncate(fd, size); close(fd); }

    /* Path 1: raw EXIF blob (what exif_loader produces). */
    ExifData* ed = exif_data_new_from_data(data, (unsigned)size);
    if (ed) {
        exif_data_foreach_content(ed, content_cb, NULL);
        unsigned char* dump = NULL;
        unsigned int dsz = 0;
        exif_data_save_data(ed, &dump, &dsz);
        free(dump);
        exif_data_unref(ed);
    }

    /* Path 2: full file loading (JPEG APP1 walk etc). */
    if (fd >= 0 || 1) {
        ExifLoader* l = exif_loader_new();
        exif_loader_write(l, (unsigned char*)data, (unsigned)size);
        ExifData* ed2 = exif_loader_get_data(l);
        if (ed2) {
            exif_data_foreach_content(ed2, content_cb, NULL);
            exif_data_unref(ed2);
        }
        exif_loader_unref(l);
    }

    unlink(path);
    return 0;
}
