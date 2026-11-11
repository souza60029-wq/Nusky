// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! SVG simples: transforma `<svg>` em caminhos (retas e curvas de Bézier) já na posição da página.
//! Entende `path`, `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`, `g`, `transform`,
//! `viewBox`, `fill`, `stroke` e `currentColor`. Não entende gradientes, máscaras, texto nem `use`.

use crate::html::{Element, Node};

/// Como uma forma é pintada.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Tinta {
    Nenhuma,
    /// `currentColor`: a cor do texto onde o SVG está.
    Atual,
    Rgb(u8, u8, u8),
}

/// Um caminho pronto para desenhar, com as coordenadas já na posição da página.
#[derive(Debug, Clone, PartialEq)]
pub struct FormaSvg {
    pub preenchimento: Tinta,
    pub opacidade_preenchimento: f32,
    pub traco: Tinta,
    pub opacidade_traco: f32,
    pub largura_traco: f32,
    /// Regra par-ímpar de preenchimento (`fill-rule: evenodd`).
    pub par_impar: bool,
    /// Comandos absolutos: `M x y`, `L x y`, `C x1 y1 x2 y2 x y` e `Z`, separados por espaço.
    pub caminho: String,
}

/// Matriz de transformação 2D: x' = a·x + c·y + e, y' = b·x + d·y + f.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Mat {
    a: f32,
    b: f32,
    c: f32,
    d: f32,
    e: f32,
    f: f32,
}

impl Mat {
    const ID: Mat = Mat { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0 };

    /// `self` depois de `o` (aplica `o` primeiro).
    fn mul(self, o: Mat) -> Mat {
        Mat {
            a: self.a * o.a + self.c * o.b,
            b: self.b * o.a + self.d * o.b,
            c: self.a * o.c + self.c * o.d,
            d: self.b * o.c + self.d * o.d,
            e: self.a * o.e + self.c * o.f + self.e,
            f: self.b * o.e + self.d * o.f + self.f,
        }
    }

    fn ponto(&self, x: f32, y: f32) -> (f32, f32) {
        (self.a * x + self.c * y + self.e, self.b * x + self.d * y + self.f)
    }

    /// Escala média, para a largura do traço.
    fn escala(&self) -> f32 {
        (self.a * self.d - self.b * self.c).abs().sqrt()
    }
}

/// Segmento de caminho absoluto.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Seg {
    M(f32, f32),
    L(f32, f32),
    C(f32, f32, f32, f32, f32, f32),
    Z,
}

/// Estilo herdado pelos filhos.
#[derive(Clone)]
struct Estilo {
    preenchimento: Tinta,
    opacidade_preenchimento: f32,
    traco: Tinta,
    opacidade_traco: f32,
    largura_traco: f32,
    par_impar: bool,
    opacidade: f32,
    mat: Mat,
}

// --- números -----------------------------------------------------------------------------------

fn numero_simples(texto: &str) -> Option<f32> {
    let t = texto.trim().trim_end_matches("px").trim();
    t.parse::<f32>().ok()
}

fn lista_de_numeros(texto: &str) -> Vec<f32> {
    let mut leitor = Leitor::novo(texto);
    let mut saida = Vec::new();
    while let Some(n) = leitor.numero() {
        saida.push(n);
    }
    saida
}

/// Leitor de números de dados de caminho e listas de pontos.
struct Leitor<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Leitor<'a> {
    fn novo(texto: &'a str) -> Leitor<'a> {
        Leitor { b: texto.as_bytes(), i: 0 }
    }

    fn espacos(&mut self) {
        while self.i < self.b.len() && (self.b[self.i].is_ascii_whitespace() || self.b[self.i] == b',') {
            self.i += 1;
        }
    }

    fn fim(&self) -> bool {
        self.i >= self.b.len()
    }

    fn espiar(&self) -> Option<u8> {
        self.b.get(self.i).copied()
    }

    /// Lê um número: sinal, dígitos, ponto decimal e expoente. `1.5.5` são dois números.
    fn numero(&mut self) -> Option<f32> {
        self.espacos();
        let inicio = self.i;
        let mut j = self.i;
        if j < self.b.len() && (self.b[j] == b'+' || self.b[j] == b'-') {
            j += 1;
        }
        let mut digitos = 0;
        while j < self.b.len() && self.b[j].is_ascii_digit() {
            j += 1;
            digitos += 1;
        }
        if j < self.b.len() && self.b[j] == b'.' {
            j += 1;
            while j < self.b.len() && self.b[j].is_ascii_digit() {
                j += 1;
                digitos += 1;
            }
        }
        if digitos == 0 {
            return None;
        }
        if j < self.b.len() && (self.b[j] == b'e' || self.b[j] == b'E') {
            let mut k = j + 1;
            if k < self.b.len() && (self.b[k] == b'+' || self.b[k] == b'-') {
                k += 1;
            }
            let ini_exp = k;
            while k < self.b.len() && self.b[k].is_ascii_digit() {
                k += 1;
            }
            if k > ini_exp {
                j = k;
            }
        }
        let texto = std::str::from_utf8(&self.b[inicio..j]).ok()?;
        self.i = j;
        texto.parse::<f32>().ok()
    }

    /// Lê a bandeira de um arco: um único `0` ou `1`, que pode vir colado no próximo número.
    fn bandeira(&mut self) -> Option<bool> {
        self.espacos();
        match self.espiar() {
            Some(b'0') => {
                self.i += 1;
                Some(false)
            }
            Some(b'1') => {
                self.i += 1;
                Some(true)
            }
            _ => None,
        }
    }
}

// --- caminho (atributo d) ----------------------------------------------------------------------

/// Converte um arco elíptico em curvas de Bézier cúbicas.
#[allow(clippy::too_many_arguments)]
fn arco_em_curvas(
    x0: f32,
    y0: f32,
    rx: f32,
    ry: f32,
    graus: f32,
    grande: bool,
    sentido: bool,
    x: f32,
    y: f32,
    saida: &mut Vec<Seg>,
) {
    if (x0 - x).abs() < 1e-6 && (y0 - y).abs() < 1e-6 {
        return;
    }
    let mut rx = rx.abs();
    let mut ry = ry.abs();
    if rx < 1e-6 || ry < 1e-6 {
        saida.push(Seg::L(x, y));
        return;
    }
    let fi = graus.to_radians();
    let (sf, cf) = fi.sin_cos();
    let dx2 = (x0 - x) / 2.0;
    let dy2 = (y0 - y) / 2.0;
    let x1p = cf * dx2 + sf * dy2;
    let y1p = -sf * dx2 + cf * dy2;
    let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if lambda > 1.0 {
        let s = lambda.sqrt();
        rx *= s;
        ry *= s;
    }
    let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    let sinal = if grande == sentido { -1.0 } else { 1.0 };
    let coef = if den.abs() < 1e-12 { 0.0 } else { sinal * (num / den).max(0.0).sqrt() };
    let cxp = coef * (rx * y1p / ry);
    let cyp = coef * (-(ry * x1p) / rx);
    let cx = cf * cxp - sf * cyp + (x0 + x) / 2.0;
    let cy = sf * cxp + cf * cyp + (y0 + y) / 2.0;

    let angulo = |ux: f32, uy: f32, vx: f32, vy: f32| -> f32 {
        let dot = ux * vx + uy * vy;
        let len = (ux * ux + uy * uy).sqrt() * (vx * vx + vy * vy).sqrt();
        let mut a = (dot / len).clamp(-1.0, 1.0).acos();
        if ux * vy - uy * vx < 0.0 {
            a = -a;
        }
        a
    };
    let teta1 = angulo(1.0, 0.0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    let mut dteta = angulo((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
    if !sentido && dteta > 0.0 {
        dteta -= std::f32::consts::TAU;
    } else if sentido && dteta < 0.0 {
        dteta += std::f32::consts::TAU;
    }

    let n = (dteta.abs() / std::f32::consts::FRAC_PI_2).ceil().max(1.0) as usize;
    let delta = dteta / n as f32;
    let t = 4.0 / 3.0 * (delta / 4.0).tan();
    let mut a1 = teta1;
    for _ in 0..n {
        let a2 = a1 + delta;
        let (s1, c1) = a1.sin_cos();
        let (s2, c2) = a2.sin_cos();
        let p1 = (c1 - t * s1, s1 + t * c1);
        let p2 = (c2 + t * s2, s2 - t * c2);
        let p3 = (c2, s2);
        let mapa = |p: (f32, f32)| -> (f32, f32) {
            (cx + rx * p.0 * cf - ry * p.1 * sf, cy + rx * p.0 * sf + ry * p.1 * cf)
        };
        let (ax, ay) = mapa(p1);
        let (bx, by) = mapa(p2);
        let (ex, ey) = mapa(p3);
        saida.push(Seg::C(ax, ay, bx, by, ex, ey));
        a1 = a2;
    }
    // Garante que o fim bate exatamente com o ponto pedido.
    if let Some(Seg::C(a, b, c, d, _, _)) = saida.last().copied() {
        saida.pop();
        saida.push(Seg::C(a, b, c, d, x, y));
    }
}

/// Lê os dados de caminho (`d`) e devolve segmentos absolutos.
fn ler_caminho(d: &str) -> Vec<Seg> {
    let mut l = Leitor::novo(d);
    let mut saida: Vec<Seg> = Vec::new();
    let (mut cx, mut cy) = (0.0_f32, 0.0_f32);
    let (mut ix, mut iy) = (0.0_f32, 0.0_f32);
    // Último ponto de controle, para S e T.
    let (mut ucx, mut ucy) = (0.0_f32, 0.0_f32);
    let mut cmd = b' ';
    let mut anterior = b' ';

    loop {
        l.espacos();
        if l.fim() {
            break;
        }
        let c = l.espiar().unwrap_or(b' ');
        if c.is_ascii_alphabetic() {
            cmd = c;
            l.i += 1;
            if cmd == b'Z' || cmd == b'z' {
                saida.push(Seg::Z);
                cx = ix;
                cy = iy;
                anterior = b'Z';
                continue;
            }
        } else if cmd == b' ' || cmd == b'Z' || cmd == b'z' {
            break;
        }
        let relativo = cmd.is_ascii_lowercase();
        let (ox, oy) = if relativo { (cx, cy) } else { (0.0, 0.0) };
        let maiusculo = cmd.to_ascii_uppercase();
        match maiusculo {
            b'M' => {
                let (Some(x), Some(y)) = (l.numero(), l.numero()) else { break };
                cx = ox + x;
                cy = oy + y;
                ix = cx;
                iy = cy;
                saida.push(Seg::M(cx, cy));
                // Pares seguintes de M viram L.
                cmd = if relativo { b'l' } else { b'L' };
            }
            b'L' => {
                let (Some(x), Some(y)) = (l.numero(), l.numero()) else { break };
                cx = ox + x;
                cy = oy + y;
                saida.push(Seg::L(cx, cy));
            }
            b'H' => {
                let Some(x) = l.numero() else { break };
                cx = ox + x;
                saida.push(Seg::L(cx, cy));
            }
            b'V' => {
                let Some(y) = l.numero() else { break };
                cy = oy + y;
                saida.push(Seg::L(cx, cy));
            }
            b'C' => {
                let (Some(x1), Some(y1), Some(x2), Some(y2), Some(x), Some(y)) =
                    (l.numero(), l.numero(), l.numero(), l.numero(), l.numero(), l.numero())
                else {
                    break;
                };
                let (a, b, c2, d2, e, f) = (ox + x1, oy + y1, ox + x2, oy + y2, ox + x, oy + y);
                saida.push(Seg::C(a, b, c2, d2, e, f));
                ucx = c2;
                ucy = d2;
                cx = e;
                cy = f;
            }
            b'S' => {
                let (Some(x2), Some(y2), Some(x), Some(y)) = (l.numero(), l.numero(), l.numero(), l.numero())
                else {
                    break;
                };
                let (a, b) = if anterior == b'C' || anterior == b'S' { (2.0 * cx - ucx, 2.0 * cy - ucy) } else { (cx, cy) };
                let (c2, d2, e, f) = (ox + x2, oy + y2, ox + x, oy + y);
                saida.push(Seg::C(a, b, c2, d2, e, f));
                ucx = c2;
                ucy = d2;
                cx = e;
                cy = f;
            }
            b'Q' => {
                let (Some(x1), Some(y1), Some(x), Some(y)) = (l.numero(), l.numero(), l.numero(), l.numero())
                else {
                    break;
                };
                let (qx, qy, e, f) = (ox + x1, oy + y1, ox + x, oy + y);
                saida.push(Seg::C(
                    cx + 2.0 / 3.0 * (qx - cx),
                    cy + 2.0 / 3.0 * (qy - cy),
                    e + 2.0 / 3.0 * (qx - e),
                    f + 2.0 / 3.0 * (qy - f),
                    e,
                    f,
                ));
                ucx = qx;
                ucy = qy;
                cx = e;
                cy = f;
            }
            b'T' => {
                let (Some(x), Some(y)) = (l.numero(), l.numero()) else { break };
                let (qx, qy) = if anterior == b'Q' || anterior == b'T' { (2.0 * cx - ucx, 2.0 * cy - ucy) } else { (cx, cy) };
                let (e, f) = (ox + x, oy + y);
                saida.push(Seg::C(
                    cx + 2.0 / 3.0 * (qx - cx),
                    cy + 2.0 / 3.0 * (qy - cy),
                    e + 2.0 / 3.0 * (qx - e),
                    f + 2.0 / 3.0 * (qy - f),
                    e,
                    f,
                ));
                ucx = qx;
                ucy = qy;
                cx = e;
                cy = f;
            }
            b'A' => {
                let (Some(rx), Some(ry), Some(graus)) = (l.numero(), l.numero(), l.numero()) else { break };
                let (Some(grande), Some(sentido)) = (l.bandeira(), l.bandeira()) else { break };
                let (Some(x), Some(y)) = (l.numero(), l.numero()) else { break };
                let (e, f) = (ox + x, oy + y);
                arco_em_curvas(cx, cy, rx, ry, graus, grande, sentido, e, f, &mut saida);
                cx = e;
                cy = f;
            }
            _ => break,
        }
        anterior = maiusculo;
    }
    saida
}

// --- formas básicas ----------------------------------------------------------------------------

const K: f32 = 0.552_284_75;

fn elipse(cx: f32, cy: f32, rx: f32, ry: f32) -> Vec<Seg> {
    vec![
        Seg::M(cx + rx, cy),
        Seg::C(cx + rx, cy + K * ry, cx + K * rx, cy + ry, cx, cy + ry),
        Seg::C(cx - K * rx, cy + ry, cx - rx, cy + K * ry, cx - rx, cy),
        Seg::C(cx - rx, cy - K * ry, cx - K * rx, cy - ry, cx, cy - ry),
        Seg::C(cx + K * rx, cy - ry, cx + rx, cy - K * ry, cx + rx, cy),
        Seg::Z,
    ]
}

fn retangulo(x: f32, y: f32, w: f32, h: f32, rx: f32, ry: f32) -> Vec<Seg> {
    let rx = rx.min(w / 2.0).max(0.0);
    let ry = ry.min(h / 2.0).max(0.0);
    if rx <= 0.0 || ry <= 0.0 {
        return vec![Seg::M(x, y), Seg::L(x + w, y), Seg::L(x + w, y + h), Seg::L(x, y + h), Seg::Z];
    }
    vec![
        Seg::M(x + rx, y),
        Seg::L(x + w - rx, y),
        Seg::C(x + w - rx + K * rx, y, x + w, y + ry - K * ry, x + w, y + ry),
        Seg::L(x + w, y + h - ry),
        Seg::C(x + w, y + h - ry + K * ry, x + w - rx + K * rx, y + h, x + w - rx, y + h),
        Seg::L(x + rx, y + h),
        Seg::C(x + rx - K * rx, y + h, x, y + h - ry + K * ry, x, y + h - ry),
        Seg::L(x, y + ry),
        Seg::C(x, y + ry - K * ry, x + rx - K * rx, y, x + rx, y),
        Seg::Z,
    ]
}

fn pontos(texto: &str, fechar: bool) -> Vec<Seg> {
    let n = lista_de_numeros(texto);
    let mut saida = Vec::new();
    for (i, par) in n.chunks(2).enumerate() {
        if par.len() < 2 {
            break;
        }
        saida.push(if i == 0 { Seg::M(par[0], par[1]) } else { Seg::L(par[0], par[1]) });
    }
    if fechar && !saida.is_empty() {
        saida.push(Seg::Z);
    }
    saida
}

// --- transformações e cores --------------------------------------------------------------------

fn ler_transformacao(texto: &str) -> Mat {
    let mut m = Mat::ID;
    let mut resto = texto;
    while let Some(abre) = resto.find('(') {
        let nome = resto[..abre].trim().trim_start_matches(',').trim().to_ascii_lowercase();
        let Some(fecha) = resto[abre..].find(')') else { break };
        let args = lista_de_numeros(&resto[abre + 1..abre + fecha]);
        let local = match nome.as_str() {
            "translate" if !args.is_empty() => {
                Mat { e: args[0], f: args.get(1).copied().unwrap_or(0.0), ..Mat::ID }
            }
            "scale" if !args.is_empty() => {
                Mat { a: args[0], d: args.get(1).copied().unwrap_or(args[0]), ..Mat::ID }
            }
            "rotate" if !args.is_empty() => {
                let (s, c) = args[0].to_radians().sin_cos();
                let giro = Mat { a: c, b: s, c: -s, d: c, e: 0.0, f: 0.0 };
                if args.len() >= 3 {
                    let (cx, cy) = (args[1], args[2]);
                    Mat { e: cx, f: cy, ..Mat::ID }.mul(giro).mul(Mat { e: -cx, f: -cy, ..Mat::ID })
                } else {
                    giro
                }
            }
            "matrix" if args.len() >= 6 => Mat { a: args[0], b: args[1], c: args[2], d: args[3], e: args[4], f: args[5] },
            "skewx" if !args.is_empty() => Mat { c: args[0].to_radians().tan(), ..Mat::ID },
            "skewy" if !args.is_empty() => Mat { b: args[0].to_radians().tan(), ..Mat::ID },
            _ => Mat::ID,
        };
        m = m.mul(local);
        resto = &resto[abre + fecha + 1..];
    }
    m
}

fn nome_de_cor(nome: &str) -> Option<(u8, u8, u8)> {
    Some(match nome {
        "black" => (0, 0, 0),
        "white" => (255, 255, 255),
        "red" => (255, 0, 0),
        "green" => (0, 128, 0),
        "blue" => (0, 0, 255),
        "yellow" => (255, 255, 0),
        "gray" | "grey" => (128, 128, 128),
        "orange" => (255, 165, 0),
        "purple" => (128, 0, 128),
        _ => return None,
    })
}

/// Lê `fill` ou `stroke`. None quando o valor não diz nada (herda).
fn ler_tinta(valor: &str) -> Option<Tinta> {
    let v = valor.trim().to_ascii_lowercase();
    if v.is_empty() || v == "inherit" {
        return None;
    }
    if v == "none" || v == "transparent" || v.starts_with("url(") {
        return Some(Tinta::Nenhuma);
    }
    if v == "currentcolor" {
        return Some(Tinta::Atual);
    }
    if let Some(hex) = v.strip_prefix('#') {
        let digitos: Vec<u8> = hex.chars().filter_map(|c| c.to_digit(16).map(|d| d as u8)).collect();
        if digitos.len() == 3 {
            return Some(Tinta::Rgb(digitos[0] * 17, digitos[1] * 17, digitos[2] * 17));
        }
        if digitos.len() >= 6 {
            return Some(Tinta::Rgb(
                digitos[0] * 16 + digitos[1],
                digitos[2] * 16 + digitos[3],
                digitos[4] * 16 + digitos[5],
            ));
        }
        return None;
    }
    if let Some(args) = v.strip_prefix("rgb(").and_then(|r| r.strip_suffix(')')) {
        let n = lista_de_numeros(args);
        if n.len() >= 3 {
            return Some(Tinta::Rgb(n[0].clamp(0.0, 255.0) as u8, n[1].clamp(0.0, 255.0) as u8, n[2].clamp(0.0, 255.0) as u8));
        }
        return None;
    }
    nome_de_cor(&v).map(|(r, g, b)| Tinta::Rgb(r, g, b))
}

// --- extração ----------------------------------------------------------------------------------

/// Tamanho natural do SVG: o `viewBox`, ou `width` e `height`. None se não houver nenhum.
pub fn tamanho_natural(svg: &Element) -> Option<(f32, f32)> {
    if let Some(vb) = svg.attr("viewbox") {
        let n = lista_de_numeros(vb);
        if n.len() == 4 && n[2] > 0.0 && n[3] > 0.0 {
            return Some((n[2], n[3]));
        }
    }
    let w = svg.attr("width").and_then(numero_simples).filter(|v| *v > 0.0);
    let h = svg.attr("height").and_then(numero_simples).filter(|v| *v > 0.0);
    match (w, h) {
        (Some(w), Some(h)) => Some((w, h)),
        _ => None,
    }
}

/// Lê um atributo de estilo, seja pelo atributo próprio ou pelo atributo `style`.
fn propriedade(el: &Element, nome: &str) -> Option<String> {
    if let Some(estilo) = el.attr("style") {
        for par in estilo.split(';') {
            if let Some((k, v)) = par.split_once(':') {
                if k.trim().eq_ignore_ascii_case(nome) {
                    return Some(v.trim().to_string());
                }
            }
        }
    }
    el.attr(nome).map(|v| v.trim().to_string())
}

fn aplicar_atributos(el: &Element, pai: &Estilo) -> Estilo {
    let mut e = pai.clone();
    if let Some(t) = propriedade(el, "fill").and_then(|v| ler_tinta(&v)) {
        e.preenchimento = t;
    }
    if let Some(t) = propriedade(el, "stroke").and_then(|v| ler_tinta(&v)) {
        e.traco = t;
    }
    if let Some(n) = propriedade(el, "stroke-width").and_then(|v| numero_simples(&v)) {
        e.largura_traco = n;
    }
    if let Some(n) = propriedade(el, "fill-opacity").and_then(|v| numero_simples(&v)) {
        e.opacidade_preenchimento = n.clamp(0.0, 1.0);
    }
    if let Some(n) = propriedade(el, "stroke-opacity").and_then(|v| numero_simples(&v)) {
        e.opacidade_traco = n.clamp(0.0, 1.0);
    }
    if let Some(n) = propriedade(el, "opacity").and_then(|v| numero_simples(&v)) {
        e.opacidade = (e.opacidade * n).clamp(0.0, 1.0);
    }
    if let Some(r) = propriedade(el, "fill-rule") {
        e.par_impar = r.eq_ignore_ascii_case("evenodd");
    }
    if let Some(t) = el.attr("transform") {
        e.mat = e.mat.mul(ler_transformacao(t));
    }
    e
}

fn numero(el: &Element, nome: &str) -> f32 {
    el.attr(nome).and_then(numero_simples).unwrap_or(0.0)
}

fn oculto(el: &Element) -> bool {
    let mostrar = propriedade(el, "display").unwrap_or_default().to_ascii_lowercase();
    let ver = propriedade(el, "visibility").unwrap_or_default().to_ascii_lowercase();
    mostrar == "none" || ver == "hidden"
}

fn formatar(segs: &[Seg], m: &Mat) -> String {
    let mut s = String::new();
    for seg in segs {
        match *seg {
            Seg::M(x, y) => {
                let (a, b) = m.ponto(x, y);
                s.push_str(&format!("M {:.2} {:.2} ", a, b));
            }
            Seg::L(x, y) => {
                let (a, b) = m.ponto(x, y);
                s.push_str(&format!("L {:.2} {:.2} ", a, b));
            }
            Seg::C(x1, y1, x2, y2, x, y) => {
                let (a, b) = m.ponto(x1, y1);
                let (c, d) = m.ponto(x2, y2);
                let (e, f) = m.ponto(x, y);
                s.push_str(&format!("C {:.2} {:.2} {:.2} {:.2} {:.2} {:.2} ", a, b, c, d, e, f));
            }
            Seg::Z => s.push_str("Z "),
        }
    }
    s.trim_end().to_string()
}

fn visitar(el: &Element, pai: &Estilo, saida: &mut Vec<FormaSvg>) {
    const IGNORADAS: [&str; 18] = [
        "defs", "clippath", "mask", "lineargradient", "radialgradient", "title", "desc", "style", "script", "text",
        "image", "use", "foreignobject", "marker", "pattern", "filter", "metadata", "symbol",
    ];
    if IGNORADAS.contains(&el.tag.as_str()) || oculto(el) {
        return;
    }
    let estilo = aplicar_atributos(el, pai);
    let segs: Vec<Seg> = match el.tag.as_str() {
        "path" => ler_caminho(el.attr("d").unwrap_or("")),
        "rect" => retangulo(
            numero(el, "x"),
            numero(el, "y"),
            numero(el, "width"),
            numero(el, "height"),
            numero(el, "rx").max(if el.attr("rx").is_none() { numero(el, "ry") } else { 0.0 }),
            numero(el, "ry").max(if el.attr("ry").is_none() { numero(el, "rx") } else { 0.0 }),
        ),
        "circle" => {
            let r = numero(el, "r");
            elipse(numero(el, "cx"), numero(el, "cy"), r, r)
        }
        "ellipse" => elipse(numero(el, "cx"), numero(el, "cy"), numero(el, "rx"), numero(el, "ry")),
        "line" => vec![Seg::M(numero(el, "x1"), numero(el, "y1")), Seg::L(numero(el, "x2"), numero(el, "y2"))],
        "polyline" => pontos(el.attr("points").unwrap_or(""), false),
        "polygon" => pontos(el.attr("points").unwrap_or(""), true),
        _ => Vec::new(),
    };
    if !segs.is_empty() && (estilo.preenchimento != Tinta::Nenhuma || estilo.traco != Tinta::Nenhuma) {
        saida.push(FormaSvg {
            preenchimento: estilo.preenchimento,
            opacidade_preenchimento: estilo.opacidade_preenchimento * estilo.opacidade,
            traco: estilo.traco,
            opacidade_traco: estilo.opacidade_traco * estilo.opacidade,
            largura_traco: (estilo.largura_traco * estilo.mat.escala()).max(0.0),
            par_impar: estilo.par_impar,
            caminho: formatar(&segs, &estilo.mat),
        });
    }
    for filho in &el.children {
        if let Node::Element(f) = filho {
            visitar(f, &estilo, saida);
        }
    }
}

/// Transforma o SVG em formas posicionadas no retângulo (`x`, `y`, `w`, `h`) da página.
/// O desenho do SVG se encaixa no retângulo mantendo a proporção, centralizado.
pub fn extrair(svg: &Element, x: f32, y: f32, w: f32, h: f32) -> Vec<FormaSvg> {
    let (vx, vy, vw, vh) = match svg.attr("viewbox").map(lista_de_numeros) {
        Some(n) if n.len() == 4 && n[2] > 0.0 && n[3] > 0.0 => (n[0], n[1], n[2], n[3]),
        _ => (0.0, 0.0, w.max(1.0), h.max(1.0)),
    };
    let escala = (w / vw).min(h / vh);
    let base = Mat {
        a: escala,
        b: 0.0,
        c: 0.0,
        d: escala,
        e: x + (w - vw * escala) / 2.0 - vx * escala,
        f: y + (h - vh * escala) / 2.0 - vy * escala,
    };
    let inicial = Estilo {
        preenchimento: Tinta::Rgb(0, 0, 0),
        opacidade_preenchimento: 1.0,
        traco: Tinta::Nenhuma,
        opacidade_traco: 1.0,
        largura_traco: 1.0,
        par_impar: false,
        opacidade: 1.0,
        mat: base,
    };
    let mut saida = Vec::new();
    // Os atributos do próprio <svg> (fill, stroke…) valem para os filhos; o transform dele não.
    let mut raiz = aplicar_atributos(svg, &inicial);
    raiz.mat = base;
    for filho in &svg.children {
        if let Node::Element(f) = filho {
            visitar(f, &raiz, &mut saida);
        }
    }
    saida
}

#[cfg(test)]
mod testes {
    use super::*;
    use crate::html::parse;

    fn svg_de(html: &str) -> Element {
        match parse(html).into_iter().next() {
            Some(Node::Element(e)) => e,
            _ => panic!("esperava elemento"),
        }
    }

    #[test]
    fn caminho_com_retas_relativas_e_fechar() {
        let segs = ler_caminho("M10 10 l 5 0 v 5 h-5 z");
        assert_eq!(
            segs,
            vec![Seg::M(10.0, 10.0), Seg::L(15.0, 10.0), Seg::L(15.0, 15.0), Seg::L(10.0, 15.0), Seg::Z]
        );
    }

    #[test]
    fn numeros_colados_e_pares_implicitos() {
        let segs = ler_caminho("M1.5.5 2-3 4 5");
        assert_eq!(segs, vec![Seg::M(1.5, 0.5), Seg::L(2.0, -3.0), Seg::L(4.0, 5.0)]);
    }

    #[test]
    fn arco_vira_curvas_e_termina_no_ponto_certo() {
        let segs = ler_caminho("M0 0 a5 5 0 0 1 10 0");
        assert!(segs.len() >= 3);
        match segs.last() {
            Some(Seg::C(.., x, y)) => {
                assert!((x - 10.0).abs() < 1e-3 && y.abs() < 1e-3);
            }
            _ => panic!("esperava curva"),
        }
    }

    #[test]
    fn bandeiras_do_arco_podem_vir_coladas() {
        let segs = ler_caminho("M0 0a5 5 0 0110 0");
        assert!(segs.len() >= 3);
    }

    #[test]
    fn transformacoes_se_compoem() {
        let m = ler_transformacao("translate(10 20) scale(2)");
        assert_eq!(m.ponto(1.0, 1.0), (12.0, 22.0));
    }

    #[test]
    fn tinta_de_cores() {
        assert_eq!(ler_tinta("none"), Some(Tinta::Nenhuma));
        assert_eq!(ler_tinta("currentColor"), Some(Tinta::Atual));
        assert_eq!(ler_tinta("#f00"), Some(Tinta::Rgb(255, 0, 0)));
        assert_eq!(ler_tinta("rgb(1, 2, 3)"), Some(Tinta::Rgb(1, 2, 3)));
        assert_eq!(ler_tinta("url(#x)"), Some(Tinta::Nenhuma));
    }

    #[test]
    fn svg_se_encaixa_no_retangulo_com_viewbox() {
        let svg = svg_de("<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 L10 10\" stroke=\"currentColor\" fill=\"none\" stroke-width=\"2\"/></svg>");
        let formas = extrair(&svg, 100.0, 50.0, 20.0, 20.0);
        assert_eq!(formas.len(), 1);
        let f = &formas[0];
        assert_eq!(f.preenchimento, Tinta::Nenhuma);
        assert_eq!(f.traco, Tinta::Atual);
        assert_eq!(f.caminho, "M 100.00 50.00 L 120.00 70.00");
        assert!((f.largura_traco - 4.0).abs() < 1e-3);
    }

    #[test]
    fn preenchimento_padrao_e_preto_e_herda_do_grupo() {
        let svg = svg_de("<svg viewBox=\"0 0 4 4\"><g fill=\"#00f\"><rect width=\"4\" height=\"4\"/></g><circle cx=\"2\" cy=\"2\" r=\"1\"/></svg>");
        let formas = extrair(&svg, 0.0, 0.0, 4.0, 4.0);
        assert_eq!(formas.len(), 2);
        assert_eq!(formas[0].preenchimento, Tinta::Rgb(0, 0, 255));
        assert_eq!(formas[1].preenchimento, Tinta::Rgb(0, 0, 0));
    }

    #[test]
    fn partes_ocultas_e_ignoradas_ficam_de_fora() {
        let svg = svg_de("<svg viewBox=\"0 0 4 4\"><defs><path d=\"M0 0 L1 1\"/></defs><path display=\"none\" d=\"M0 0 L1 1\"/><title>x</title></svg>");
        assert!(extrair(&svg, 0.0, 0.0, 4.0, 4.0).is_empty());
    }

    #[test]
    fn tamanho_natural_pelo_viewbox_ou_atributos() {
        assert_eq!(tamanho_natural(&svg_de("<svg viewBox=\"0 0 24 12\"></svg>")), Some((24.0, 12.0)));
        assert_eq!(tamanho_natural(&svg_de("<svg width=\"16\" height=\"8\"></svg>")), Some((16.0, 8.0)));
        assert_eq!(tamanho_natural(&svg_de("<svg></svg>")), None);
    }
}
