# Bash Commands for Foundry

## Init Project

```bash
# Initialize new Foundry project with sample contracts
# Creates: src/Counter.sol, script/Counter.s.sol, test/Counter.t.sol
forge init
```

```bash
# Initialize in non-empty directory
forge init --force
```

```bash
# Initialize without sample contracts (src/Counter.sol, script/Counter.s.sol, test/Counter.t.sol)
forge init --empty
```