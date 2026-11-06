// app/Nusky/Nusky-Bridging-Header.h
// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

#ifndef Nusky_Bridging_Header_h
#define Nusky_Bridging_Header_h

// Medida de texto fornecida pela casca (CoreText).
typedef float (*nusky_measure_fn)(const char *text, float font_size, int bold);

// Renderização e diagnóstico.
char *nusky_render(const char *html, float viewport_width, nusky_measure_fn measure);
char *nusky_diagnose(const char *html, float viewport_width, nusky_measure_fn measure);
void nusky_free_string(char *s);

// Busca de sites pelo nome.
// nusky_busca_carregar: json NULL carrega a lista embutida. Retorna 0 se deu certo, 1 se a lista estiver errada.
int nusky_busca_carregar(const char *json);
// Versão da lista em uso (0 se não houver).
int nusky_busca_versao(void);
// Data da lista em uso, aaaa-mm-dd (vazia se não houver). Liberar com nusky_free_string.
char *nusky_busca_data(void);
// Texto com uma linha por endereço: endereco<TAB>contagem.
void nusky_busca_definir_usos(const char *texto);
void nusky_busca_registrar_uso(const char *endereco);
// Linhas: endereco<TAB>nome<TAB>título do atalho (vazio se for o site). Liberar com nusky_free_string.
char *nusky_busca(const char *consulta);
// Linha: nome<TAB>endereço, ou vazio. Liberar com nusky_free_string.
char *nusky_busca_sugestao(const char *consulta);

#endif