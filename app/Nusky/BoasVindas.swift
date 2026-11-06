import SwiftUI
import UIKit

/// Versão atual dos termos. Se mudar, a tela de termos aparece de novo para todos.
let versaoDosTermos = "1.0"

/// Chaves guardadas só no aparelho.
enum ChavesTermos {
    static let versaoAceita = "termosVersaoAceita"
    static let dataAceite = "termosDataAceite"
}

/// Primeira abertura: três telas de apresentação e, depois, os termos.
struct BoasVindas: View {
    let aoAceitar: () -> Void

    @Environment(\.colorScheme) private var esquema
    @State private var etapa = 0

    private var escuro: Bool { esquema == .dark }
    private var texto: Color { escuro ? .white : .black }

    private let paginas: [PaginaApresentacao] = [
        PaginaApresentacao(
            icone: "BoasVindasLupa",
            simbolo: "magnifyingglass",
            titulo: "Bem-vindo ao Nusky",
            texto: "Um navegador leve para iPhone, feito para abrir sites com rapidez."
        ),
        PaginaApresentacao(
            icone: "BoasVindasLista",
            simbolo: "list.bullet",
            titulo: "Os sites são encontrados pelo nome",
            texto: "Ao pesquisar, o Nusky procura numa lista de endereços que já vem com o app. Não é uma busca na internet."
        ),
        PaginaApresentacao(
            icone: "BoasVindasAparelho",
            simbolo: "iphone",
            titulo: "Seus dados ficam no aparelho",
            texto: "Histórico e pesquisas ficam só no seu iPhone. Antes de continuar, leia os termos de uso."
        )
    ]

    var body: some View {
        ZStack {
            (escuro ? Color.black : Color.white).ignoresSafeArea()
            if etapa < paginas.count {
                apresentacao
            } else {
                TermosDeUso(aoAceitar: aoAceitar)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: etapa)
    }

    private var paginaAtual: PaginaApresentacao {
        paginas[min(etapa, paginas.count - 1)]
    }

    private var apresentacao: some View {
        VStack(spacing: 28) {
            Spacer()

            IconeDaTela(nome: paginaAtual.icone, simbolo: paginaAtual.simbolo, cor: texto)

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
                    Circle()
                        .fill(indice == etapa ? texto : texto.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            BotaoCapsula(titulo: "Avançar") {
                etapa += 1
            }
        }
        .padding(.bottom, 32)
    }
}

/// Texto e ícone de uma tela de apresentação.
private struct PaginaApresentacao {
    let icone: String
    let simbolo: String
    let titulo: String
    let texto: String
}

/// Usa o desenho do catálogo de imagens quando ele existe. Enquanto não existe, mostra um SF Symbol.
private struct IconeDaTela: View {
    let nome: String
    let simbolo: String
    let cor: Color

    var body: some View {
        Group {
            if UIImage(named: nome) != nil {
                Image(nome)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: simbolo)
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundColor(cor)
        .frame(width: 140, height: 140)
    }
}

/// Botão de cápsula usado nas telas de boas-vindas e nos termos.
private struct BotaoCapsula: View {
    let titulo: String
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Text(titulo)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }
}

/// Termos de uso. Com `aoAceitar`, mostra o botão "Li e aceito".
/// Sem ele (por exemplo, em Ajustes), mostra só o texto.
struct TermosDeUso: View {
    var aoAceitar: (() -> Void)? = nil

    @Environment(\.colorScheme) private var esquema
    private var texto: Color { esquema == .dark ? .white : .black }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Termos de Uso e Avisos do Nusky")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(texto)

                    ForEach(Array(clausulas.enumerated()), id: \.offset) { indice, clausula in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(indice + 1). \(clausula.titulo)")
                                .font(.system(size: 17, weight: .semibold))
                            Text(clausula.texto)
                                .font(.system(size: 16))
                        }
                        .foregroundColor(texto)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }

            if let aoAceitar = aoAceitar {
                BotaoCapsula(titulo: "Li e aceito", acao: aoAceitar)
                    .padding(.bottom, 24)
            }
        }
    }

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
            texto: "Histórico, pesquisas e sessões de navegação ficam somente no seu aparelho. Sessões são os dados que mantêm a página em que você estava. Cookies são pequenos arquivos que os sites guardam para reconhecer você. Eles também ficam no aparelho e são enviados apenas ao site que os criou, como em qualquer navegador. O Nusky não tem servidor próprio para receber dados e não envia esses dados a ninguém. O app também não tem cadastro, conta nem login."
        ),
        Clausula(
            titulo: "O que sai do aparelho",
            texto: "Ao abrir um site, o endereço IP do aparelho (o número que identifica sua conexão na internet) e o seu pedido chegam ao servidor desse site, como em qualquer acesso à internet. Ao procurar atualização da lista, o pedido chega ao GitHub, que pode ver o endereço IP. A operadora da rede, seja Wi-Fi ou dados móveis, também pode registrar a conexão. O Nusky não tem como impedir isso e não promete proteção de identidade."
        ),
        Clausula(
            titulo: "Atualização da lista",
            texto: "A lista só é atualizada quando você toca em \"Procurar atualização\", em Ajustes, e confirma. O app não verifica nada em segundo plano, isto é, sem que você peça. Se você não atualizar, o app continua usando a lista que já está no aparelho, que pode ficar desatualizada."
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
            texto: "Esta é a versão 1.0 dos termos, em vigor desde 5 de novembro de 2026, para o Nusky 0.0.2. Se este texto mudar, o app pedirá seu aceite de novo. Ao aceitar, o app guarda somente no aparelho a versão aceita e a data do aceite. Esse registro não é enviado a ninguém."
        )
    ]
}