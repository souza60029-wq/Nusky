# Arquitetura do Nusky

## Visão geral

O Nusky é dividido em duas partes com uma fronteira clara entre elas:

```
┌──────────────────────────────┐
│  app/ (Swift + SwiftUI)      │  janela, abas, barra de endereço,
│                              │  rede (URLSession), desenho final
└──────────────┬───────────────┘
               │ chamada C (FFI)
┌──────────────▼───────────────┐
│  engine/ (Rust)              │  HTML → DOM → estilo → layout
│                              │  → lista de comandos de desenho
└──────────────────────────────┘
```

## Regras de dependência

- O **motor não conhece telas, UIKit ou SwiftUI.** Ele só recebe texto e devolve dados. Por isso, todos os testes rodam no Linux.
- A **casca nunca interpreta HTML ou CSS.** Ela apenas entrega o texto ao motor e desenha o que o motor devolve.
- A rede fica na casca. O motor recebe o conteúdo já baixado.

## Fluxo de dados

1. A casca baixa a página com `URLSession`.
2. O texto HTML é entregue ao motor.
3. O **parser** transforma o HTML numa árvore (DOM).
4. O **estilo** aplica as regras CSS a cada nó (no v0.1, valores padrão).
5. O **layout** calcula posição e tamanho de cada elemento.
6. O motor devolve uma **lista de comandos de desenho**: texto, posição, tamanho.
7. A casca desenha essa lista na tela.

## Decisões técnicas

| Área | Escolha | Motivo |
|---|---|---|
| Motor | Rust | Sem coletor de lixo, desempenho de C++, segurança de memória em tempo de compilação. |
| Casca | Swift + SwiftUI | Linguagem nativa, interface leve. |
| Desenho | Core Graphics e CoreText no v0.1 | Suficiente para conteúdo simples. |
| Desenho futuro | Metal | Entra quando medições mostrarem necessidade. |
| Rede | URLSession | Já vem no sistema, sem criptografia própria. |
| JavaScript | Adiado | Será o componente mais pesado. Com JIT via TrollStore, há opções futuras. |

## Princípio de otimização

Medir antes de otimizar. Nenhuma otimização entra sem uma medição que mostre o gargalo.

## Testes

- **Motor:** testes unitários com `cargo test`, rodando no Linux.
- **Casca:** testes manuais no iPhone 6s até existirem testes automatizados de interface.