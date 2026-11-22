// app/Nusky/PodaCSS.swift
import Foundation

/// Tira do CSS baixado o que o motor nunca usa, antes de entregá-lo a ele.
///
/// Sai: comentários, `@font-face`, `@keyframes`, `@media print`, `@charset`, `@page` e o excesso de espaços.
/// Fica: tudo o mais (seletores, declarações, `@media`, `@layer`, `@supports`...), com textos entre aspas
/// e `url(...)` intactos. O motor já ignorava essas regras; a diferença é que ele não precisa mais lê-las.
/// Folhas grandes (GitHub, ChatGPT) perdem de 15% a 40% do tamanho, o que também ajuda a caber no limite
/// de memória do iPhone 6s. A lógica foi escrita e testada em JavaScript (testes/js/poda_css.js) e transcrita aqui.
enum PodaCSS {
    private static let descartar: Set<String> = [
        "font-face", "keyframes", "-webkit-keyframes", "-moz-keyframes", "-o-keyframes",
        "charset", "counter-style", "font-feature-values", "page", "view-transition"
    ]

    static func enxugar(_ css: String) -> String {
        var leitor = Enxugador(css)
        return leitor.rodar()
    }

    /// `@media print` puro (sem tela, sem `all`, sem lista). `@media print, screen` fica.
    static func apenasImpressao(_ preludio: String) -> Bool {
        if preludio.contains(",") || preludio.contains("screen") || preludio.contains("all") { return false }
        var t = preludio
        if t.hasPrefix("only ") { t = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        return t == "print" || t.hasPrefix("print ")
    }

    private struct Enxugador {
        let b: [UInt8]
        let n: Int
        var i = 0
        var saida: [UInt8] = []
        var espaco = false

        init(_ css: String) {
            b = Array(css.utf8)
            n = b.count
            saida.reserveCapacity(n)
        }

        func em(_ k: Int) -> UInt8 { (k >= 0 && k < n) ? b[k] : 0 }

        static func branco(_ c: UInt8) -> Bool {
            c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C
        }

        /// `i` está em "/*": vai para depois do "*/".
        mutating func pularComentario() {
            i += 2
            while i < n && !(b[i] == 0x2A && em(i + 1) == 0x2F) { i += 1 }
            i += 2
        }

        /// `i` está na aspa de abertura: copia o texto inteiro, com escapes.
        mutating func copiarTexto(_ aspa: UInt8) {
            saida.append(b[i])
            i += 1
            while i < n {
                let c = b[i]
                saida.append(c)
                i += 1
                if c == 0x5C && i < n {
                    saida.append(b[i])
                    i += 1
                } else if c == aspa {
                    return
                }
            }
        }

        /// `i` logo depois do "{": pula até o "}" que o fecha.
        mutating func pularBloco() {
            var prof = 1
            while i < n && prof > 0 {
                let c = b[i]
                if c == 0x2F && em(i + 1) == 0x2A {
                    pularComentario()
                } else if c == 0x22 || c == 0x27 {
                    i += 1
                    while i < n {
                        let d = b[i]
                        i += 1
                        if d == 0x5C {
                            i += 1
                        } else if d == c {
                            break
                        }
                    }
                } else {
                    if c == 0x7B { prof += 1 } else if c == 0x7D { prof -= 1 }
                    i += 1
                }
            }
        }

        mutating func rodar() -> String {
            while i < n {
                let c = b[i]
                if c == 0x2F && em(i + 1) == 0x2A {
                    pularComentario()
                    espaco = true
                    continue
                }
                if Enxugador.branco(c) {
                    espaco = true
                    i += 1
                    continue
                }
                if espaco {
                    if let ultimo = saida.last, ultimo != 0x7B, ultimo != 0x7D, ultimo != 0x3B {
                        saida.append(0x20)
                    }
                    espaco = false
                }
                if c == 0x22 || c == 0x27 {
                    copiarTexto(c)
                    continue
                }
                if c == 0x40, tentarDescartarRegra() {
                    espaco = true
                    continue
                }
                saida.append(c)
                i += 1
            }
            return String(decoding: saida, as: UTF8.self)
        }

        /// `i` está num "@". Se a regra não serve ao motor, pula ela inteira e devolve true.
        mutating func tentarDescartarRegra() -> Bool {
            var j = i + 1
            while j < n {
                let c = b[j]
                let letra = (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x2D
                if !letra { break }
                j += 1
            }
            let nome = String(decoding: b[(i + 1)..<j], as: UTF8.self).lowercased()

            // O prelúdio vai até "{" ou ";", sem contar o que está entre aspas.
            var k = j
            while k < n && b[k] != 0x7B && b[k] != 0x3B {
                if b[k] == 0x22 || b[k] == 0x27 {
                    let q = b[k]
                    k += 1
                    while k < n && b[k] != q {
                        if b[k] == 0x5C { k += 1 }
                        k += 1
                    }
                }
                k += 1
            }
            let fimPreludio = min(k, n)
            var jogar = PodaCSS.descartar.contains(nome)
            if !jogar && nome == "media" {
                let preludio = String(decoding: b[j..<fimPreludio], as: UTF8.self)
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                jogar = PodaCSS.apenasImpressao(preludio)
            }
            guard jogar else { return false }
            if k < n && b[k] == 0x7B {
                i = k + 1
                pularBloco()
            } else {
                i = k + 1
            }
            return true
        }
    }
}
