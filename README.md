# Nusky

Navegador para iPhone com motor próprio, escrito em Rust, e casca em Swift/SwiftUI. Não usa WebKit.

## Objetivo

Abrir páginas com velocidade e pouco uso de memória em aparelhos antigos, começando pelo iPhone 6s (chip A9, 2 GB de RAM, iOS 15.8.8). O app é instalado com TrollStore.

## O que funciona hoje (versão 0.0.3)

- Abrir endereços http e https, com links clicáveis e endereços com acento.
- HTML básico: parágrafos, títulos, listas, links e entidades HTML (nomeadas e numéricas).
- Medição de texto feita pelo CoreText do próprio aparelho.
- CSS básico: tamanho, negrito, margens, `display: none` e cor.
- CSS lido de tags `<style>`, de folhas externas (`<link rel="stylesheet">`) e dos atributos `style`, `id` e `class`.
- Seletores: tipo, classe, id, descendente, filho direto, `:not(...)` simples e listas separadas por vírgula. Pseudo-classes de interação (`:hover`, `:focus` e similares) nunca casam.
- Cor do CSS: a cor da página aparece quando há contraste suficiente. No modo noturno, só troca a cor quando o contraste fica baixo.
- Histórico em duas camadas por aba, com voltar e avançar. A rolagem de cada site é guardada.
- Abas em grade, com fechar, nova aba e seleção para apagar em lote.
- Barra de endereço que expande e retrai, em cima ou embaixo da tela, com botões ou gestos.
- Tela de carregamento com barra de progresso.
- Configurações: tema automático ou modo noturno, barra embaixo e botões na barra.

## Limitações conhecidas

- Sem JavaScript. Páginas que dependem dele mostram só o HTML inicial.
- Sem imagens.
- Sem suporte a `position`, `visibility` e `clip`.
- Seletores `[atributo]`, `+`, `~` e `:first-child` ainda não são suportados.
- Sites grandes ficam lentos e esquentam o aparelho.
- A barra de pesquisa só aceita endereço completo.
- Alguns sites ainda não abrem.
- Em fontes grandes, algumas palavras de título podem ser cortadas na borda.
- Sem bloqueio de anúncios.

## Roadmap

Sem ordem fixa:

- Seletores e propriedades restantes para esconder menus.
- Imagens, decodificadas no tamanho da tela e com `srcset` quando houver.
- Adaptador do YouTube.
- Virtualização completa da página.
- JavaScript, depois que o layout estiver estável.
- Metal, somente se as medições mostrarem gargalo.

## Estrutura

- `engine/`: motor em Rust (HTML, CSS, layout e ponte para a casca).
- `app/Nusky/`: casca em Swift/SwiftUI (tela, histórico, abas, configurações e download).
- `testes/`: páginas usadas para testar recursos no aparelho.
- `.github/workflows/`: builds automáticos no GitHub Actions.
- `project.yml`: configuração do projeto Xcode, gerada com XcodeGen.

## Como verificar

- Testes do motor: `cargo test --manifest-path engine/Cargo.toml`
- Build do app: o workflow `ios` gera o arquivo `Nusky-unsigned.ipa`, que pode ser instalado com TrollStore.

## Documentação

Detalhes de arquitetura estão em `ARCHITECTURE.md`.

## Versionamento

A versão sobe em marcos validados no aparelho. A versão atual é 0.0.3.

## Plataforma de teste

- iPhone 6s, iOS 15.8.8
- TrollStore 2.1.1, com JIT habilitado

## Licença

Este projeto é distribuído sob a Mozilla Public License 2.0. Veja o arquivo `LICENSE`.

Copyright (c) 2026 S7y1_e