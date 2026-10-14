#ifndef CSTBIMAGE_H
#define CSTBIMAGE_H

/// Decodes a PNG, JPEG, BMP or GIF (first frame) held in memory into straight
/// RGBA bytes, four per pixel, rows top to bottom. Returns NULL when the bytes are
/// not an image it understands. Free the result with goose_image_free.
unsigned char *goose_image_decode_rgba(const unsigned char *bytes, int length, int *width, int *height);

void goose_image_free(unsigned char *pixels);

#endif
