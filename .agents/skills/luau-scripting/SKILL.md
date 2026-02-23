---
name: luau-scripting
description: Luau scripting conventions and validation workflow for this project. Use when creating, editing, reviewing, or refactoring Luau scripts.
---

# Luau Scripting

## Core Rules

- Do not change existing coding style unless the user explicitly requests it.
- Do not rewrite `if-then-else` into ternary-style patterns.
- Do not add `pairs` to `for i, v in t do` loops without explicit instruction.
- Reuse existing shared utilities instead of creating new local helpers for the same purpose.

## Comments

- Write comments in Korean.
- Add a block comment above each module that explains the module.

## Output And Branching

- Write output strings in English.
- Avoid overusing `assert` and `error`.
- Do not add type-validation branches (`if`, `typeof`) unless explicitly requested.
