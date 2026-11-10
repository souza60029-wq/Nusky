// app/Nusky/ListaAbas.swift
import SwiftUI
import UIKit

/// Tela de abas no estilo da tela de apps recentes do iOS: cartões grandes com a miniatura da página,
/// que se deslizam de lado.
struct ListaAbas: View {
    @ObservedObject var historico: Historico
    let fundoEscuro: Bool
    let onSelect: (UUID) -> Void
    let onNew: () -> Void
    let onDelete: (Set<UUID>) -> Void
    let onClose: () -> Void

    private var larguraTela: CGFloat { UIScreen.main.bounds.width }
    private var larguraCartao: CGFloat { larguraTela * 0.74 }
    private var alturaCartao: CGFloat { min(UIScreen.main.bounds.height * 0.6, larguraCartao * 1.6) }

    private var contagem: String {
        let n = historico.abas.count
        return n == 1 ? "1 aba" : "\(n) abas"
    }

    var body: some View {
        PainelVidro(titulo: "Abas", fundoEscuro: fundoEscuro, aoFechar: onClose) {
            VStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(historico.abas) { aba in
                            cartao(aba)
                        }
                    }
                    .padding(.horizontal, (larguraTela - larguraCartao) / 2)
                    .padding(.vertical, 10)
                }

                HStack {
                    Text(contagem)
                        .font(.system(size: 15, weight: .medium))
                        .opacity(0.7)
                    Spacer()
                    Button(action: onNew) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                            Text("Nova aba")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 46)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(EstiloToque(forma: .capsula))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private func cartao(_ aba: Aba) -> some View {
        let ativa = aba.id == historico.abaAtual.id
        let host = aba.entradaAtual?.host ?? ""

        return ZStack(alignment: .top) {
            miniatura(aba)
                .frame(width: larguraCartao, height: alturaCartao)
                .clipped()

            HStack(spacing: 8) {
                if !host.isEmpty {
                    IconeDoSite(host: host, tamanho: 24)
                }
                Text(host.isEmpty ? "Nova aba" : host)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    onDelete([aba.id])
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(EstiloToque(forma: .circulo))
                .accessibilityLabel("Fechar aba")
            }
            .padding(.horizontal, 10)
            .frame(width: larguraCartao, height: 46)
            .background(Rectangle().fill(.ultraThinMaterial))
        }
        .frame(width: larguraCartao, height: alturaCartao)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ativa ? Color.accentColor : (fundoEscuro ? Color.white.opacity(0.16) : Color.black.opacity(0.1)),
                        lineWidth: ativa ? 3 : 0.8)
        )
        .shadow(color: fundoEscuro ? Color.white.opacity(0.14) : Color.black.opacity(0.22), radius: 12, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { onSelect(aba.id) }
    }

    @ViewBuilder
    private func miniatura(_ aba: Aba) -> some View {
        if let imagem = MiniaturasAbas.compartilhada.imagem(para: aba.id) {
            Image(uiImage: imagem)
                .resizable()
                .scaledToFill()
                .frame(width: larguraCartao, height: alturaCartao, alignment: .top)
        } else {
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.08))
                Image(systemName: "globe")
                    .font(.system(size: 40, weight: .light))
                    .opacity(0.4)
            }
        }
    }
}
