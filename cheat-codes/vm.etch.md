# ELI5: using vm.etch

## What is vm.etch?

**Function Signature (Foundry):**
```solidity
function etch(address who, bytes calldata code) external;
```

**What It Does:**

`vm.etch` is a Foundry cheat code that sets the bytecode at a specific address to your provided code. It directly manipulates the EVM state during testing, allowing you to place arbitrary bytecode at any address.

**Why It's Useful for Testing:**

1. **Mock External Contracts** - Replace production contracts with test mocks at known addresses
2. **Deterministic Addresses** - Deploy contracts to specific addresses across test environments
3. **Test Helper Contracts** - Replace contracts with versions that expose private variables
4. **Mock Precompiles** - Simulate custom precompiles (Blast, Arbitrum, etc.)
5. **Test EIP-7702** - Simulate EOAs with smart contract capabilities
6. **Fork Testing** - Replace mainnet contracts with mocks during fork tests

**IMPORTANT:** `vm.etch` is for testing only. It manipulates EVM state in ways that are impossible on real networks.

## Creation Code vs Runtime Code (Critical Concept)

Before using `vm.etch`, you must understand the difference between creation code and runtime code. This is **critical** because `vm.etch` expects **runtime code**, not creation code.

### The Two Types of Bytecode

**Creation Code (Init Code):**
- Code executed **only once** during deployment
- Contains constructor logic and constructor parameters
- Prepares the contract and returns runtime bytecode
- Uses `CODECOPY` to load runtime code into memory
- Uses `RETURN` to send runtime code back to EVM
- **Never stored on-chain**

**Runtime Code (Deployed Bytecode):**
- The actual code **stored on-chain** after deployment
- Contains all function logic for the contract
- Does **NOT** include constructor logic or parameters
- This is what the EVM executes when you call the contract
- **This is what `vm.etch` expects!**

### Visual Representation

```
┌─────────────────────────────────────────────────────────┐
│         Transaction Data During Deployment              │
├─────────────────┬─────────────────┬────────────────────┤
│  Creation Code  │  Runtime Code   │ Constructor Params │
│   (Init Code)   │ (Deployed Code) │                    │
├─────────────────┼─────────────────┼────────────────────┤
│  Runs once      │  Stored on-chain│  Used during init  │
│  during deploy  │  permanently    │  then discarded    │
└─────────────────┴─────────────────┴────────────────────┘
                       ↑
                This is what vm.etch needs!
```

### The Deployment Process

1. **Transaction sent** with full bytecode (creation + runtime + params)
2. **Creation code runs** (constructor executes)
3. **State initialized** (storage variables set)
4. **Immutables embedded** (placeholders replaced with values)
5. **Runtime code extracted** from creation code
6. **RETURN opcode sends** runtime code to EVM
7. **EVM stores** runtime code at contract address

**Key Insight:** The code you see when you call `address(contract).code` is the **runtime code**, not creation code.

### Why This Matters for vm.etch

```solidity
// ❌ WRONG - This is creation code (init + runtime)
bytes memory creationCode = type(MyContract).creationCode;
vm.etch(target, creationCode); // Will not work correctly!

// ✅ CORRECT - This is runtime code
MyContract deployed = new MyContract();
bytes memory runtimeCode = address(deployed).code;
vm.etch(target, runtimeCode); // Works!
```

## How to Extract Runtime Bytecode

There are two main methods to get runtime bytecode for use with `vm.etch`.

### Method 1: Using `.code` on Deployed Contract (Recommended)

**Syntax:**
```solidity
MyContract deployed = new MyContract(arg1, arg2);
bytes memory runtimeCode = address(deployed).code;
vm.etch(targetAddress, runtimeCode);
```

**How It Works:**
- Deploy the contract normally (constructor runs)
- Extract runtime code from the deployed instance
- Use with `vm.etch`


**Example:**
```solidity
contract Oracle {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function getPrice() public pure returns (uint256) {
        return 2000e18;
    }
}

function test_ExtractWithCode() public {
    address alice = address(0x1);

    // Deploy with specific owner
    Oracle oracle = new Oracle(alice);

    // Extract runtime code (owner is now hardcoded as alice)
    bytes memory code = address(oracle).code;

    // Deploy to different address
    address target = address(0x999);
    vm.etch(target, code);

    // Owner is preserved!
    assertEq(Oracle(target).owner(), alice);
}
```

### Method 2: Using `vm.getDeployedCode()` (For Undeployed Contracts)

**Syntax:**
```solidity
bytes memory code = vm.getDeployedCode("MyContract.sol:MyContract");
vm.etch(targetAddress, code);
```

**How It Works:**
- Reads compiled artifacts from the `out/` directory
- Returns runtime bytecode without deploying
- Requires filesystem permissions

**Configuration Required:**
```toml
# foundry.toml
[profile.default]
fs_permissions = [{ access = "read", path = "./out"}]
```

**Example:**
```solidity
contract SimpleStorage {
    uint256 public value;

    function setValue(uint256 _value) public {
        value = _value;
    }
}

function test_GetDeployedCode() public {
    // Get bytecode without deploying
    bytes memory code = vm.getDeployedCode("SimpleStorage.sol:SimpleStorage");

    // Etch to target
    address target = address(0x123);
    vm.etch(target, code);

    // Contract works, but value is 0 (default)
    SimpleStorage(target).setValue(42);
    assertEq(SimpleStorage(target).value(), 42);
}
```

### Method 3: Using `forge inspect` (Command Line)

**Command:**
```bash
# Get runtime bytecode (deployed bytecode)
forge inspect MyContract deployedBytecode

# Get creation bytecode (full deployment transaction data)
forge inspect MyContract bytecode
```

**For vm.etch, use:** `deployedBytecode`

This method is useful for understanding bytecode or copying it into scripts, but for tests, use Method 1 or 2.

### Comparison Table

| Method                | Constructor Runs? | Immutables Set? | Storage Initialized? | Best For                       |
|-----------------------|-------------------|-----------------|----------------------|--------------------------------|
| `.code` (Recommended) | ✅ Yes            | ✅ Yes          | ✅ Yes (not copied)  | Contracts with immutables      |
| `vm.getDeployedCode()`| ❌ No             | ❌ No (zeros)   | ❌ No                | Simple contracts, no immutables|
| `forge inspect`       | N/A               | N/A             | N/A                  | Manual inspection/documentation|

**Best Practice:** Use `.code` on deployed contracts (Method 1) unless you have a specific reason not to.

## Real Examples: Without vs With vm.etch

Let's see why `vm.etch` is valuable by comparing the old way vs the new way.

### Scenario: Testing a Contract That Uses an Oracle

You have a `PriceConsumer` contract that fetches prices from an oracle at a hardcoded address.

```solidity
contract PriceConsumer {
    Oracle public oracle;

    constructor(address _oracle) {
        oracle = Oracle(_oracle);
    }

    function isPriceAbove(uint256 threshold) public view returns (bool) {
        return oracle.getPrice() > threshold;
    }
}

contract Oracle {
    // Complex mainnet oracle logic
    function getPrice() public view returns (uint256) {
        // ... calls chainlink, reads storage, etc
    }
}
```

### Without vm.etch (Complex)

```solidity
function test_WithoutEtch() public {
    // ❌ Problem 1: Can't control oracle behavior easily
    Oracle oracle = new Oracle();

    // ❌ Problem 2: Can't mock at specific address
    // If consumer expects oracle at 0xOracleAddress, you're stuck

    // ❌ Problem 3: Have to modify production code
    // Add setOracle() just for testing

    // ❌ Problem 4: Complex setup for mainnet forks
    // Have to deal with real oracle state
}
```

### With vm.etch (Clean)

```solidity
contract MockOracle {
    uint256 public price;

    function setPrice(uint256 _price) public {
        price = _price;
    }

    function getPrice() public view returns (uint256) {
        return price;
    }
}

function test_WithEtch() public {
    // ✅ 1. Deploy mock with simple, controllable behavior
    MockOracle mock = new MockOracle();
    mock.setPrice(2000e18);

    // ✅ 2. Extract bytecode
    bytes memory mockCode = address(mock).code;

    // ✅ 3. Replace oracle at specific address
    address oracleAddress = address(0x999);
    vm.etch(oracleAddress, mockCode);

    // ✅ 4. Set storage (since storage isn't copied)
    vm.store(oracleAddress, bytes32(uint256(0)), bytes32(uint256(2000e18)));

    // ✅ 5. Test with full control
    PriceConsumer consumer = new PriceConsumer(oracleAddress);
    assertTrue(consumer.isPriceAbove(1500e18));
    assertFalse(consumer.isPriceAbove(2500e18));
}
```

## EIP-7702: Delegated EOAs (Comprehensive Section)

EIP-7702 is a proposed Ethereum improvement that allows Externally Owned Accounts (EOAs) to temporarily have smart contract capabilities. `vm.etch` is perfect for testing EIP-7702 behavior.


### The Magic Prefix: `0xef0100`

Instead of storing full contract code, EIP-7702 uses a **delegation designator**:

```
┌────────┬──────────────────────────────────┐
│ 0xef01 │    Implementation Address        │
│ 00     │         (20 bytes)               │
├────────┼──────────────────────────────────┤
│ 3 bytes│           20 bytes               │
└────────┴──────────────────────────────────┘
    ↑                    ↑
 Magic prefix    Where to delegate calls
```

**Total:** 23 bytes (3 + 20)

**Format:**
```solidity
bytes memory delegationCode = abi.encodePacked(
    hex"ef0100",                  // Magic prefix
    address(implementation)        // Implementation contract
);
```

### Testing EIP-7702 with vm.etch

#### Basic Example: Simple Delegation

```solidity
contract SimpleWallet {
    function executeBatch(address[] calldata targets, bytes[] calldata data)
        external
        returns (bytes[] memory results)
    {
        require(targets.length == data.length, "Length mismatch");
        results = new bytes[](targets.length);

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call(data[i]);
            require(success, "Call failed");
            results[i] = result;
        }

        return results;
    }
}

function test_EIP7702_BasicDelegation() public {
    // Create EOA
    address eoa = makeAddr("user");

    // Deploy implementation
    SimpleWallet impl = new SimpleWallet();

    // Set delegation code using vm.etch
    vm.etch(
        eoa,
        abi.encodePacked(hex"ef0100", address(impl))
    );

    // Verify delegation code is set correctly
    bytes memory code = eoa.code;
    assertEq(code.length, 23);  // 3 + 20 bytes

    // Verify prefix
    assertEq(uint8(code[0]), 0xef);
    assertEq(uint8(code[1]), 0x01);
    assertEq(uint8(code[2]), 0x00);

    // Extract and verify implementation address
    address storedImpl;
    assembly {
        storedImpl := mload(add(code, 23))  // Load last 20 bytes
    }
    assertEq(storedImpl, address(impl));

    // EOA can now execute batch transactions!
    vm.prank(eoa);
    address[] memory targets = new address[](2);
    bytes[] memory data = new bytes[](2);
    // ... set up batch call data ...
    SimpleWallet(eoa).executeBatch(targets, data);
}
```

### Testing Patterns for EIP-7702

**Pattern 1: Verify Delegation Code Format**
```solidity
function test_VerifyDelegationFormat() public {
    address eoa = makeAddr("user");
    address impl = address(new SimpleWallet());

    vm.etch(eoa, abi.encodePacked(hex"ef0100", impl));

    bytes memory code = eoa.code;

    // Verify length
    assertEq(code.length, 23);

    // Verify magic prefix
    bytes3 prefix;
    assembly {
        prefix := mload(add(code, 32))
    }
    assertEq(prefix, hex"ef0100");
}
```

**Pattern 2: Test Storage Isolation**
```solidity
function test_StorageIsolation() public {
    address eoa1 = makeAddr("user1");
    address eoa2 = makeAddr("user2");
    address impl = address(new StatefulWallet());

    // Both EOAs delegate to same implementation
    vm.etch(eoa1, abi.encodePacked(hex"ef0100", impl));
    vm.etch(eoa2, abi.encodePacked(hex"ef0100", impl));

    // Set storage for eoa1
    vm.prank(eoa1);
    StatefulWallet(eoa1).setValue(42);

    // eoa2 has independent storage
    vm.prank(eoa2);
    StatefulWallet(eoa2).setValue(99);

    // Verify isolation
    assertEq(StatefulWallet(eoa1).getValue(), 42);
    assertEq(StatefulWallet(eoa2).getValue(), 99);
}
```

**Pattern 3: Test Upgrade Path**
```solidity
function test_UpgradeImplementation() public {
    address eoa = makeAddr("user");

    // Start with v1
    WalletV1 implV1 = new WalletV1();
    vm.etch(eoa, abi.encodePacked(hex"ef0100", address(implV1)));

    // Use v1 features
    vm.prank(eoa);
    WalletV1(eoa).v1Function();

    // Upgrade to v2
    WalletV2 implV2 = new WalletV2();
    vm.etch(eoa, abi.encodePacked(hex"ef0100", address(implV2)));

    // Now has v2 features
    vm.prank(eoa);
    WalletV2(eoa).v2Function();
}
```