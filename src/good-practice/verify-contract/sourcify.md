# Verify Deployed Contracts with Sourcify (Standard JSON Input)

Sourcify verifies by matching bytecode metadata. That means compiler version, optimizer settings, and metadata hash must match exactly. This guide shows how to pull or generate the Standard JSON Input and submit it to Sourcify.

## Path 1: Contract already verified on Etherscan

1. Open the lookup page:
   https://sourcify.dev/#/lookup
2. Search by address (example EntryPoint v0.9):
   https://sourcify.dev/#/lookup/0x433709009B8330FDa32311DF1C2AFA402eD8D009
3. If Sourcify has it, click "View in Sourcify Repository".
4. Open the repo entry for the chain id and address:
   https://repo.sourcify.dev/1/0x433709009B8330FDa32311DF1C2AFA402eD8D009
5. Scroll to "Standard JSON Input" and download the JSON.

You can reuse this JSON to verify the same contract on another chain or environment, as long as the deployed bytecode is identical.

## Path 2: Verified on Etherscan but missing on Sourcify

1. Go to https://verify.sourcify.dev/
2. Click "Import from Etherscan".
3. Provide your Etherscan API key and import.
4. Scroll to "Standard JSON Input" and download the JSON.

## Path 3: Generate Standard JSON Input with Foundry

Foundry can print the Standard JSON input for a deployed contract:
```bash
forge verify-contract \
  --show-standard-json-input \
  --chain <chain_id> \
  <deployed_address> \
  <path/to/Contract.sol:ContractName>
```

Use the output JSON with the Sourcify UI or API.

Reference:
https://getfoundry.sh/forge/reference/verify-contract#forge-verify-contract
