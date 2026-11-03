# Nusky

Navegador experimental para iOS com motor de renderização próprio, escrito em Rust.

**Status:** fase de arquitetura (v0.0). Ainda não há navegação real.

## Objetivo

Construir um navegador leve, rápido e estável para hardware antigo, começando por páginas simples e crescendo em compatibilidade de forma medida.

## Escopo do v0.1

- Receber uma string com HTML simples (títulos e parágrafos).
- Produzir uma lista de comandos de desenho (texto, posição, tamanho).
- Testes automatizados rodando no Linux via GitHub Actions.
- Casca iOS mostrando essa lista na tela.

## Fora de escopo por enquanto

- JavaScript
- Flexbox e grid
- Compatibilidade com sites reais
- Metal (entra depois que medirmos um gargalo real)

## Documentação

- [ARCHITECTURE.md](ARCHITECTURE.md): camadas, fluxo de dados e decisões técnicas.

## Plataforma de teste

- iPhone 6s (chip A9, 2 GB de RAM)
- iOS 15.8.8
- TrollStore 2.1.1 (JIT habilitado)

## Licença

Copyright (c) 2026 S7y1_e

Este projeto é distribuído sob a [Mozilla Public License 2.0](LICENSE).