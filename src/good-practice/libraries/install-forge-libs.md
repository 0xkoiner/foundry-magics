# Install Forge Libraries with Custom Folder Names

By default `forge install` clones into `lib/<repo-name>`. You can override the folder name by prepending `<folder-name>=` before the GitHub path.

## Syntax

```bash
forge install <folder-name>=<github-org>/<repo>
```

This clones the repo into `lib/<folder-name>` instead of the default `lib/<repo>`.

## Why Use This

- **Version-pinned folders** — keep multiple versions side-by-side (`solady-v0.1.26`, `solady-v0.2.0`)
- **Cleaner remappings** — use descriptive names in `remappings.txt`
- **Avoid conflicts** — two forks of the same repo won't collide

## Examples

```bash
# Solady pinned to v0.1.26
forge install solady-v0.1.26=vectorized/solady

# OpenZeppelin Contracts v5.5.0
forge install openzeppelin-contracts-v5.5.0=OpenZeppelin/openzeppelin-contracts

# OpenZeppelin Upgradeable v5.5.0
forge install openzeppelin-contracts-upgradeable-v5.5.0=OpenZeppelin/openzeppelin-contracts-upgradeable
```

## Pin a Specific Tag

Add `@<tag>` to lock the version:

```bash
forge install solady-v0.1.26=vectorized/solady@v0.1.26
```

## Resulting `remappings.txt`

After install, update remappings to match the folder names:

```
solady-v0.1.26/=lib/solady-v0.1.26/src/
openzeppelin-contracts-v5.5.0/=lib/openzeppelin-contracts-v5.5.0/contracts/
```

source: https://getfoundry.sh/forge/reference/install#forge-install
