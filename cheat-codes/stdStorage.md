## ELI5: using stdStorage for StdStorage

Simple analogy: Think of it like giving a remote control (library functions) to a specific toy (struct type). Now the toy can use all the remote's buttons directly!

*What is using...for?*

The syntax using LibraryA for TypeB attaches library functions to a type, allowing you to call library functions as if they were methods of that type.

*Without using...for:*

```solidity
// You must call library functions explicitly
LibraryName.functionName(variable, args);
```

*With using...for:*

```solidity
using LibraryName for TypeName;

// Now you can call library functions like methods
variable.functionName(args);  // Much cleaner!
```

*Your Specific Case: using stdStorage for StdStorage*

```solidity
using stdStorage for StdStorage;
```
Translation: "Attach all functions from the stdStorage library to the StdStorage struct type."

*What are these?*

stdStorage = A library from forge-std with storage manipulation functions
StdStorage = A struct type that represents a storage operation

This is a Foundry testing utility that lets you read and write to any storage slot in any contract during tests.

### Real Example from Foundry Tests

*Let me show you how this works:*

Without using stdStorage for StdStorage:

```solidity
import {StdStorage, stdStorage} from "forge-std/Test.sol";

contract MyTest is Test {
    // Without "using...for"
    function test_ChangeBalance() public {
        address user = address(0x123);
        MyToken token = new MyToken();

        // Ugly: Must call library functions explicitly
        StdStorage storage slot = stdStorage
            .target(address(token))
            .sig("balanceOf(address)")
            .with_key(user);

        stdStorage.find(slot);  // Find the slot
        stdStorage.checked_write(slot, 1000);  // Write to it
    }
}
```

*With using stdStorage for StdStorage:*
```solidity
import {StdStorage, stdStorage} from "forge-std/Test.sol";

contract MyTest is Test {
    using stdStorage for StdStorage;  // ✅ Enable method-style calls

    function test_ChangeBalance() public {
        address user = address(0x123);
        MyToken token = new MyToken();

        // Clean: Call library functions as methods!
        stdStorage
            .target(address(token))
            .sig("balanceOf(address)")
            .with_key(user)
            .checked_write(1000);  // Much more readable!

        assertEq(token.balanceOf(user), 1000);
    }
}
```

### How using...for Works

The Pattern:
```solidity
// 1. Define a library with functions
library MathLib {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function multiply(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }
}

// 2. Attach library to a type
using MathLib for uint256;

// 3. Now you can call library functions as methods
function example() public {
    uint256 x = 5;

    // Without "using...for":
    uint256 result1 = MathLib.add(x, 3);  // MathLib.add(x, 3)

    // With "using...for":
    uint256 result2 = x.add(3);  // x.add(3) - looks like a method!

    // Both do the same thing, but method syntax is cleaner
}
```
> Much cleaner! The library functions are now called like methods on the stdStorage object.


*Important: First Parameter Becomes this*

When you use using LibraryA for TypeB:
```solidity
library StringLib {
    function toUpper(string memory str) internal pure returns (string memory) {
        // Convert to uppercase
    }
}

using StringLib for string;

// When you call:
string memory name = "hello";
string memory upper = name.toUpper();

// It's actually calling:
// StringLib.toUpper(name)
// The first parameter (string) becomes the "object"
```

### Common Patterns in Solidity

Pattern 1: String Utilities
```solidity
library StringUtils {
    function concat(string memory a, string memory b)
        internal pure returns (string memory)
    {
        return string(abi.encodePacked(a, b));
    }
}

using StringUtils for string;

function example() public {
    string memory greeting = "Hello".concat(" World");  // Clean!
}
```
Pattern 2: Array Operations
```solidity
library ArrayLib {
    function sum(uint256[] memory arr) internal pure returns (uint256) {
        uint256 total;
        for (uint256 i = 0; i < arr.length; i++) {
            total += arr[i];
        }
        return total;
    }
}

using ArrayLib for uint256[];

function example() public {
    uint256[] memory numbers = new uint256[](3);
    numbers[0] = 10;
    numbers[1] = 20;
    numbers[2] = 30;

    uint256 total = numbers.sum();  // Calling library function as method
    // total = 60
}
```
Pattern 3: forge-std stdStorage (Your Case)
```solidity
import {StdStorage, stdStorage} from "forge-std/Test.sol";

contract BenchmarkTest is Test {
    using stdStorage for StdStorage;  // Enable chaining methods

    function test_ManipulateStorage() public {
        MyContract target = new MyContract();

        // Chain library functions like methods
        stdStorage
            .target(address(target))
            .sig("owner()")
            .checked_write(address(0xdead));

        // Now target.owner() returns 0xdead!
        assertEq(target.owner(), address(0xdead));
    }
}
```

Scope of using...for

You can use it at different scopes:

Contract-level (Your Case):
```solidity
contract BenchmarkTest is Test {
    using stdStorage for StdStorage;  // Available in entire contract

    function test1() public {
        stdStorage.target(address(token));  // ✅ Works
    }

    function test2() public {
        stdStorage.target(address(nft));  // ✅ Works
    }
}
```

*File-level (Solidity 0.8.13+):*
```solidity
// At the top of the file, outside any contract
using stdStorage for StdStorage;

contract Test1 {
    function test() public {
        stdStorage.target(...);  // ✅ Works
    }
}

contract Test2 {
    function test() public {
        stdStorage.target(...);  // ✅ Works
    }
}
```

*Function-level:*
```solidity
function test() public {
    using MathLib for uint256;  // Only in this function

    uint256 x = 5;
    x.add(3);  // ✅ Works here
}

function test2() public {
    uint256 x = 5;
    x.add(3);  // ❌ Error: add not available here
}
```

*Benefits of using...for*

1. Cleaner syntax - Method-style calls are more readable
2. Chainable operations - Especially useful with builder patterns
3. Type safety - Compiler ensures you're using the right types
4. Code organization - Separate utility functions from main logic
5. Gas efficient - No overhead, just syntax sugar (internal library calls)

Real Example: Why It Matters

*Without using...for (Ugly):*
```solidity
function test() public {
    bytes32 slot = keccak256(abi.encode(user, 0));
    slot = stdStorage.find(
        stdStorage.with_key(
            stdStorage.sig(
                stdStorage.target(
                    StdStorage({/* init */}),
                    address(token)
                ),
                "balanceOf(address)"
            ),
            user
        )
    );
}
```

*With using...for (Clean):*
```solidity
using stdStorage for StdStorage;

function test() public {
    stdStorage
        .target(address(token))
        .sig("balanceOf(address)")
        .with_key(user)
        .find();  // Beautiful chaining!
}
```

### Key Takeaways

1. using LibraryA for TypeB = Attach library functions to a type
2. Method syntax = variable.function(args) instead of Library.function(variable, args)
3. No overhead = Pure syntax sugar, same bytecode as direct library calls
4. Your case = Enables clean storage manipulation in tests
5. Common in Foundry = using stdStorage for StdStorage is standard pattern

Bottom line: using stdStorage for StdStorage allows you to call storage manipulation functions like methods (stdStorage.target(...)) instead of library functions (stdStorage.target(stdStorage, ...)), making your test code much cleaner and more readable!


## Line-by-Line Explanation
```solidity
contract MyTest is Test {
    function test_ChangeBalance() public {
        // 1. Create a user address to test with
        address user = address(0x123);

        // 2. Deploy a new token contract
        MyToken token = new MyToken();

        // 3. Build a storage query using stdStorage
        StdStorage storage slot = stdStorage
            .target(address(token))      // Which contract?
            .sig("balanceOf(address)")   // Which storage variable?
            .with_key(user);             // Which mapping key?

        // 4. Find the actual storage slot number
        stdStorage.find(slot);

        // 5. Write value to that slot
        stdStorage.checked_write(slot, 1000);
    }
}
```
*Let me explain each part in detail:*

Understanding Each Method

1. .target(address) - Which Contract?

Purpose: Specifies which contract's storage you want to manipulate.

.target(address(token))

Translation: "I want to modify storage in the token contract"

2. .sig(string) - Which Storage Variable?

Purpose: Specifies the function signature to identify which storage variable you want to access.

.sig("balanceOf(address)")

Translation: "I want to access the storage that the balanceOf(address) function reads from"

*Why function signature? Because stdStorage works backwards:*
1. You tell it which getter function you want to affect
2. It figures out which storage slot that function reads from
3. It manipulates that slot directly

3. .with_key(value) - For Mappings, Which Key?

Purpose: For mappings, specifies the key to look up.

.with_key(user)

Translation: "In the mapping, use user as the key"

Example mapping:
```solidity
contract MyToken {
    mapping(address => uint256) public balanceOf;  // Storage slot 0

    // balanceOf(user) reads from: keccak256(abi.encode(user, 0))
}
```

*When you use .with_key(user), stdStorage will:*
1. Take the mapping's base slot (e.g., slot 0)
2. Hash it with the key: keccak256(abi.encode(user, 0))
3. That's the actual storage slot for balanceOf[user]

### Storage Slot Calculation: Manual vs stdStorage

Manual Way (Complex):
```solidity
contract MyToken {
    mapping(address => uint256) public balanceOf;  // Slot 0
}

function test_ManualSlotCalculation() public {
    MyToken token = new MyToken();
    address user = address(0x123);
    
    // 1. Calculate slot manually
    bytes32 slot = keccak256(abi.encode(
        user,    // Mapping key
        0        // Base slot number for balanceOf
    ));
    
    // 2. Write to slot directly
    vm.store(address(token), slot, bytes32(uint256(1000)));
    
    // 3. Verify
    assertEq(token.balanceOf(user), 1000);
}
```
Problems:
- ❌ You need to know the slot number (0 for balanceOf)
- ❌ You need to manually calculate keccak256 hash
- ❌ Easy to make mistakes
- ❌ Brittle - breaks if storage layout changes

*stdStorage Way (Easy):*
```solidity
using stdStorage for StdStorage;

function test_StdStorageWay() public {
    MyToken token = new MyToken();
    address user = address(0x123);
    
    // Just describe what you want!
    stdStorage
        .target(address(token))
        .sig("balanceOf(address)")
        .with_key(user)
        .checked_write(1000);

    assertEq(token.balanceOf(user), 1000);
}
```

Benefits:
- ✅ Don't need to know slot numbers
- ✅ stdStorage figures out the layout
- ✅ More readable and maintainable
- ✅ Less error-prone

### Complete Structure for Finding & Writing Slots

Structure 1: Simple Storage Variable
```solidity
contract Counter {
    uint256 public count;  // Slot 0
}

// Using stdStorage:
stdStorage
    .target(address(counter))
    .sig("count()")           // Getter function
    .checked_write(42);       // Write 42 to count

// Equivalent manual way:
vm.store(address(counter), bytes32(uint256(0)), bytes32(uint256(42)));
```
Structure 2: Mapping (Your Case)
```solidity
contract MyToken {
    mapping(address => uint256) public balanceOf;  // Slot 0
}

// Using stdStorage:
stdStorage
    .target(address(token))
    .sig("balanceOf(address)")
    .with_key(user)           // Specify mapping key
    .checked_write(1000);

// Equivalent manual way:
bytes32 slot = keccak256(abi.encode(user, 0));
vm.store(address(token), slot, bytes32(uint256(1000)));
```
Structure 3: Nested Mapping
```solidity
contract MyToken {
    // mapping(owner => mapping(spender => uint256))
    mapping(address => mapping(address => uint256)) public allowance;  // Slot 1
}

// Using stdStorage:
stdStorage
    .target(address(token))
    .sig("allowance(address,address)")
    .with_key(owner)          // First key
    .with_key(spender)        // Second key
    .checked_write(500);

// Equivalent manual way:
bytes32 slot1 = keccak256(abi.encode(owner, 1));
bytes32 slot2 = keccak256(abi.encode(spender, slot1));
vm.store(address(token), slot2, bytes32(uint256(500)));
```
Structure 4: Array
```solidity
contract MyContract {
    uint256[] public items;  // Slot 2
}

// Using stdStorage:
stdStorage
    .target(address(myContract))
    .sig("items(uint256)")
    .with_key(0)              // Index in array
    .checked_write(999);

// items[0] is now 999
```
Structure 5: Struct in Mapping
```solidity
contract UserRegistry {
    struct User {
        uint256 id;
        uint256 balance;
    }

    mapping(address => User) public users;  // Slot 0

    // Note: Solidity generates: users(address) returns (uint256 id, uint256 balance)
}

// To modify user.balance:
stdStorage
    .target(address(registry))
    .sig("users(address)")
    .with_key(userAddr)
    .depth(1)                 // 0 = id, 1 = balance (struct field index)
    .checked_write(5000);
```
### Methods Reference

Core Methods:

| Method                | Purpose            | Example                        |
|-----------------------|--------------------|--------------------------------|
| .target(address)      | Which contract     | .target(address(token))        |
| .sig(string)          | Function signature | .sig("balanceOf(address)")     |
| .with_key(value)      | Mapping key        | .with_key(user)                |
| .depth(uint256)       | Struct field index | .depth(1)                      |
| .checked_write(value) | Write & verify     | .checked_write(1000)           |
| .find()               | Get slot number    | bytes32 slot = .find()         |
| .read()               | Read current value | uint256 val = uint256(.read()) |

*Write Methods:*
```solidity
// checked_write: Writes and verifies the value was written correctly
stdStorage
    .target(address(token))
    .sig("balanceOf(address)")
    .with_key(user)
    .checked_write(1000);  // ✅ Safest - verifies write succeeded

// find() + vm.store: Manual control
bytes32 slot = stdStorage
    .target(address(token))
    .sig("balanceOf(address)")
    .with_key(user)
    .find();
vm.store(address(token), slot, bytes32(uint256(1000)));
```
*Why Not Use Slot Numbers Directly?*

Problem with Slot Numbers:
```solidity
contract MyToken {
    uint256 public totalSupply;                    // Slot 0
    mapping(address => uint256) public balanceOf;  // Slot 1
    mapping(address => mapping(address => uint256)) public allowance;  // Slot 2
}

// If you add a variable:
contract MyToken {
    address public owner;                          // Slot 0 ← NEW!
    uint256 public totalSupply;                    // Slot 1 ← CHANGED!
    mapping(address => uint256) public balanceOf;  // Slot 2 ← CHANGED!
    mapping(address => mapping(address => uint256)) public allowance;  // Slot 3 ← CHANGED!
}

// All your hardcoded slot numbers break! ❌
```
Benefits of stdStorage:
```solidity
// This works regardless of storage layout changes! ✅
stdStorage
    .target(address(token))
    .sig("balanceOf(address)")  // Finds the slot automatically
    .with_key(user)
    .checked_write(1000);
```
### Best Practices with stdStorage

✅ DO:

1. Use descriptive variable names when finding slots:
```solidity
// ✅ Clear what this represents
bytes32 balanceSlot = stdStorage
    .target(address(token))
    .sig("balanceOf(address)")
    .with_key(user)
    .find();
```
2. Use checked_write for safety:
```solidity
// ✅ Verifies the write succeeded
stdStorage
    .target(address(token))
    .sig("balanceOf(address)")
    .with_key(user)
    .checked_write(1000);
```
3. Chain operations for readability:
```solidity
// ✅ Clean and readable
stdStorage
    .target(address(token))
    .sig("balanceOf(address)")
    .with_key(user)
    .checked_write(1000);
```
4. Use for complex storage manipulation in tests:
```solidity
// ✅ Great for setting up test state
function test_TransferWithLargeBalance() public {
    stdStorage
        .target(address(token))
        .sig("balanceOf(address)")
        .with_key(alice)
        .checked_write(type(uint256).max);

    vm.prank(alice);
    token.transfer(bob, 1000);

    assertEq(token.balanceOf(bob), 1000);
}
```
❌ DON'T:

1. Don't use in production contracts:
// ❌ stdStorage is for TESTING only!
// Never use in production code

2. Don't hardcode slot numbers (use stdStorage instead):
// ❌ Brittle and breaks if storage changes
bytes32 slot = bytes32(uint256(1));
vm.store(address(token), slot, bytes32(uint256(1000)));

// ✅ Use stdStorage
stdStorage.target(address(token)).sig("balanceOf(address)").with_key(user).checked_write(1000);

3. Don't forget .with_key() for mappings:
// ❌ Missing with_key for mapping
stdStorage
    .target(address(token))
    .sig("balanceOf(address)")
    .checked_write(1000);  // Error!

// ✅ Include with_key
stdStorage
    .target(address(token))
    .sig("balanceOf(address)")
    .with_key(user)
    .checked_write(1000);

### Complete Working Example
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract MyToken {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function transfer(address to, uint256 amount) public {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

contract TokenTest is Test {
    using stdStorage for StdStorage;

    MyToken token;
    address alice = address(0x1);
    address bob = address(0x2);

    function setUp() public {
        token = new MyToken();
    }

    function test_StdStorageExamples() public {
        // Example 1: Write to mapping
        stdStorage
            .target(address(token))
            .sig("balanceOf(address)")
            .with_key(alice)
            .checked_write(1000 ether);

        assertEq(token.balanceOf(alice), 1000 ether);

        // Example 2: Write to simple variable
        stdStorage
            .target(address(token))
            .sig("totalSupply()")
            .checked_write(1000000 ether);

        assertEq(token.totalSupply(), 1000000 ether);

        // Example 3: Read current value
        uint256 currentBalance = uint256(
            stdStorage
                .target(address(token))
                .sig("balanceOf(address)")
                .with_key(alice)
                .read()
        );

        assertEq(currentBalance, 1000 ether);

        // Example 4: Find slot and use vm.store
        bytes32 bobBalanceSlot = stdStorage
            .target(address(token))
            .sig("balanceOf(address)")
            .with_key(bob)
            .find();

        vm.store(address(token), bobBalanceSlot, bytes32(uint256(500 ether)));
        assertEq(token.balanceOf(bob), 500 ether);
    }
}
```
Key Takeaways

1. .target() = Which contract to modify
2. .sig() = Which getter function (finds storage slot from this)
3. .with_key() = For mappings, which key to use
4. .checked_write() = Safest way to write (verifies success)
5. .find() = Get the actual slot number
6. Use stdStorage instead of manual slot calculation = More maintainable and less error-prone
7. Only for testing = Never use in production code

Bottom line: stdStorage abstracts away complex storage slot calculations, making your tests cleaner and more maintainable!

## stdStorage requires a PUBLIC or EXTERNAL function to work!

- ✅ Public - Works perfectly
- ✅ External - Works perfectly
- ⚠️ Internal - stdStorage won't work (no getter), but vm.store() will
- ⚠️ Private - stdStorage won't work (no getter), but vm.store() will
- ✅ View/Pure - These are about mutability, not visibility - they work fine with stdStorage

Why? The .sig() Method Needs a Callable Function

stdStorage works by:
1. Calling the function you specify in .sig()
2. Tracing which storage slot that function reads
3. Manipulating that slot directly

If there's no public getter, stdStorage can't call it!

Examples by Visibility

1. Public Variable (✅ Works)
```solidity
contract MyContract {
    uint256 public count;  // Auto-generates: function count() public view returns (uint256)
}

// ✅ Works - public getter exists
stdStorage
    .target(address(myContract))
    .sig("count()")  // Can call this!
    .checked_write(42);
```
2. Private Variable (❌ stdStorage Doesn't Work)
```solidity
contract MyContract {
    uint256 private count;  // No public getter!

    function getCount() public view returns (uint256) {
        return count;
    }
}

// ❌ This won't work - no count() getter
stdStorage
    .target(address(myContract))
    .sig("count()")  // Error! Function doesn't exist
    .checked_write(42);

// ⚠️ This might work if getCount() directly returns count
stdStorage
    .target(address(myContract))
    .sig("getCount()")  // Might work if it's simple enough
    .checked_write(42);

// ✅ But you can use vm.store directly!
bytes32 slot = bytes32(uint256(0));  // count is in slot 0
vm.store(address(myContract), slot, bytes32(uint256(42)));
```
3. Internal Variable (❌ stdStorage Doesn't Work)
```solidity
contract MyContract {
    uint256 internal count;  // No public getter

    function getCount() public view returns (uint256) {
        return count;
    }
}

// ❌ stdStorage won't work directly
// ✅ Use vm.store instead
vm.store(address(myContract), bytes32(uint256(0)), bytes32(uint256(42)));
```
4. View/Pure Functions (✅ Works)
```solidity
contract MyContract {
    uint256 public count;  // Generates: function count() public view returns (uint256)
}

// ✅ Works perfectly - view is about mutability, not visibility
stdStorage
    .target(address(myContract))
    .sig("count()")  // This is a view function, works fine!
    .checked_write(42);
```
Complete Test Exam*ple*
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract StorageExample {
    uint256 public publicVar = 1;      // Slot 0
    uint256 internal internalVar = 2;  // Slot 1
    uint256 private privateVar = 3;    // Slot 2

    mapping(address => uint256) public publicMapping;    // Slot 3
    mapping(address => uint256) internal internalMapping; // Slot 4
    mapping(address => uint256) private privateMapping;   // Slot 5

    // Getters for internal/private
    function getInternal() public view returns (uint256) {
        return internalVar;
    }

    function getPrivate() public view returns (uint256) {
        return privateVar;
    }

    function getInternalMapping(address key) public view returns (uint256) {
        return internalMapping[key];
    }
}

contract StorageVisibilityTest is Test {
    using stdStorage for StdStorage;

    StorageExample example;
    address user = address(0x123);

    function setUp() public {
        example = new StorageExample();
    }

    // ✅ Public variable - stdStorage works
    function test_PublicVariable() public {
        stdStorage
            .target(address(example))
            .sig("publicVar()")
            .checked_write(100);

        assertEq(example.publicVar(), 100);
    }

    // ❌ Internal variable - stdStorage doesn't work, use vm.store
    function test_InternalVariable() public {
        // This would fail:
        // stdStorage.target(address(example)).sig("internalVar()").checked_write(200);

        // ✅ Use vm.store instead
        bytes32 slot = bytes32(uint256(1));  // internalVar is in slot 1
        vm.store(address(example), slot, bytes32(uint256(200)));

        // Verify using the getter
        assertEq(example.getInternal(), 200);
    }

    // ❌ Private variable - stdStorage doesn't work, use vm.store
    function test_PrivateVariable() public {
        // ✅ Use vm.store
        bytes32 slot = bytes32(uint256(2));  // privateVar is in slot 2
        vm.store(address(example), slot, bytes32(uint256(300)));

        assertEq(example.getPrivate(), 300);
    }

    // ✅ Public mapping - stdStorage works
    function test_PublicMapping() public {
        stdStorage
            .target(address(example))
            .sig("publicMapping(address)")
            .with_key(user)
            .checked_write(1000);

        assertEq(example.publicMapping(user), 1000);
    }

    // ❌ Internal mapping - use vm.store
    function test_InternalMapping() public {
        // Calculate slot for mapping
        bytes32 slot = keccak256(abi.encode(user, 4));  // Slot 4 is internalMapping
        vm.store(address(example), slot, bytes32(uint256(2000)));

        assertEq(example.getInternalMapping(user), 2000);
    }

    // ❌ Private mapping - use vm.store
    function test_PrivateMapping() public {
        // Calculate slot for mapping
        bytes32 slot = keccak256(abi.encode(user, 5));  // Slot 5 is privateMapping
        vm.store(address(example), slot, bytes32(uint256(3000)));

        // Can verify by reading storage directly
        uint256 value = uint256(vm.load(address(example), slot));
        assertEq(value, 3000);
    }
}
```
### Finding Slot Numbers for Private/Internal Variables

Method 1: Use forge inspect

# Get storage layout
forge inspect MyContract storage-layout
```solidity
# Output shows slot numbers for all variables:
# {
#   "storage": [
#     {"label": "publicVar", "slot": "0", "type": "uint256"},
#     {"label": "internalVar", "slot": "1", "type": "uint256"},
#     {"label": "privateVar", "slot": "2", "type": "uint256"}
#   ]
# }
```
Method 2: Manual Calculation
```solidity
contract MyContract {
    uint256 public a;      // Slot 0
    uint256 internal b;    // Slot 1
    uint256 private c;     // Slot 2
    mapping(address => uint256) public d;     // Slot 3
    mapping(address => uint256) internal e;   // Slot 4
}

// Accessing internal variable b (slot 1):
vm.store(address(myContract), bytes32(uint256(1)), bytes32(uint256(newValue)));

// Accessing internal mapping e[user] (slot 4):
bytes32 slot = keccak256(abi.encode(user, 4));
vm.store(address(myContract), slot, bytes32(uint256(newValue)));
```
Method 3: Use vm.load() to Inspect
```solidity
function test_FindSlotNumber() public {
    MyContract c = new MyContract();
    
    // Read from slot 0
    bytes32 value0 = vm.load(address(c), bytes32(uint256(0)));
    console.log("Slot 0:", uint256(value0));
    
    // Read from slot 1  
    bytes32 value1 = vm.load(address(c), bytes32(uint256(1)));
    console.log("Slot 1:", uint256(value1));
    
    // Read from slot 2
    bytes32 value2 = vm.load(address(c), bytes32(uint256(2)));
    console.log("Slot 2:", uint256(value2));
}
```
*Workaround: Create Helper Getters for Testing*
```solidity
contract MyContract {
    uint256 private count;
    mapping(address => uint256) private balances;

    // Production code...

    // Test helpers (only in test builds or test contracts)
    function TEST_getCount() public view returns (uint256) {
        return count;
    }

    function TEST_getBalance(address user) public view returns (uint256) {
        return balances[user];
    }
}

// Now you can use stdStorage:
stdStorage
    .target(address(myContract))
    .sig("TEST_getCount()")  // ✅ Works!
    .checked_write(42);
```
Summary Table

| Visibility        | Has Public Getter? | stdStorage Works? | Alternative                                                  |
|-------------------|--------------------|-------------------|--------------------------------------------------------------|
| public            | ✅ Yes             | ✅ Yes            | -                                                            |
| external          | ✅ Yes             | ✅ Yes            | -                                                            |
| internal          | ❌ No              | ❌ No             | vm.store() + manual slot calculation                         |
| private           | ❌ No              | ❌ No             | vm.store() + manual slot calculation                         |
| view (mutability) | N/A                | ✅ Yes            | Works with any visibility that's public/external             |
| pure (mutability) | N/A                | ⚠️ Maybe          | Works only if function reads from storage despite being pure |

Best Practice Recommendations

✅ For Public/External Variables:

// Use stdStorage - clean and maintainable
stdStorage
    .target(address(contract))
    .sig("publicVar()")
    .checked_write(newValue);

✅ For Internal/Private Variables:

// Option 1: Use forge inspect to find slot
// forge inspect MyContract storage-layout

// Option 2: Calculate slot manually
bytes32 slot = bytes32(uint256(slotNumber));
vm.store(address(contract), slot, bytes32(uint256(newValue)));

// Option 3: Add test helper getters
// function TEST_getPrivateVar() public view returns (uint256) { return privateVar; }

✅ For Internal/Private Mappings:

// Calculate slot with keccak256
bytes32 slot = keccak256(abi.encode(key, baseSlot));
vm.store(address(contract), slot, bytes32(uint256(newValue)));

Key Takeaways

1. stdStorage needs a PUBLIC/EXTERNAL function to work with .sig()
2. Private/Internal variables don't have public getters, so stdStorage can't use them
3. Use vm.store() and vm.load() for private/internal storage manipulation
4. view/pure are about mutability, not visibility - they work fine if the function is public/external
5. Use forge inspect storage-layout to find slot numbers for private/internal variables
6. vm.store() works on ANY storage slot regardless of visibility - it's bytecode-level access

Bottom line: stdStorage is limited to public/external getters. For private/internal variables, you'll need to use vm.store() with manual slot calculation, but this still works perfectly fine!