// app/Nusky/ListaAbas.swift
import SwiftUI
import UIKit

/// Tela de abas: uma grade de cartões simples, cada um só com o ícone do site e o nome.
struct ListaAbas: View {
    @ObservedObject var historico: Historico
    let fundoEscuro: Bool
    let onSelect: (UUID) -> Void
    let onNew: () -> Void
    let onDelete: (Set<UUID>) -> Void
    let onClose: () -> Void

    private let colunas = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var contagem: String {
        let n = historico.abas.count
        return n == 1 ? "1 aba" : "\(n) abas"
    }

    var body: some View {
        PainelVidro(titulo: "Abas", fundoEscuro: fundoEscuro, aoFechar: onClose) {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: colunas, spacing: 14) {
                        ForEach(historico.abas) { aba in
                            cartao(aba)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
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
                .padding(.vertical, 14)
            }
        }
    }

    private func cartao(_ aba: Aba) -> some View {
        let ativa = aba.id == historico.abaAtual.id
        let host = aba.entradaAtual?.host ?? ""

        return ZStack(alignment: .topTrailing) {
            Button {
                onSelect(aba.id)
            } label: {
                VStack(spacing: 12) {
                    if host.isEmpty {
                        Image(systemName: "globe")
                            .font(.system(size: 34, weight: .light))
                            .frame(width: 64, height: 64)
                            .opacity(0.6)
                    } else {
                        IconeDoSite(host: host, tamanho: 64)
                    }
                    Text(host.isEmpty ? "Nova aba" : host)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 152)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(EstiloToque(forma: .retangulo(24)))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: ativa ? 2.5 : 0)
                    .allowsHitTesting(false)
            )

            Button {
                onDelete([aba.id])
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .opacity(0.7)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar aba")
        }
    }
}
