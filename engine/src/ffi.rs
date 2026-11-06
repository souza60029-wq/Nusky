// engine/src/ffi.rs
// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Interface C do motor, chamada pela casca Swift.
//!
//! Renderização:
//! `nusky_render` recebe HTML e, opcionalmente, uma função de medição fornecida pela casca.
//! Formato de saída: uma linha por comando de texto, com campos separados por tab:
//! `x<TAB>y<TAB>tamanho<TAB>negrito(0/1)<TAB>link<TAB>cor<TAB>texto`.
//! O campo `link` fica vazio quando o texto não é link.
//! O campo `cor` é `r,g,b` (0 a 255), ou vazio quando a página não definiu cor.
//!
//! Antes do layout, o HTML passa por `preparo::marcar_com_javascript`, que troca
//! "client-nojs" por "client-js" na tag <html>.
//!
//! `nusky_diagnose` aceita 