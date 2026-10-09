#include "AetherScreensCatalog.h"
#include <CoreServices/CoreServices.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/param.h>

static uint64_t get(const uint8_t *bytes, unsigned size) {
    uint64_t result = 0;
    for (unsigned i = 0; i < size; ++i) result = (result << 8) | bytes[i];
    return result;
}
static void swap_finder(uint8_t *bytes) {
    const unsigned widths[14] = {4, 4, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 2, 4};
    unsigned offset = 0;
    for (unsigned index = 0; index < 14; ++index) {
        unsigned width = widths[index];
        for (unsigned i = 0; i < width / 2; ++i) {
            uint8_t byte = bytes[offset + i];
            bytes[offset + i] = bytes[offset + width - i - 1];
            bytes[offset + width - i - 1] = byte;
        }
        offset += width;
    }
}

static void put(uint8_t *out, uint64_t value, unsigned size) {
    for (unsigned i = 0; i < size; ++i) out[size - i - 1] = (uint8_t)(value >> (8 * i));
}
static void date(uint8_t *out, UTCDateTime value) {
    put(out, value.highSeconds, 2); put(out + 2, value.lowSeconds, 4); put(out + 6, value.fraction, 2);
}
int32_t ae_collect_catalog(const char *path, uint16_t level, uint8_t output[104]) {
    if (!path || !output) return paramErr;
    FSRef reference;
    OSStatus status = FSPathMakeRefWithOptions((const UInt8 *)path, kFSPathMakeRefDoNotFollowLeafSymlink, &reference, NULL);
    if (status) return status;
    FSCatalogInfo info;
    memset(&info, 0, sizeof(info));
    status = FSGetCatalogInfo(&reference, kFSCatInfoGettableInfo, &info, NULL, NULL, NULL);
    if (status) return status;
    memset(output, 0, 104);
    const FSPermissionInfo *permissions = (const FSPermissionInfo *)&info.permissions;
    output[0] = (info.nodeFlags & kFSNodeIsDirectoryMask) ? 2 : 1;
    output[1] = permissions->userAccess;
    memcpy(output + 2, info.finderInfo, 16); memcpy(output + 18, info.extFinderInfo, 16);
    /* Native SendNewItemMessage converts Finder fields in mixed widths. */
    swap_finder(output + 2);
    if (!(info.nodeFlags & kFSNodeIsDirectoryMask)) {
        put(output + 34, info.rsrcLogicalSize, 8); put(output + 42, info.dataLogicalSize, 8);
    }
    date(output + 50, info.createDate); date(output + 58, info.contentModDate);
    date(output + 66, info.attributeModDate); date(output + 74, info.accessDate); date(output + 82, info.backupDate);
    put(output + 90, info.nodeFlags, 2); put(output + 92, level, 2);
    put(output + 94, permissions->mode, 2); put(output + 96, info.textEncodingHint, 4);
    return noErr;
}

static UTCDateTime read_date(const uint8_t *bytes) {
    UTCDateTime result;
    result.highSeconds = (UInt16)get(bytes, 2);
    result.lowSeconds = (UInt32)get(bytes + 2, 4);
    result.fraction = (UInt16)get(bytes + 6, 2);
    return result;
}
int32_t ae_restore_catalog_metadata(int descriptor, const uint8_t header[104]) {
    if (descriptor < 0 || !header) return paramErr;
    char path[PATH_MAX];
    struct stat source, observed;
    if (fstat(descriptor, &source) || fcntl(descriptor, F_GETPATH, path) || lstat(path, &observed)) return fnfErr;
    if (source.st_dev != observed.st_dev || source.st_ino != observed.st_ino ||
        (!S_ISREG(source.st_mode) && !S_ISDIR(source.st_mode)) ||
        (S_ISDIR(source.st_mode) != ((get(header + 90, 2) & kFSNodeIsDirectoryMask) != 0))) return paramErr;
    FSRef reference;
    OSStatus status = FSPathMakeRefWithOptions((const UInt8 *)path, kFSPathMakeRefDoNotFollowLeafSymlink, &reference, NULL);
    if (status) return status;
    FSCatalogInfo info;
    memset(&info, 0, sizeof(info));
    uint8_t finder[32];
    memcpy(finder, header + 2, 32); swap_finder(finder);
    memcpy(info.finderInfo, finder, 16); memcpy(info.extFinderInfo, finder + 16, 16);
    info.createDate = read_date(header + 50); info.contentModDate = read_date(header + 58);
    info.attributeModDate = read_date(header + 66); info.backupDate = read_date(header + 82);
    info.textEncodingHint = (TextEncoding)get(header + 96, 4);
    /* Native 0x1be3 mask, with lock/node flags deferred to the owner. */
    return FSSetCatalogInfo(&reference, 0x1be1, &info);
}
