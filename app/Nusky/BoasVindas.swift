import SwiftUI
import UIKit

/// Versão atual dos termos. Se mudar, a tela de termos aparece de novo para todos.
let versaoDosTermos = "1.1"

/// Chaves guardadas só no aparelho.
enum ChavesTermos {
    static let versaoAceita = "termosVersaoAceita"
    static let dataAceite = "termosDataAceite"
}

// MARK: - Boas-vindas

/// Primeira abertura: três telas de apresentação com ícones animados e, depois, os termos.
struct BoasVindas: View {
    let aoAceitar: () -> Void

    @Environment(\.colorScheme) private var esquema
    @State private var etapa = 0

    private var escuro: Bool { esquema == .dark }
    private var texto: Color { escuro ? .white : .black }

    private let paginas: [PaginaApresentacao] = [
        PaginaApresentacao(
            titulo: "Bem-vindo ao Nusky",
            texto: "Um navegador leve para iPhone, feito para abrir sites com rapidez."
        ),
        PaginaApresentacao(
            titulo: "Os sites são encontrados pelo nome",
            texto: "Ao pesquisar, o Nusky procura numa lista de endereços que já vem com o app. Não é uma busca na internet."
        ),
        PaginaApresentacao(
            titulo: "Seus dados ficam no aparelho",
            texto: "Histórico, favoritos e pesquisas ficam só no seu iPhone. Antes de continuar, leia os termos de uso."
        )
    ]

    var body: some View {
        ZStack {
            FundoColorido(escuro: escuro)
            if etapa < paginas.count {
                apresentacao
            } else {
                TermosDeUso(aoAceitar: aoAceitar)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: etapa)
    }

    private var paginaAtual: PaginaApresentacao {
        paginas[min(etapa, paginas.count - 1)]
    }

    private var apresentacao: some View {
        VStack(spacing: 28) {
            Spacer()

            iconeDaEtapa
                .frame(width: 190, height: 190)
                .id(etapa)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))

            VStack(spacing: 12) {
                Text(paginaAtual.titulo)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(texto)
                    .multilineTextAlignment(.center)
                Text(paginaAtual.texto)
                    .font(.system(size: 17))
                    .foregroundColor(texto.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<paginas.count, id: \.self) { indice in
                    Capsule()
                        .fill(indice == etapa ? texto : texto.opacity(0.3))
                        .frame(width: indice == etapa ? 22 : 8, height: 8)
                }
            }

            HStack(spacing: 12) {
                if etapa > 0 {
                    Button {
                        etapa -= 1
                    } label: {
                        Text("Voltar")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(texto)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(EstiloToque(forma: .capsula))
                }
                Button {
                    etapa += 1
                } label: {
                    HStack(spacing: 8) {
                        Text(etapa == paginas.count - 1 ? "Ler os termos" : "Avançar")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(texto)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Capsule())
                }
                .buttonStyle(EstiloToque(forma: .capsula))
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 32)
        .environment(\.colorScheme, esquema)
    }

    @ViewBuilder
    private var iconeDaEtapa: some View {
        switch etapa {
        case 0:
            IconeNuvem()
        case 1:
            IconeBusca(escuro: escuro)
        default:
            IconeCadeado(escuro: escuro)
        }
    }
}

/// Texto de uma tela de apresentação.
private struct PaginaApresentacao {
    let titulo: String
    let texto: String
}

// MARK: - Fundo e ícones animados

/// Fundo com manchas de cor que se movem devagar, para o vidro dos botões ter o que desfocar.
private struct FundoColorido: View {
    let escuro: Bool

    var body: some View {
        TimelineView(.animation) { contexto in
            let t = contexto.date.timeIntervalSinceReferenceDate
            ZStack {
                (escuro ? Color.black : Color.white)
                mancha(Color.blue, t, 0.0, x: 90, y: -190)
                mancha(Color.purple, t, 2.1, x: -110, y: 40)
                mancha(Color.teal, t, 4.2, x: 80, y: 250)
            }
        }
        .ignoresSafeArea()
    }

    private func mancha(_ cor: Color, _ t: Double, _ fase: Double, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(cor.opacity(escuro ? 0.42 : 0.3))
            .frame(width: 260, height: 260)
            .blur(radius: 60)
            .offset(x: x + CGFloat(sin(t * 0.35 + fase)) * 40, y: y + CGFloat(cos(t * 0.3 + fase)) * 40)
    }
}

/// A nuvem do Nusky flutuando, com a órbita girando e estrelas piscando.
/// A bolinha da órbita passa por trás da nuvem quando está na metade de trás do círculo.
private struct IconeNuvem: View {
    var body: some View {
        TimelineView(.animation) { contexto in
            let t = contexto.date.timeIntervalSinceReferenceDate
            let flutua = CGFloat(sin(t * 1.6)) * 8
            let angulo = t * 1.9
            let atras = sin(angulo) < 0
            ZStack {
                Ellipse()
                    .stroke(Color.yellow.opacity(0.9), lineWidth: 5)
                    .frame(width: 180, height: 50)
                    .offset(y: 18 + flutua)

                if atras {
                    bolinha(angulo, flutua)
                }

                nuvem
                    .offset(y: flutua)

                if !atras {
                    bolinha(angulo, flutua)
                }

                estrela(t, fase: 0).offset(x: -78, y: -70)
                estrela(t, fase: 1.7).offset(x: 80, y: -52)
                estrela(t, fase: 3.1).offset(x: 62, y: 74)
            }
        }
    }

    private func bolinha(_ angulo: Double, _ flutua: CGFloat) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 14, height: 14)
            .offset(x: CGFloat(cos(angulo)) * 90, y: 18 + flutua + CGFloat(sin(angulo)) * 25)
    }

    private var nuvem: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 64, height: 64).offset(x: -34, y: 4)
            Circle().fill(Color.white).frame(width: 84, height: 84).offset(x: 0, y: -14)
            Circle().fill(Color.white).frame(width: 62, height: 62).offset(x: 36, y: 6)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .frame(width: 140, height: 44)
                .offset(y: 16)
        }
        .shadow(color: Color.blue.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private func estrela(_ t: Double, fase: Double) -> some View {
        let brilho = 0.5 + 0.5 * sin(t * 3 + fase)
        return Image(systemName: "sparkle")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(Color.yellow)
            .opacity(0.35 + 0.65 * brilho)
            .scaleEffect(0.7 + 0.5 * CGFloat(brilho))
    }
}

/// Uma barra de busca digitando "com.nusky", com resultados que aparecem em seguida.
private struct IconeBusca: View {
    let escuro: Bool
    private let endereco = "com.nusky"

    var body: some View {
        TimelineView(.animation) { contexto in
            let t = contexto.date.timeIntervalSinceReferenceDate
            let ciclo = t.truncatingRemainder(dividingBy: 6.0)
            let letras = min(endereco.count, max(0, Int(ciclo * 3.0)))
            let digitado = String(endereco.prefix(letras))
            let mostrarCursor = Int(t * 2.5) % 2 == 0
            let resultados = letras >= 7

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .semibold))
                        .offset(x: CGFloat(sin(t * 3)) * 2)
                    Text(digitado + (mostrarCursor ? "|" : " "))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                    Spacer(minLength: 0)
                }
                .foregroundColor(escuro ? Color.white : Color.black)
                .padding(.horizontal, 18)
                .frame(width: 200, height: 54)
                .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5))

                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        linha(i, aparece: resultados)
                    }
                }
            }
        }
    }

    private func linha(_ i: Int, aparece: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color.accentColor.opacity(0.5)).frame(width: 18, height: 18)
            Capsule().fill(Color.primary.opacity(0.3)).frame(width: CGFloat(110 - i * 20), height: 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 180, height: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
        .opacity(aparece ? 1 : 0)
        .offset(y: aparece ? 0 : 10)
        .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.08), value: aparece)
    }
}

/// Um celular com um cadeado que fecha e abre, e ondas saindo dele.
private struct IconeCadeado: View {
    let escuro: Bool

    var body: some View {
        TimelineView(.animation) { contexto in
            let t = contexto.date.timeIntervalSinceReferenceDate
            let onda = CGFloat(t.truncatingRemainder(dividingBy: 2.4) / 2.4)
            // Fica fechado a maior parte do tempo e abre por um instante.
            let aberto = sin(t * 1.3) > 0.8
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(Double(1 - onda) * 0.6), lineWidth: 3)
                    .frame(width: 80 + onda * 110, height: 80 + onda * 110)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(escuro ? Color.white : Color.black, lineWidth: 5)
                    .frame(width: 96, height: 160)

                VStack(spacing: -2) {
                    // Argola do cadeado: as duas pernas ficam sempre; a da direita sobe quando abre.
                    Path { p in
                        p.move(to: CGPoint(x: 4, y: 36))
                        p.addLine(to: CGPoint(x: 4, y: 22))
                        p.addArc(center: CGPoint(x: 20, y: 22), radius: 16, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                        p.addLine(to: CGPoint(x: 36, y: aberto ? 26 : 36))
                    }
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .frame(width: 40, height: 40)
                    .offset(y: aberto ? -5 : 0)
                    .animation(.easeInOut(duration: 0.25), value: aberto)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green)
                        .frame(width: 52, height: 40)
                        .overlay(Circle().fill(Color.white).frame(width: 8, height: 8))
                }
            }
        }
    }
}

// MARK: - Termos

/// Termos de uso, em fonte com serifa. Com `aoAceitar` (primeira abertura), uma linha fina no pé da tela
/// se enche em 3 segundos, de ponta a ponta, e então sobe, se expande e vira o botão "Aceitar os termos".
/// Sem `aoAceitar` (por exemplo, em Ajustes), mostra só o texto.
struct TermosDeUso: View {
    var aoAceitar: (() -> Void)? = nil

    @Environment(\.colorScheme) private var esquema
    private var texto: Color { esquema == .dark ? .white : .black }

    /// Quanto da linha de espera já encheu (0 a 1).
    @State private var progresso: CGFloat = 0
    @State private var pronto = false

    private var fonteTitulo: Font { .system(size: 26, weight: .bold, design: .serif) }
    private var fonteClausula: Font { .system(size: 17, weight: .semibold, design: .serif) }
    private var fonteCorpo: Font { .system(size: 16, design: .serif) }

    var body: some View {
        ZStack(alignment: .bottom) {
            lista
            if aoAceitar != nil {
                rodape
            }
        }
        .onAppear { iniciarEspera() }
    }

    private var lista: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Termos de Uso e Avisos do Nusky")
                    .font(fonteTitulo)
                    .foregroundColor(texto)

                ForEach(Array(clausulas.enumerated()), id: \.offset) { indice, clausula in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(indice + 1). \(clausula.titulo)")
                            .font(fonteClausula)
                        Text(clausula.texto)
                            .font(fonteCorpo)
                    }
                    .foregroundColor(texto)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, aoAceitar != nil ? 110 : 24)
        }
    }

    /// A linha de espera e o botão são o mesmo elemento: a linha sobe, cresce e ganha o texto.
    private var rodape: some View {
        ZStack(alignment: .bottom) {
            // Linha de espera: uma faixa de ponta a ponta no pé da tela, que enche da esquerda para a direita.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(texto.opacity(0.15))
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * progresso)
                }
            }
            .frame(height: 4)
            .opacity(pronto ? 0 : 1)
            .ignoresSafeArea(edges: .bottom)

            Button {
                aoAceitar?()
            } label: {
                Text("Aceitar os termos")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(texto)
                    .frame(maxWidth: .infinity)
                    .frame(height: pronto ? 54 : 4)
                    .opacity(pronto ? 1 : 0)
                    .contentShape(Capsule())
            }
            .buttonStyle(EstiloToque(forma: .capsula))
            .padding(.horizontal, pronto ? 24 : 0)
            .padding(.bottom, pronto ? 28 : 0)
            .scaleEffect(x: 1, y: pronto ? 1 : 0.05, anchor: .bottom)
            .opacity(pronto ? 1 : 0)
            .disabled(!pronto)
        }
    }

    /// Enche a linha em 3 segundos e depois abre o botão.
    private func iniciarEspera() {
        guard aoAceitar != nil else { return }
        progresso = 0
        pronto = false
        withAnimation(.linear(duration: 3)) {
            progresso = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.05) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                pronto = true
            }
        }
    }

    // MARK: Cláusulas

    private struct Clausula {
        let titulo: String
        let texto: String
    }

    private let clausulas: [Clausula] = [
        Clausula(
            titulo: "O que é o Nusky",
            texto: "O Nusky é um navegador para iPhone, gratuito e de código aberto. Por enquanto, ele é distribuído apenas pelo GitHub, e não pela App Store. Ele abre sites de terceiros, isto é, sites feitos e mantidos por outras pessoas ou empresas. O Nusky não hospeda, não controla, não garante e não endossa (não apoia nem recomenda) o conteúdo desses sites. Ao abrir um site, sua relação é com esse site."
        ),
        Clausula(
            titulo: "Lista de endereços",
            texto: "O Nusky traz embutida uma lista de endereços de sites, usada para encontrar sites pelo nome. Não é uma busca na web. O app encontra sites apenas dentro dessa lista, que fica num repositório público no GitHub (um site onde se guarda e se publica código e dados). As indicações podem ser revisadas por pessoas antes de entrar na lista, mas podem conter erros, e nenhuma delas garante que um site seja seguro ou confiável. Você pode reportar erros pelo GitHub Issues, a área pública de avisos do repositório."
        ),
        Clausula(
            titulo: "Dados no aparelho",
            texto: "Histórico de visitas, favoritos, pesquisas, miniaturas das abas e sessões de navegação ficam somente no seu aparelho. Sessões são os dados que mantêm a página em que você estava. Cookies são pequenos arquivos que os sites guardam para reconhecer você. Eles também ficam no aparelho e são enviados apenas ao site que os criou, como em qualquer navegador. O Nusky não tem servidor próprio para receber dados e não envia esses dados a ninguém. O app também não tem cadastro, conta nem login. Em Ajustes, na aba Privacidade, você pode apagar o histórico de visitas, os cookies e o cache."
        ),
        Clausula(
            titulo: "O que sai do aparelho",
            texto: "Ao abrir um site, o endereço IP do aparelho (o número que identifica sua conexão na internet) e o seu pedido chegam ao servidor desse site, como em qualquer acesso à internet. O mesmo vale para as imagens e para o ícone do site: o Nusky os pede ao próprio site, inclusive o ícone de sites guardados nos favoritos e no histórico. Ao procurar atualização da lista ou do app, o pedido chega ao GitHub, que pode ver o endereço IP. A operadora da rede, seja Wi-Fi ou dados móveis, também pode registrar a conexão. O Nusky não tem como impedir isso e não promete proteção de identidade."
        ),
        Clausula(
            titulo: "JavaScript e imagens",
            texto: "O Nusky executa o JavaScript das páginas no próprio aparelho, por até 6 segundos, e baixa as imagens, reduzidas para economizar memória. Isso pode deixar o aparelho mais lento e gastar bateria e dados. Você pode desligar o JavaScript e as imagens em Ajustes, na aba Navegação. Sites que dependem de JavaScript podem abrir incompletos."
        ),
        Clausula(
            titulo: "Atualizações",
            texto: "A lista de sites só é atualizada quando você toca em \"Atualizar só a lista de sites\", em Ajustes, e confirma. O app só procura uma versão nova de si mesmo quando você toca em \"Atualizar o app\". Nesse caso, o Nusky consulta a última versão publicada no GitHub e entrega o arquivo de instalação ao TrollStore, que é outro app e faz a instalação. Atualizar o app também atualiza a lista de sites. O app não verifica nada em segundo plano, isto é, sem que você peça. Se você não atualizar, o app continua usando o que já está no aparelho, que pode ficar desatualizado."
        ),
        Clausula(
            titulo: "Responsabilidade do usuário",
            texto: "Você usa o Nusky por conta própria. Deve respeitar as leis brasileiras e os termos de uso de cada site que abrir, que são as regras que cada site define para quem o acessa. Você é responsável pelas suas senhas e contas, e também pelo que faz nos sites que visita."
        ),
        Clausula(
            titulo: "Garantias",
            texto: "O Nusky é fornecido \"como está\", ou seja, sem promessa de que vá funcionar sempre, sem interrupções ou falhas. Também não há garantia de que ele sirva para uma finalidade específica, na medida permitida pela lei. Nada neste texto limita os direitos que a lei brasileira garante ao consumidor, como os previstos no Código de Defesa do Consumidor (Lei 8.078/1990)."
        ),
        Clausula(
            titulo: "Código aberto",
            texto: "O código do Nusky é aberto e licenciado sob a MPL-2.0 (Mozilla Public License 2.0), uma licença que define como o código pode ser usado, estudado e compartilhado. Você pode consultar o código em https://github.com/souza60029-wq/Nusky. O texto da licença é que define essas regras, e este documento não as substitui."
        ),
        Clausula(
            titulo: "Contato",
            texto: "Responsável pelo projeto: S7y1_e, conta souza60029-wq no GitHub. Para dúvidas e assuntos de privacidade, escreva para nuskyofc@gmail.com. Mensagens enviadas a esse e-mail são lidas pelo responsável pelo projeto. Para erros do app e para sugestões ou denúncias de sites, use o GitHub Issues em https://github.com/souza60029-wq/Nusky. Tudo o que for publicado no GitHub Issues é público, e qualquer pessoa pode ler. Por isso, não envie dados pessoais desnecessários por e-mail e não os publique no GitHub."
        ),
        Clausula(
            titulo: "Versão e alterações",
            texto: "Esta é a versão 1.1 dos termos, em vigor desde 9 de novembro de 2026, para o Nusky 0.0.5. Se este texto mudar, o app pedirá seu aceite de novo. Ao aceitar, o app guarda somente no aparelho a versão aceita e a data do aceite. Esse registro não é enviado a ninguém."
        )
    ]
}
