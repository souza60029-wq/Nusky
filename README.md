# Nusky

Navegador para iPhone feito do zero. Ele não usa o motor de desenho do WebKit (o motor que o Safari usa): tem um motor próprio, escrito em Rust, que lê o HTML, aplica o CSS, calcula a posição de cada coisa e desenha a página. A tela do app é feita em Swift e SwiftUI.

## Objetivo

Abrir páginas com velocidade e pouco uso de memória em aparelhos antigos, começando pelo iPhone 6s (chip A9, 2 GB de RAM, iOS 15.8.8). O app é instalado com TrollStore. As prioridades são otimização, pouca memória, design e estabilidade.

## O que funciona hoje (versão 0.0.4)

**Páginas**

- Abrir endereços http e https, com links clicáveis. Digitar o nome de um site (a busca roda numa lista que fica no aparelho, tolera erro de digitação e não envia o que foi pesquisado).
- HTML: parágrafos, títulos, listas, tabelas, links, quebra de linha (`<br>`) e entidades.
- CSS lido de `<style>`, folhas externas e atributos `style`, `id` e `class`: tamanho, negrito, margens, preenchimento (padding), cor, cor de fundo, bordas, cantos arredondados, `text-align`, `display` (bloco, linha, flex), `flex-direction`, `gap`, `justify-content`, `width` e `height` (valores absolutos) e propriedades personalizadas (`--cor`, `var()`), com as classes reais do `<html>`.
- Caixas de fundo e cor de fundo da página. Flex em linha e em coluna; três ou mais filhos que não cabem lado a lado empilham.
- **Imagens (novo):** `<img>` baixa e desenha PNG, JPEG, GIF e WebP, inclusive `data:` e atributos de carregamento preguiçoso. A imagem é reduzida ao decodificar para gastar pouca memória. O espaço é reservado pelos atributos `width` e `height`, pelo CSS ou, sem eles, pelo tamanho natural da imagem. SVG ainda não é desenhado.
- **JavaScript:** o JavaScriptCore roda os scripts da página sobre um DOM próprio (árvore, seletores, eventos, temporizadores, `fetch`, armazenamento) e devolve o HTML final ao motor. Há limite de 6 segundos.
- Medição de texto feita pelo CoreText do próprio aparelho. O desenho é feito em blocos, só do que aparece na tela.

**App**

- **Barra nova (0.0.4):** uma pílula com o site. Ao tocar nela (área de toque maior que a pílula), ela se expande com mola, e a barra de ferramentas sai de trás dela ligada por um "chiclete" que estica. A barra fica sobre um fundo desfocado. Ela recolhe sozinha ao rolar a página, tocar na página, abrir uma ferramenta ou enviar um endereço, e só volta a abrir com um toque.
- Ao tocar no campo de endereço, o teclado sobe com o endereço todo selecionado: quem começa a digitar apaga o antigo. Enquanto digita, as ferramentas se guardam para dar espaço aos resultados.
- No campo de endereço fica só o botão de recarregar. As ferramentas são voltar, avançar (quando houver), abas, biblioteca, compartilhar e ajustes.
- Abas em grade, com fechar, nova aba e seleção para apagar em lote. Histórico por aba, com voltar e avançar, e a rolagem de cada site é guardada.
- **Biblioteca (novo):** favoritos e histórico de visitas, só no aparelho.
- **Compartilhar (novo):** a folha de compartilhamento do iOS.
- **Ajustes (novo):** tela com fundo desfocado e tópicos: Aparência, Navegação, Desempenho, Privacidade, Endereços e Sobre. A cor do texto segue a claridade do que está atrás: fundo escuro, texto branco; fundo claro, texto preto.
  - Aparência: tema automático ou noturno e barra em cima ou embaixo.
  - Navegação: versão desktop, mostrar imagens, executar JavaScript.
  - Desempenho: diagnóstico da página atual.
  - Privacidade: limpar histórico de visitas, cookies, cache e imagens guardadas.
  - Endereços: atualização manual da lista de sites, com confirmação.
- Diagnóstico embutido: mede a página, o JavaScript depois dos scripts e a memória, e gera um relatório de texto.
- Ícone novo.

## Limitações conhecidas

- Nem todo site abre: o Nusky não é um navegador completo. Cada site precisa ser provado no aparelho.
- Sem SVG, ícones vetoriais, campos de formulário desenhados, `position`, fontes próprias do site e fundo atrás de texto no meio da linha.
- Fileiras que rolam de lado viram uma lista vertical.
- `width` e `height` só valem para imagens, e só em valores absolutos.
- O JavaScript de páginas grandes usa centenas de MB e pode estourar o limite de 6 segundos.
- Sem bloqueio de anúncios.
- Anonimato não é prometido: o modo anônimo só será feito depois de medido.

## Roadmap

- 0.0.5: ChatGPT, Claude (login e carregamento) e Discord.
- 0.0.6: GitHub, YouTube e Pinterest.
- 0.1.0: sites principais abrindo, validados no aparelho; acabamento visual.
- Regras específicas por site em `dados/fixes.json`, com scripts externos e limite de tempo medido no iPhone 6s.
- Metal para desenhar, somente se a medição mostrar rolagem travando.
- Lista de sites maior, atalhos aprendidos só no aparelho e economia de memória nas abas paradas.

As regras do motor são gerais. Nada de nome de site ou de framework no código do motor: o que for específico de um site vai em `dados/`.

## Estrutura

- `engine/`: motor em Rust (HTML, CSS, layout e ponte para a casca).
- `app/Nusky/`: casca em Swift e SwiftUI (barra, ajustes, abas, biblioteca, imagens, JavaScript e download).
- `dados/`: lista de sites para a busca por nome.
- `testes/`: páginas usadas para testar recursos no aparelho.
- `.github/workflows/`: builds automáticos no GitHub Actions.
- `project.yml`: configuração do projeto Xcode, gerada com XcodeGen.

## Como verificar

- Testes do motor: `cargo test --manifest-path engine/Cargo.toml`
- Build do app: o workflow `ios` gera o arquivo `Nusky-unsigned.ipa`, que pode ser instalado com TrollStore.

## Documentação

Detalhes de arquitetura estão em `ARCHITECTURE.md`.

## Versionamento

A versão sobe em marcos validados no iPhone. As três versões (`engine/Cargo.toml` e `project.yml`, com o build) sobem juntas, num commit só. A versão atual é 0.0.4.

## Plataforma de teste

- iPhone 6s, iOS 15.8.8
- TrollStore 2.1.1, com JIT habilitado

## Licença

Este projeto é distribuído sob a Mozilla Public License 2.0. Veja o arquivo `LICENSE`.

Copyright (c) 2026 S7y1_e