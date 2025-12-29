# Deterministic Deployment with CREATE2

Deterministic deployment uses CREATE2 to precompute a contract address from the deployer address, a salt, and the init code hash. When the same deployer contract is used across networks, the same salt and bytecode produce the same address, enabling cross-chain address parity and pre-authorized integrations.

This guide documents the deployment flow in `script/DeterministicDeployment.s.sol` and the use of the deterministic deployment proxy.

## Deterministic Deployment Proxy (EIP-2470)

The script uses the deterministic deployment proxy from Arachnid:
https://github.com/Arachnid/deterministic-deployment-proxy

Proxy address used in the script:
`0x4e59b44847b379578588920cA78FbF26c0B4956C`

This proxy is pre-deployed on many networks. Always verify it exists on the target chain before relying on deterministic addresses.

## CREATE2 Address Formula

CREATE2 computes the deployed address as:

```
address = keccak256(0xff ++ deployer ++ salt ++ keccak256(init_code))[12:]
```

The script uses:
```solidity
address expectedAddress = vm.computeCreate2Address(__SALT__, keccak256(creationCode), __CREATE2_DEPLOYER__);
```

## Script Flow

File: `script/DeterministicDeployment.s.sol`

1. Build init code: `creationCode = type(Counter).creationCode`.
2. Compute `expectedAddress` using CREATE2 and the proxy as the deployer.
3. Short-circuit if code already exists at `expectedAddress`.
4. Create deployment payload: `deploymentData = abi.encodePacked(__SALT__, creationCode)`.
5. Call the proxy with the payload and validate the returned address.
6. Assert code exists at the expected address after deployment.

The proxy call returns the deployed address in the response bytes; the script checks:
```solidity
require(address(bytes20(res)) == expectedAddress, "Wrong Addres Delpoyed");
```

## Constructor Arguments

If the target contract has constructor arguments, include them in the init code:
```solidity
bytes memory creationCode = abi.encodePacked(
    type(MyContract).creationCode,
    abi.encode(arg1, arg2)
);
```

Any change to init code (compiler version, metadata, constructor args) changes the deployed address.

## Running

Quick local run (Makefile target):
```
make deterministic-deployment
```

To broadcast on a network, add `--rpc-url` and `--broadcast`:
```
forge script ./script/DeterministicDeployment.s.sol --rpc-url <RPC_URL> --broadcast -vv
```
