// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

#ifndef Nusky_Bridging_Header_h
#define Nusky_Bridging_Header_h

// Medida de texto fornecida pela casca (CoreText).
typedef float (*nusky_measure_fn)(const char *text, float font_size, int bold);

char *nusky_render(const char *html, float viewport_width, nusky_measure_fn measure);
char *nusky_diagnose(const char *html, float viewport_width, nusky_measure_fn measure);
void nusky_free_string(char *s);

#endif