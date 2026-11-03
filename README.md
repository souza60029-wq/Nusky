# Nusky

Navegador próprio para iOS, com motor escrito em Rust e casca em Swift/SwiftUI. Não usa WebKit.

Versão atual: **0.0.2**

## Objetivo

Um navegador leve e rápido para o iPhone 6s (chip A9, 2 GB de RAM, iOS 15.8.8), instalado via TrollStore. O motor é feito do zero: parser HTML, layout e desenho são escritos pelo próprio projeto.

## O que funciona hoje

- Parser HTML: tags, atributos, comentários, doctype, tags void e entidades nomeadas e numéricas.
- Layout de blocos verticais, com quebra de linha por palavras.
- Medição real de texto pelo CoreText, via callback do Swift, para quebras de linha parecidas com as do Safari.
- Links clicáveis, em azul e sublinhados. Links relativos são resolvidos pela URL final da página.
- Barra de endereço retrátil, com modo noturno e diurno e opção de posição (topo ou base).

## Limitações conhecidas

- Sem CSS: cores, fontes, margens e elementos com `display: none` são ignorados.
- Sem JavaScript.
- Sem imagens.
- Sem tabelas, formulários, flexbox ou grid.
- Sem histórico, abas ou downloads.
- Sites que o Safari do iPhone 6s não abre também não abrem aqui.

## Roadmap

Próximos passos, nesta ordem:

1. Histórico (voltar e avançar).
2. CSS básico: cor, fonte, margens e `display: none`.
3. Imagens.
4. Bloqueio de anúncios e rastreadores dentro do motor.
5. JavaScript, depois que o layout estiver estável (com JIT via TrollStore).
6. Metal, somente se as medições mostrarem gargalo.

## Estrutura do repositório

```
LICENSE
README.md
ARCHITECTURE.md
engine/          motor em Rust (parser, layout, FFI)
app/Nusky/       casca em Swift/SwiftUI
project.yml      geração do projeto Xcode (XcodeGen)
entitlements.plist
.github/workflows/   CI: testes do motor e build do app
```

## Como verificar

- **Testes do motor:** workflow `test-engine` (roda `cargo test` no Linux).
- **Build do app:** workflow `iOS` gera `Nusky-unsigned.ipa`, disponível como artifact na execução.
- **Instalação:** pelo TrollStore, no iPhone.

## Documentação

As decisões de arquitetura estão em [ARCHITECTURE.md](ARCHITECTURE.md).

## Versionamento

A versão só muda em marcos importantes.

- **0.0.1:** primeira versão funcional (parser, layout, links, ponte FFI).
- **0.0.2:** medição real de texto pelo CoreText e decodificação de entidades HTML.

## Plataforma de teste

- iPhone 6s, iOS 15.8.8
- TrollStore 2.1.1, com JIT habilitado

## Licença

Este projeto é licenciado sob a [Mozilla Public License 2.0](https://www.mozilla.org/MPL/2.0/).

Copyright (c) 2026 S7y1_e

O texto completo da licença está no arquivo LICENSE.