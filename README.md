# Foundry Magics

This project is a focused knowledge base for experienced Solidity engineers who want sharper Foundry workflows, practical lifehacks, and opinionated good practices across the development cycle. The guides are concise, technical, and oriented toward real-world shipping.

## Contents

| Category | Guide | What it covers |
| --- | --- | --- |
| Bash Commands | [Foundry CLI quick starts](src/bash-commands/foundry.md) | Common `forge` init patterns and flags |
| Accounts | [GCP + Foundry](src/account/gcp.md) | Running scripts with GCP KMS-backed keys |
| Cheat Codes | [vm.etch deep dive](src/cheat-codes/vm.etch.md) | Runtime code vs creation code, and practical etch patterns |
| Cheat Codes | [stdStorage usage](src/cheat-codes/stdStorage.md) | Advanced storage writes in tests with fluent chaining |
| Good Practice / Deployment | [Deterministic deployment with CREATE2](src/good-practice/deployment/DeterministicDeployment.md) | EIP-2470 proxy flow and deterministic address mechanics |

## Scope

- Senior-level Solidity guidance: minimal hand-holding, maximum signal.
- Foundry-first workflows: scripts, testing, and deployment ergonomics.
- Practical tricks: things you actually use when shipping and debugging.
