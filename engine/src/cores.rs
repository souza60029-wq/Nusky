// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Cores do CSS além de `#hex`, `rgb()` e `hsl()`.
//!
//! - os 148 nomes de cor do CSS (`rebeccapurple`, `gold`, `lightgray`...);
//! - `hwb()`, `lab()`, `lch()`, `oklab()`, `oklch()` e `color(srgb|display-p3|xyz ...)`;
//! - `color-mix(in <espaço>, cor %, cor %)`;
//! - `light-dark(clara, escura)`, que segue o tema do aparelho.
//!
//! Sites feitos com Tailwind 4 (arena.ai e muitos outros) escrevem quase todas as cores em `oklch()` e
//! `color-mix()`. Antes disso, essas cores eram descartadas e o texto caía na cor padrão dos links.
//!
//! As contas seguem o CSS Color 4. Cor fora da gama do sRGB perde saturação até caber (como o Safari faz)
//! em vez de ser cortada canal por canal, o que mudaria o tom.

use std::f64::consts::PI;

/// Vermelho, verde, azul (0 a 255) e transparência (0 a 1).
pub type Rgba = (u8, u8, u8, f32);

/// Leitor de cor geral, para as cores que vêm dentro de `color-mix()` e `light-dark()`.
pub type Leitor = fn(&str) -> Option<Rgba>;

/// Cor pelo nome em minúsculas. Não inclui `transparent` nem `currentcolor`.
pub fn por_nome(nome: &str) -> Option<(u8, u8, u8)> {
    let c = match nome {
        "aliceblue" => (240, 248, 255),
        "antiquewhite" => (250, 235, 215),
        "aqua" => (0, 255, 255),
        "aquamarine" => (127, 255, 212),
        "azure" => (240, 255, 255),
        "beige" => (245, 245, 220),
        "bisque" => (255, 228, 196),
        "black" => (0, 0, 0),
        "blanchedalmond" => (255, 235, 205),
        "blue" => (0, 0, 255),
        "blueviolet" => (138, 43, 226),
        "brown" => (165, 42, 42),
        "burlywood" => (222, 184, 135),
        "cadetblue" => (95, 158, 160),
        "chartreuse" => (127, 255, 0),
        "chocolate" => (210, 105, 30),
        "coral" => (255, 127, 80),
        "cornflowerblue" => (100, 149, 237),
        "cornsilk" => (255, 248, 220),
        "crimson" => (220, 20, 60),
        "cyan" => (0, 255, 255),
        "darkblue" => (0, 0, 139),
        "darkcyan" => (0, 139, 139),
        "darkgoldenrod" => (184, 134, 11),
        "darkgray" => (169, 169, 169),
        "darkgreen" => (0, 100, 0),
        "darkgrey" => (169, 169, 169),
        "darkkhaki" => (189, 183, 107),
        "darkmagenta" => (139, 0, 139),
        "darkolivegreen" => (85, 107, 47),
        "darkorange" => (255, 140, 0),
        "darkorchid" => (153, 50, 204),
        "darkred" => (139, 0, 0),
        "darksalmon" => (233, 150, 122),
        "darkseagreen" => (143, 188, 143),
        "darkslateblue" => (72, 61, 139),
        "darkslategray" => (47, 79, 79),
        "darkslategrey" => (47, 79, 79),
        "darkturquoise" => (0, 206, 209),
        "darkviolet" => (148, 0, 211),
        "deeppink" => (255, 20, 147),
        "deepskyblue" => (0, 191, 255),
        "dimgray" => (105, 105, 105),
        "dimgrey" => (105, 105, 105),
        "dodgerblue" => (30, 144, 255),
        "firebrick" => (178, 34, 34),
        "floralwhite" => (255, 250, 240),
        "forestgreen" => (34, 139, 34),
        "fuchsia" => (255, 0, 255),
        "gainsboro" => (220, 220, 220),
        "ghostwhite" => (248, 248, 255),
        "gold" => (255, 215, 0),
        "goldenrod" => (218, 165, 32),
        "gray" => (128, 128, 128),
        "green" => (0, 128, 0),
        "greenyellow" => (173, 255, 47),
        "grey" => (128, 128, 128),
        "honeydew" => (240, 255, 240),
        "hotpink" => (255, 105, 180),
        "indianred" => (205, 92, 92),
        "indigo" => (75, 0, 130),
        "ivory" => (255, 255, 240),
        "khaki" => (240, 230, 140),
        "lavender" => (230, 230, 250),
        "lavenderblush" => (255, 240, 245),
        "lawngreen" => (124, 252, 0),
        "lemonchiffon" => (255, 250, 205),
        "lightblue" => (173, 216, 230),
        "lightcoral" => (240, 128, 128),
        "lightcyan" => (224, 255, 255),
        "lightgoldenrodyellow" => (250, 250, 210),
        "lightgray" => (211, 211, 211),
        "lightgreen" => (144, 238, 144),
        "lightgrey" => (211, 211, 211),
        "lightpink" => (255, 182, 193),
        "lightsalmon" => (255, 160, 122),
        "lightseagreen" => (32, 178, 170),
        "lightskyblue" => (135, 206, 250),
        "lightslategray" => (119, 136, 153),
        "lightslategrey" => (119, 136, 153),
        "lightsteelblue" => (176, 196, 222),
        "lightyellow" => (255, 255, 224),
        "lime" => (0, 255, 0),
        "limegreen" => (50, 205, 50),
        "linen" => (250, 240, 230),
        "magenta" => (255, 0, 255),
        "maroon" => (128, 0, 0),
        "mediumaquamarine" => (102, 205, 170),
        "mediumblue" => (0, 0, 205),
        "mediumorchid" => (186, 85, 211),
        "mediumpurple" => (147, 112, 219),
        "mediumseagreen" => (60, 179, 113),
        "mediumslateblue" => (123, 104, 238),
        "mediumspringgreen" => (0, 250, 154),
        "mediumturquoise" => (72, 209, 204),
        "mediumvioletred" => (199, 21, 133),
        "midnightblue" => (25, 25, 112),
        "mintcream" => (245, 255, 250),
        "mistyrose" => (255, 228, 225),
        "moccasin" => (255, 228, 181),
        "navajowhite" => (255, 222, 173),
        "navy" => (0, 0, 128),
        "oldlace" => (253, 245, 230),
        "olive" => (128, 128, 0),
        "olivedrab" => (107, 142, 35),
        "orange" => (255, 165, 0),
        "orangered" => (255, 69, 0),
        "orchid" => (218, 112, 214),
        "palegoldenrod" => (238, 232, 170),
        "palegreen" => (152, 251, 152),
        "paleturquoise" => (175, 238, 238),
        "palevioletred" => (219, 112, 147),
        "papayawhip" => (255, 239, 213),
        "peachpuff" => (255, 218, 185),
        "peru" => (205, 133, 63),
        "pink" => (255, 192, 203),
        "plum" => (221, 160, 221),
        "powderblue" => (176, 224, 230),
        "purple" => (128, 0, 128),
        "rebeccapurple" => (102, 51, 153),
        "red" => (255, 0, 0),
        "rosybrown" => (188, 143, 143),
        "royalblue" => (65, 105, 225),
        "saddlebrown" => (139, 69, 19),
        "salmon" => (250, 128, 114),
        "sandybrown" => (244, 164, 96),
        "seagreen" => (46, 139, 87),
        "seashell" => (255, 245, 238),
        "sienna" => (160, 82, 45),
        "silver" => (192, 192, 192),
        "skyblue" => (135, 206, 235),
        "slateblue" => (106, 90, 205),
        "slategray" => (112, 128, 144),
        "slategrey" => (112, 128, 144),
        "snow" => (255, 250, 250),
        "springgreen" => (0, 255, 127),
        "steelblue" => (70, 130, 180),
        "tan" => (210, 180, 140),
        "teal" => (0, 128, 128),
        "thistle" => (216, 191, 216),
        "tomato" => (255, 99, 71),
        "turquoise" => (64, 224, 208),
        "violet" => (238, 130, 238),
        "wheat" => (245, 222, 179),
        "white" => (255, 255, 255),
        "whitesmoke" => (245, 245, 245),
        "yellow" => (255, 255, 0),
        "yellowgreen" => (154, 205, 50),
        _ => return None,
    };
    Some(c)
}

/// Lê `nome(...)` para os nomes acima. `v` já vem em minúsculas e sem espaços nas pontas.
pub fn funcao(v: &str, escuro: bool, leitor: Leitor) -> Option<Rgba> {
    let abre = v.find('(')?;
    if !v.ends_with(')') {
        return None;
    }
    let nome = v[..abre].trim();
    let interior = &v[abre + 1..v.len() - 1];
    match nome {
        "hwb" => hwb(interior),
        "lab" => lab(interior, false),
        "lch" => lab(interior, true),
        "oklab" => oklab(interior, false),
        "oklch" => oklab(interior, true),
        "color" => cor_espaco(interior),
        "color-mix" => misturar(interior, leitor),
        "light-dark" => {
            let partes = dividir_virgulas(interior);
            if partes.len() != 2 {
                return None;
            }
            leitor(if escuro { partes[1] } else { partes[0] })
        }
        _ => None,
    }
}

// ---------------------------------------------------------------------------------------------
// Matrizes e curvas (CSS Color 4)
// ---------------------------------------------------------------------------------------------

const D50: [f64; 3] = [0.3457 / 0.3585, 1.0, (1.0 - 0.3457 - 0.3585) / 0.3585];

const D50_PARA_D65: [f64; 9] = [
    0.9554734527042182, -0.023098536874261423, 0.0632593086610217,
    -0.028369706963208136, 1.0099954580058226, 0.021041398966943008,
    0.012314001688319899, -0.020507696433477912, 1.3303659366080753,
];

const D65_PARA_D50: [f64; 9] = [
    1.0479298208405488, 0.022946793341019088, -0.05019222954313557,
    0.029627815688159344, 0.990434484573249, -0.01707382502938514,
    -0.009243058152591178, 0.015055144896577895, 0.7518742899580008,
];

const XYZ_PARA_RGB: [f64; 9] = [
    3.2409699419045226, -1.537383177570094, -0.4986107602930034,
    -0.9692436362808796, 1.8759675015077202, 0.04155505740717559,
    0.05563007969699366, -0.20397695888897652, 1.0569715142428786,
];

const RGB_PARA_XYZ: [f64; 9] = [
    0.4123907992659595, 0.357584339383878, 0.1804807884018343,
    0.21263900587151036, 0.715168678767756, 0.07219231536073371,
    0.01933081871559185, 0.11919477979462598, 0.9505321522496607,
];

const P3_PARA_XYZ: [f64; 9] = [
    0.4865709486482162, 0.26566769316909306, 0.1982172852343625,
    0.2289745640697488, 0.6917385218365064, 0.079286914093745,
    0.0, 0.04511338185890264, 1.043944368900976,
];

fn multiplicar(m: &[f64; 9], v: [f64; 3]) -> [f64; 3] {
    [
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    ]
}

/// sRGB codificado (0 a 1) para linear.
fn para_linear(c: f64) -> f64 {
    if c.abs() <= 0.04045 {
        c / 12.92
    } else {
        c.signum() * ((c.abs() + 0.055) / 1.055).powf(2.4)
    }
}

/// Linear para sRGB codificado.
fn de_linear(c: f64) -> f64 {
    if c.abs() <= 0.0031308 {
        12.92 * c
    } else {
        c.signum() * (1.055 * c.abs().powf(1.0 / 2.4) - 0.055)
    }
}

/// Canal linear para byte, cortando o que passar da gama.
fn byte(linear: f64) -> u8 {
    let g = de_linear(linear.max(0.0).min(1.0));
    (g.max(0.0).min(1.0) * 255.0).round() as u8
}

fn bytes(linear: [f64; 3]) -> (u8, u8, u8) {
    (byte(linear[0]), byte(linear[1]), byte(linear[2]))
}

fn oklab_para_linear(l: f64, a: f64, b: f64) -> [f64; 3] {
    let l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    let m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    let s_ = l - 0.0894841775 * a - 1.2914855480 * b;
    let (l3, m3, s3) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_);
    [
        4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
        -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
        -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3,
    ]
}

fn linear_para_oklab(c: [f64; 3]) -> [f64; 3] {
    let l = (0.4122214708 * c[0] + 0.5363325363 * c[1] + 0.0514459929 * c[2]).cbrt();
    let m = (0.2119034982 * c[0] + 0.6806995451 * c[1] + 0.1073969566 * c[2]).cbrt();
    let s = (0.0883024619 * c[0] + 0.2817188376 * c[1] + 0.6299787005 * c[2]).cbrt();
    [
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    ]
}

fn lab_para_linear(l: f64, a: f64, b: f64) -> [f64; 3] {
    let e = 216.0 / 24389.0;
    let k = 24389.0 / 27.0;
    let fy = (l + 16.0) / 116.0;
    let fx = fy + a / 500.0;
    let fz = fy - b / 200.0;
    let x = if fx * fx * fx > e { fx * fx * fx } else { (116.0 * fx - 16.0) / k };
    let y = if l > 8.0 { fy * fy * fy } else { l / k };
    let z = if fz * fz * fz > e { fz * fz * fz } else { (116.0 * fz - 16.0) / k };
    let xyz50 = [x * D50[0], y * D50[1], z * D50[2]];
    multiplicar(&XYZ_PARA_RGB, multiplicar(&D50_PARA_D65, xyz50))
}

fn linear_para_lab(c: [f64; 3]) -> [f64; 3] {
    let xyz = multiplicar(&D65_PARA_D50, multiplicar(&RGB_PARA_XYZ, c));
    let e = 216.0 / 24389.0;
    let k = 24389.0 / 27.0;
    let f = |t: f64| -> f64 {
        if t > e {
            t.cbrt()
        } else {
            (k * t + 16.0) / 116.0
        }
    };
    let fx = f(xyz[0] / D50[0]);
    let fy = f(xyz[1] / D50[1]);
    let fz = f(xyz[2] / D50[2]);
    [116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)]
}

fn na_gama(c: [f64; 3]) -> bool {
    c.iter().all(|x| *x >= -0.0005 && *x <= 1.0005)
}

/// OKLCH para bytes. Cor fora da gama perde croma até caber, mantendo claridade e matiz.
fn oklch_para_bytes(l: f64, c: f64, h: f64) -> (u8, u8, u8) {
    let l = l.max(0.0).min(1.0);
    let c = c.max(0.0);
    let hr = h * PI / 180.0;
    let direto = oklab_para_linear(l, c * hr.cos(), c * hr.sin());
    if na_gama(direto) || l <= 0.0 || l >= 1.0 {
        return bytes(direto);
    }
    let mut baixo = 0.0f64;
    let mut alto = c;
    for _ in 0..18 {
        let meio = (baixo + alto) / 2.0;
        let teste = oklab_para_linear(l, meio * hr.cos(), meio * hr.sin());
        if na_gama(teste) {
            baixo = meio;
        } else {
            alto = meio;
        }
    }
    bytes(oklab_para_linear(l, baixo * hr.cos(), baixo * hr.sin()))
}

fn oklab_para_bytes(l: f64, a: f64, b: f64) -> (u8, u8, u8) {
    let c = (a * a + b * b).sqrt();
    let mut h = b.atan2(a) * 180.0 / PI;
    if h < 0.0 {
        h += 360.0;
    }
    oklch_para_bytes(l, c, h)
}

// ---------------------------------------------------------------------------------------------
// Leitura dos argumentos
// ---------------------------------------------------------------------------------------------

/// Separa por vírgulas que estão fora de parênteses.
fn dividir_virgulas(s: &str) -> Vec<&str> {
    let mut saida: Vec<&str> = Vec::new();
    let mut prof = 0i32;
    let mut inicio = 0usize;
    for (i, c) in s.char_indices() {
        if c == '(' {
            prof += 1;
        } else if c == ')' {
            prof -= 1;
        } else if c == ',' && prof == 0 {
            saida.push(s[inicio..i].trim());
            inicio = i + 1;
        }
    }
    saida.push(s[inicio..].trim());
    saida
}

/// Separa por espaços que estão fora de parênteses.
fn dividir_espacos(s: &str) -> Vec<&str> {
    let mut saida: Vec<&str> = Vec::new();
    let mut prof = 0i32;
    let mut inicio: Option<usize> = None;
    for (i, c) in s.char_indices() {
        if c == '(' {
            prof += 1;
            if inicio.is_none() {
                inicio = Some(i);
            }
        } else if c == ')' {
            prof -= 1;
        } else if c.is_whitespace() && prof <= 0 {
            if let Some(ini) = inicio.take() {
                saida.push(&s[ini..i]);
            }
        } else if inicio.is_none() {
            inicio = Some(i);
        }
    }
    if let Some(ini) = inicio {
        saida.push(&s[ini..]);
    }
    saida
}

/// Canais e transparência de `a b c / alfa`. Vírgulas também valem. Falha se houver função dentro.
fn argumentos(interior: &str) -> Option<(Vec<String>, f32)> {
    if interior.contains('(') {
        return None;
    }
    let texto = interior.replace(',', " ").replace('/', " / ");
    let mut canais: Vec<String> = Vec::new();
    let mut alfa = 1.0f32;
    let mut apos_barra = false;
    for t in texto.split_whitespace() {
        if t == "/" {
            apos_barra = true;
        } else if apos_barra {
            alfa = numero(t, 1.0)? as f32;
            alfa = alfa.max(0.0).min(1.0);
        } else {
            canais.push(t.to_string());
        }
    }
    Some((canais, alfa))
}

/// Número, porcentagem (`cheio` é o valor de 100%) ou `none`.
fn numero(t: &str, cheio: f64) -> Option<f64> {
    if t == "none" {
        return Some(0.0);
    }
    match t.strip_suffix('%') {
        Some(n) => n.trim().parse::<f64>().ok().map(|x| x / 100.0 * cheio),
        None => t.parse::<f64>().ok(),
    }
}

/// Ângulo em graus. Aceita deg, grad, rad, turn e número puro.
fn matiz(t: &str) -> Option<f64> {
    if t == "none" {
        return Some(0.0);
    }
    let (n, fator) = if let Some(n) = t.strip_suffix("deg") {
        (n, 1.0)
    } else if let Some(n) = t.strip_suffix("grad") {
        (n, 0.9)
    } else if let Some(n) = t.strip_suffix("rad") {
        (n, 180.0 / PI)
    } else if let Some(n) = t.strip_suffix("turn") {
        (n, 360.0)
    } else {
        (t, 1.0)
    };
    n.trim().parse::<f64>().ok().map(|x| x * fator)
}

fn finalizar(rgb: (u8, u8, u8), alfa: f32) -> Option<Rgba> {
    Some((rgb.0, rgb.1, rgb.2, alfa))
}

// ---------------------------------------------------------------------------------------------
// Funções de cor
// ---------------------------------------------------------------------------------------------

fn hwb(interior: &str) -> Option<Rgba> {
    let (c, alfa) = argumentos(interior)?;
    if c.len() != 3 {
        return None;
    }
    let h = matiz(&c[0])?;
    let mut w = numero(&c[1], 1.0)?;
    let mut b = numero(&c[2], 1.0)?;
    // Sem % o número vale como porcentagem (hwb(0 20 30)).
    if !c[1].ends_with('%') && c[1] != "none" {
        w /= 100.0;
    }
    if !c[2].ends_with('%') && c[2] != "none" {
        b /= 100.0;
    }
    w = w.max(0.0).min(1.0);
    b = b.max(0.0).min(1.0);
    if w + b >= 1.0 {
        let cinza = (w / (w + b) * 255.0).round() as u8;
        return finalizar((cinza, cinza, cinza), alfa);
    }
    let h = ((h % 360.0) + 360.0) % 360.0 / 60.0;
    let puro = |k: f64| -> f64 {
        let t = ((k + h) % 6.0 + 6.0) % 6.0;
        let v = (t - 3.0).abs() - 1.0;
        v.max(0.0).min(1.0)
    };
    let canal = |k: f64| -> u8 {
        let v = puro(k) * (1.0 - w - b) + w;
        (v.max(0.0).min(1.0) * 255.0).round() as u8
    };
    finalizar((canal(0.0), canal(4.0), canal(2.0)), alfa)
}

/// `lab(L a b)` e, com `polar`, `lch(L C H)`.
fn lab(interior: &str, polar: bool) -> Option<Rgba> {
    let (c, alfa) = argumentos(interior)?;
    if c.len() != 3 {
        return None;
    }
    let l = numero(&c[0], 100.0)?;
    let (a, b) = if polar {
        let croma = numero(&c[1], 150.0)?.max(0.0);
        let h = matiz(&c[2])? * PI / 180.0;
        (croma * h.cos(), croma * h.sin())
    } else {
        (numero(&c[1], 125.0)?, numero(&c[2], 125.0)?)
    };
    let linear = lab_para_linear(l.max(0.0).min(100.0), a, b);
    finalizar(bytes(linear), alfa)
}

/// `oklab(L a b)` e, com `polar`, `oklch(L C H)`.
fn oklab(interior: &str, polar: bool) -> Option<Rgba> {
    let (c, alfa) = argumentos(interior)?;
    if c.len() != 3 {
        return None;
    }
    let l = numero(&c[0], 1.0)?;
    if polar {
        let croma = numero(&c[1], 0.4)?;
        let h = matiz(&c[2])?;
        finalizar(oklch_para_bytes(l, croma, h), alfa)
    } else {
        let a = numero(&c[1], 0.4)?;
        let b = numero(&c[2], 0.4)?;
        finalizar(oklab_para_bytes(l.max(0.0).min(1.0), a, b), alfa)
    }
}

/// `color(srgb r g b)`, `srgb-linear`, `display-p3`, `xyz`, `xyz-d65` e `xyz-d50`.
fn cor_espaco(interior: &str) -> Option<Rgba> {
    let (c, alfa) = argumentos(interior)?;
    if c.len() != 4 {
        return None;
    }
    let x = numero(&c[1], 1.0)?;
    let y = numero(&c[2], 1.0)?;
    let z = numero(&c[3], 1.0)?;
    let linear: [f64; 3] = match c[0].as_str() {
        "srgb" => [para_linear(x), para_linear(y), para_linear(z)],
        "srgb-linear" => [x, y, z],
        "display-p3" => {
            let p3 = [para_linear(x), para_linear(y), para_linear(z)];
            multiplicar(&XYZ_PARA_RGB, multiplicar(&P3_PARA_XYZ, p3))
        }
        "xyz" | "xyz-d65" => multiplicar(&XYZ_PARA_RGB, [x, y, z]),
        "xyz-d50" => multiplicar(&XYZ_PARA_RGB, multiplicar(&D50_PARA_D65, [x, y, z])),
        _ => return None,
    };
    finalizar(bytes(linear), alfa)
}

// ---------------------------------------------------------------------------------------------
// color-mix
// ---------------------------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq)]
enum Espaco {
    Srgb,
    SrgbLinear,
    Oklab,
    Oklch,
    Lab,
    Lch,
    Xyz,
}

fn espaco_de(nome: &str) -> Option<Espaco> {
    match nome {
        // hsl e hwb são misturados em sRGB: a diferença é pequena e o custo de implementar o matiz não compensa.
        "srgb" | "hsl" | "hwb" => Some(Espaco::Srgb),
        "srgb-linear" => Some(Espaco::SrgbLinear),
        "oklab" => Some(Espaco::Oklab),
        "oklch" => Some(Espaco::Oklch),
        "lab" => Some(Espaco::Lab),
        "lch" => Some(Espaco::Lch),
        "xyz" | "xyz-d65" | "xyz-d50" => Some(Espaco::Xyz),
        _ => None,
    }
}

fn polar(e: Espaco) -> bool {
    e == Espaco::Oklch || e == Espaco::Lch
}

/// Cor (bytes) para as três coordenadas do espaço. Nos espaços polares: claridade, croma, matiz.
fn para_espaco(e: Espaco, rgb: (u8, u8, u8)) -> [f64; 3] {
    let codificado = [rgb.0 as f64 / 255.0, rgb.1 as f64 / 255.0, rgb.2 as f64 / 255.0];
    let linear = [
        para_linear(codificado[0]),
        para_linear(codificado[1]),
        para_linear(codificado[2]),
    ];
    match e {
        Espaco::Srgb => codificado,
        Espaco::SrgbLinear => linear,
        Espaco::Oklab => linear_para_oklab(linear),
        Espaco::Lab => linear_para_lab(linear),
        Espaco::Xyz => multiplicar(&RGB_PARA_XYZ, linear),
        Espaco::Oklch | Espaco::Lch => {
            let t = if e == Espaco::Oklch { linear_para_oklab(linear) } else { linear_para_lab(linear) };
            let croma = (t[1] * t[1] + t[2] * t[2]).sqrt();
            let mut h = t[2].atan2(t[1]) * 180.0 / PI;
            if h < 0.0 {
                h += 360.0;
            }
            [t[0], croma, h]
        }
    }
}

fn de_espaco(e: Espaco, v: [f64; 3]) -> (u8, u8, u8) {
    match e {
        Espaco::Srgb => bytes([para_linear(v[0]), para_linear(v[1]), para_linear(v[2])]),
        Espaco::SrgbLinear => bytes(v),
        Espaco::Oklab => oklab_para_bytes(v[0], v[1], v[2]),
        Espaco::Oklch => oklch_para_bytes(v[0], v[1], v[2]),
        Espaco::Lab => bytes(lab_para_linear(v[0].max(0.0).min(100.0), v[1], v[2])),
        Espaco::Lch => {
            let h = v[2] * PI / 180.0;
            bytes(lab_para_linear(v[0].max(0.0).min(100.0), v[1].max(0.0) * h.cos(), v[1].max(0.0) * h.sin()))
        }
        Espaco::Xyz => bytes(multiplicar(&XYZ_PARA_RGB, v)),
    }
}

/// Uma cor do `color-mix` com a porcentagem opcional (`red 30%` ou `30% red`).
fn cor_com_porcentagem(texto: &str, leitor: Leitor) -> Option<(Rgba, Option<f64>)> {
    let partes = dividir_espacos(texto);
    if partes.is_empty() {
        return None;
    }
    let ultima = partes[partes.len() - 1];
    let primeira = partes[0];
    let (cor_txt, pct): (String, Option<f64>) = if partes.len() >= 2 && ultima.ends_with('%') && !ultima.contains('(') {
        (partes[..partes.len() - 1].join(" "), numero(ultima, 100.0))
    } else if partes.len() >= 2 && primeira.ends_with('%') && !primeira.contains('(') {
        (partes[1..].join(" "), numero(primeira, 100.0))
    } else {
        (texto.trim().to_string(), None)
    };
    let cor = leitor(&cor_txt)?;
    Some((cor, pct))
}

fn misturar(interior: &str, leitor: Leitor) -> Option<Rgba> {
    let partes = dividir_virgulas(interior);
    if partes.len() != 3 {
        return None;
    }
    let mut cabeca = partes[0].split_whitespace();
    if cabeca.next()? != "in" {
        return None;
    }
    let espaco = espaco_de(cabeca.next()?)?;

    let (c1, p1) = cor_com_porcentagem(partes[1], leitor)?;
    let (c2, p2) = cor_com_porcentagem(partes[2], leitor)?;
    let (mut w1, mut w2) = match (p1, p2) {
        (Some(a), Some(b)) => (a, b),
        (Some(a), None) => (a, 100.0 - a),
        (None, Some(b)) => (100.0 - b, b),
        (None, None) => (50.0, 50.0),
    };
    let soma = w1 + w2;
    if soma <= 0.0 {
        return None;
    }
    // Porcentagens que somam menos de 100% deixam o resultado mais transparente.
    let escala_alfa = if soma < 100.0 { soma / 100.0 } else { 1.0 };
    w1 /= soma;
    w2 /= soma;

    let a1 = c1.3 as f64;
    let a2 = c2.3 as f64;
    let alfa = a1 * w1 + a2 * w2;
    if alfa <= 0.0 {
        return Some((0, 0, 0, 0.0));
    }
    let mut x = para_espaco(espaco, (c1.0, c1.1, c1.2));
    let mut y = para_espaco(espaco, (c2.0, c2.1, c2.2));

    let mut misto = [0.0f64; 3];
    if polar(espaco) {
        // Cor sem croma não tem matiz: usa o da outra.
        if x[1] < 0.0001 {
            x[2] = y[2];
        }
        if y[1] < 0.0001 {
            y[2] = x[2];
        }
        // Matiz pelo caminho mais curto.
        let mut h2 = y[2];
        let d = h2 - x[2];
        if d > 180.0 {
            h2 -= 360.0;
        } else if d < -180.0 {
            h2 += 360.0;
        }
        misto[2] = (x[2] * w1 + h2 * w2 + 360.0) % 360.0;
        for i in 0..2 {
            misto[i] = (x[i] * a1 * w1 + y[i] * a2 * w2) / alfa;
        }
    } else {
        for i in 0..3 {
            misto[i] = (x[i] * a1 * w1 + y[i] * a2 * w2) / alfa;
        }
    }
    let rgb = de_espaco(espaco, misto);
    let final_alfa = ((alfa * escala_alfa) as f32).max(0.0).min(1.0);
    Some((rgb.0, rgb.1, rgb.2, final_alfa))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base(v: &str) -> Option<Rgba> {
        let v = v.trim();
        if v == "transparent" {
            return Some((0, 0, 0, 0.0));
        }
        if let Some(n) = por_nome(v) {
            return Some((n.0, n.1, n.2, 1.0));
        }
        funcao(v, false, base)
    }

    fn perto(a: Option<Rgba>, r: u8, g: u8, b: u8) -> bool {
        match a {
            Some(c) => {
                (c.0 as i32 - r as i32).abs() <= 1
                    && (c.1 as i32 - g as i32).abs() <= 1
                    && (c.2 as i32 - b as i32).abs() <= 1
            }
            None => false,
        }
    }

    #[test]
    fn nomes_de_cor() {
        assert_eq!(por_nome("rebeccapurple"), Some((102, 51, 153)));
        assert_eq!(por_nome("gold"), Some((255, 215, 0)));
        assert_eq!(por_nome("lightgray"), Some((211, 211, 211)));
        assert_eq!(por_nome("grey"), Some((128, 128, 128)));
        assert_eq!(por_nome("naoexiste"), None);
    }

    #[test]
    fn oklch_do_tailwind() {
        // red-500 e blue-500 do Tailwind 4.
        assert!(perto(base("oklch(63.7% 0.237 25.331)"), 251, 44, 54));
        assert!(perto(base("oklch(0.623 0.214 259.815)"), 50, 128, 255));
        assert!(perto(base("oklch(1 0 0)"), 255, 255, 255));
        assert!(perto(base("oklch(0 0 0)"), 0, 0, 0));
    }

    #[test]
    fn oklch_com_alfa_e_none() {
        let c = base("oklch(0.5 0 none / 50%)").unwrap();
        assert!((c.3 - 0.5).abs() < 0.01);
        assert!(perto(Some(c), 99, 99, 99));
    }

    #[test]
    fn lab_e_lch() {
        assert!(perto(base("lab(54.29 80.8 69.89)"), 255, 0, 0));
        assert!(perto(base("lch(100 0 0)"), 255, 255, 255));
    }

    #[test]
    fn hwb_funciona() {
        assert!(perto(base("hwb(0 0% 0%)"), 255, 0, 0));
        assert!(perto(base("hwb(120 0% 50%)"), 0, 128, 0));
        assert!(perto(base("hwb(0 100% 0%)"), 255, 255, 255));
    }

    #[test]
    fn color_srgb_e_display_p3() {
        assert!(perto(base("color(srgb 1 0 0)"), 255, 0, 0));
        assert!(perto(base("color(srgb 0.5 0.5 0.5 / 0.2)"), 128, 128, 128));
        assert!(perto(base("color(display-p3 1 1 1)"), 255, 255, 255));
    }

    #[test]
    fn color_mix_em_srgb() {
        assert!(perto(base("color-mix(in srgb, red, blue)"), 128, 0, 128));
        let c = base("color-mix(in srgb, white 50%, transparent)").unwrap();
        assert!(perto(Some(c), 255, 255, 255));
        assert!((c.3 - 0.5).abs() < 0.01);
    }

    #[test]
    fn color_mix_em_oklab() {
        assert!(perto(base("color-mix(in oklab, red, blue)"), 140, 83, 162));
        assert!(perto(base("color-mix(in oklab, white 30%, red)"), 255, 119, 101));
        let c = base("color-mix(in oklab, black 50%, transparent)").unwrap();
        assert!(perto(Some(c), 0, 0, 0));
        assert!((c.3 - 0.5).abs() < 0.01);
    }

    #[test]
    fn color_mix_com_cor_dentro_de_cor() {
        let c = base("color-mix(in oklab, oklch(63.7% 0.237 25.331) 40%, transparent)").unwrap();
        assert!(perto(Some(c), 251, 44, 54));
        assert!((c.3 - 0.4).abs() < 0.01);
    }

    #[test]
    fn color_mix_invalido_e_none() {
        assert!(base("color-mix(red, blue)").is_none());
        assert!(base("color-mix(in foo, red, blue)").is_none());
    }

    #[test]
    fn light_dark_segue_o_tema() {
        assert!(perto(funcao("light-dark(red, blue)", false, base), 255, 0, 0));
        assert!(perto(funcao("light-dark(red, blue)", true, base), 0, 0, 255));
    }

    #[test]
    fn funcao_desconhecida_e_none() {
        assert!(base("foo(1 2 3)").is_none());
    }
}
