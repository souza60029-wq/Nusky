#ifndef Nusky_Bridging_Header_h
#define Nusky_Bridging_Header_h

typedef float (*nusky_measure_fn)(const char *text, float font_size, int bold);

char *nusky_render(const char *html, float viewport_width, nusky_measure_fn measure);
void nusky_free_string(char *s);

#endif