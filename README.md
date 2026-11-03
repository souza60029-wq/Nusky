# Nusky

Navegador experimental para iOS com motor de renderização próprio, escrito em Rust.

**Versão:** 0.0.1
**Status:** protótipo funcional. Carrega páginas simples, segue links e tem interface básica. Ainda não funciona com a maioria dos sites.

## O que funciona hoje

- Baixar páginas por HTTP e HTTPS.
- Interpretar HTML: elementos, atributos, comentários e tags sem fechamento.
- Layout em blocos: títulos, parágrafos e texto em linha, com quebra por palavras.
- Links clicáveis, incluindo caminhos relativos.
- Barra de endereço retrátil: toque para expandir, teclado com a tecla Ir.
- Botões de recarregar e de configurações.
- Modo noturno e posição da barra (topo ou base), salvos entre aberturas.
- Testes automatizados do motor no Linux, pelo GitHub Actions.
- Compilação do motor para iPhone (`aarch64-apple-ios`) e geração do `.ipa`.

## Limitações conhecidas

- **Medição de texto estimada:** as quebras de linha podem diferir do Safari. Isso será corrigido com a medição real do CoreText.
- **Entidades HTML:** `&amp;`, `&nbsp;` e similares ainda aparecem como estão no texto (são decodificadas apenas em atributos).
- **Sem CSS:** cores, fontes, margens e posições usam valores fixos.
- **Sem JavaScript.**
- **Sem imagens, tabelas, formulários, flexbox ou grid.**
- **Sem histórico:** não há voltar nem avançar.
- **Sem abas, favoritos ou downloads.**

## Roadmap

- **0.0.2:** medição real de texto pelo CoreText e decodificação completa de entidades.
- **Próximos passos:** histórico (voltar e avançar), CSS básico (cor, fonte e margens) e imagens.
- **Bloqueio de anúncios e rastreadores:** implementado no próprio motor, já que o Nusky não usa WebKit.
- **JavaScript:** depois que o layout estiver estável. Com JIT via TrollStore, há opções para um interpretador rápido.
- **Metal:** entra apenas quando as medições mostrarem necessidade.

## Estrutura do repositório

```
engine/              motor em Rust (HTML, layout e interface C)
app/Nusky/           app iOS em Swift e SwiftUI
.github/workflows/   CI: testes do motor e build do app
project.yml          configuração do projeto Xcode (XcodeGen)
entitlements.plist   permissões de JIT para o TrollStore
```

## Como verificar

- **Motor:** `cargo test --manifest-path engine/Cargo.toml`, executado automaticamente a cada commit.
- **App:** o workflow **iOS** gera o `.ipa`, que é instalado no iPhone pelo TrollStore.

## Documentação

- [ARCHITECTURE.md](ARCHITECTURE.md): camadas, fluxo de dados e decisões técnicas.

## Versionamento

A versão só muda em marcos importantes. Enquanto estiver em 0.0.x, o projeto está em fase inicial e pode mudar de forma incompatível.

## Plataforma de teste

- iPhone 6s (chip A9, 2 GB de RAM)
- iOS 15.8.8
- TrollStore 2.1.1 (JIT habilitado)

## Licença

Copyright (c) 2026 S7y1_e

Este projeto é distribuído sob a [Mozilla Public License 2.0](LICENSE).