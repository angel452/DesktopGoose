// stb_image (public domain, nothings/stb v2.30) does the decoding. Only the
// formats the goose uses are compiled in, and file I/O stays on the Swift side so
// paths never go through the C runtime's narrow-character fopen.
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_BMP
#define STBI_ONLY_GIF
#include "stb_image.h"

#include "CStbImage.h"

unsigned char *goose_image_decode_rgba(const unsigned char *bytes, int length, int *width, int *height) {
    int channels = 0;
    return stbi_load_from_memory(bytes, length, width, height, &channels, 4);
}

void goose_image_free(unsigned char *pixels) {
    stbi_image_free(pixels);
}
