# Solady ERC20 Deep Dive

Source: `lib/solady-v0.1.26/src/tokens/ERC20.sol`

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture at a Glance](#2-architecture-at-a-glance)
3. [The 3 Big Design Decisions](#3-the-3-big-design-decisions)
4. [Function Map](#4-function-map)
5. [Gas Tricks Summary](#5-gas-tricks-summary)
6. [Storage Layout Deep Dive](#6-storage-layout-deep-dive)
   - 6.3 [Why These Specific Seed Values?](#63-why-these-specific-seed-values)
7. [Slot Computation: Byte-by-Byte](#7-slot-computation-byte-by-byte)
8. [The or() Optimization](#8-the-or-optimization)
9. [Replicating Slot Computation in Solidity/Chisel](#9-replicating-slot-computation-in-soliditychisel)
10. [Comparison: Solidity vs Solady](#10-comparison-solidity-vs-solady)
11. [Collision Safety](#11-collision-safety)
12. [Advanced Assembly Tricks Deep Dive](#12-advanced-assembly-tricks-deep-dive)

---

## Address Convention

Throughout this document:

```
owner   = 0xcafebabecafebabecafebabecafebabecafebabe
spender = 0xdeadbeafdeadbeafdeadbeafdeadbeafdeadbeaf
```

---

## 1. Introduction

This is Vectorized's gas-optimized ERC20 implementation — the most gas-efficient ERC20 in production today. It implements the standard ERC20 interface plus EIP-2612 (gasless approvals via permit) and native Permit2 integration, all written almost entirely in inline assembly.

---

## 2. Architecture at a Glance

```
  ┌──────────────────────────────────────────────────────────┐
  │                   Solady ERC20 (abstract)                │
  ├──────────────────────────────────────────────────────────┤
  │                                                          │
  │  CUSTOM ERRORS (L26-48)                                  │
  │    7 custom errors — 4-byte selectors, no strings        │
  │    (saves ~2000+ gas per revert vs require(... "msg"))   │
  │                                                          │
  │  EVENTS (L54-66)                                         │
  │    Transfer, Approval — pre-computed topic hashes        │
  │    stored as constants to avoid runtime keccak256        │
  │                                                          │
  │  STORAGE (L72-98)                                        │
  │    NO state variables declared!                          │
  │    All storage is accessed via hand-crafted slot seeds:  │
  │    • _TOTAL_SUPPLY_SLOT    → fixed slot for supply       │
  │    • _BALANCE_SLOT_SEED    → seed to derive balance map  │
  │    • _ALLOWANCE_SLOT_SEED  → seed to derive allowance    │
  │    • _NONCES_SLOT_SEED     → seed to derive permit nonce │
  │                                                          │
  │  CONSTANTS (L104-125)                                    │
  │    EIP-712 domain typehash, permit typehash,             │
  │    default version hash, Permit2 canonical address       │
  │                                                          │
  │  ERC20 METADATA (L131-140)                               │
  │    name(), symbol() → abstract (you implement)           │
  │    decimals() → returns 18                               │
  │                                                          │
  │  ERC20 CORE (L146-347)                                   │
  │    totalSupply, balanceOf, allowance,                    │
  │    approve, transfer, transferFrom                       │
  │                                                          │
  │  EIP-2612 PERMIT (L353-487)                              │
  │    permit(), nonces(), DOMAIN_SEPARATOR()                │
  │    Full gasless approval with ecrecover                  │
  │                                                          │
  │  INTERNAL MINT/BURN (L496-552)                           │
  │    _mint(), _burn()                                      │
  │                                                          │
  │  INTERNAL TRANSFER/ALLOWANCE (L558-644)                  │
  │    _transfer(), _spendAllowance(), _approve()            │
  │                                                          │
  │  HOOKS (L650-656)                                        │
  │    _beforeTokenTransfer(), _afterTokenTransfer()         │
  │    Empty by default — override for custom logic          │
  │                                                          │
  │  PERMIT2 (L667-669)                                      │
  │    _givePermit2InfiniteAllowance() → true by default     │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
```

---

## 3. The 3 Big Design Decisions

### 1. No State Variables — Custom Storage Layout

Solidity normally assigns storage slots sequentially (slot 0, 1, 2...). Solady skips this entirely. Instead, it uses magic
seed constants to compute storage slots via keccak256:

```
balanceOf[owner]     → keccak256(owner . 0x00000000 00000000 . 0x87a211a2)
allowance[owner][sp] → keccak256(owner . 0x00000000 00000000 . 0x7f5e9f20 . spender)
nonces[owner]        → keccak256(owner . 0x00000000 00000000 . 0x38377508)
totalSupply          → fixed at slot 0x05345cdf77eb68f44c
```

Why? This avoids Solidity's mapping overhead (extra hashing, zero-padding to 32 bytes). Vectorized packs the address + seed
into fewer bytes before hashing, saving gas on every keccak256.

### 2. Everything Is Assembly

Every function body is `assembly { ... }`. This gives Vectorized:
- No ABI encoding overhead — calldata/memory is managed manually
- No redundant checks — Solidity adds overflow checks, zero-address checks, etc. that ERC20 doesn't need
- Precise memory control — heavy use of scratch space (0x00-0x3f) instead of allocating new memory
- Optimal event emission — log3 called directly with pre-computed topics

### 3. Native Permit2 Integration

The contract treats Uniswap's Permit2 (`0x000000000022D473030F116dDEE9F6B43aC78BA3`) as a first-class citizen:
- `allowance()` returns `type(uint256).max` for Permit2 without an sload
- `transferFrom()` skips the allowance check entirely when `caller() == _PERMIT2`
- `approve()` and `permit()` revert if you try to set Permit2's allowance to anything other than max
- All controlled by `_givePermit2InfiniteAllowance()` — override to return false to disable

---

## 4. Function Map

```
  ┌─────────────────────────────────┬─────────────┬───────────┬──────────────────────────────────────────────────────────┐
  │            Function             │ Visibility  │ Assembly? │                       What It Does                       │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ totalSupply()                   │ public view │ Yes       │ Single sload from fixed slot                             │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ balanceOf(owner)                │ public view │ Yes       │ Compute slot from seed, sload                            │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ allowance(owner, sp)            │ public view │ Yes       │ Permit2 shortcut + seed-based sload                      │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ approve(sp, amt)                │ public      │ Yes       │ sstore allowance + emit Approval                         │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ transfer(to, amt)               │ public      │ Yes       │ Subtract sender, add receiver, emit Transfer             │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ transferFrom(from, to, amt)     │ public      │ Yes       │ Check allowance, transfer, 2 code paths (Permit2 on/off) │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ permit(...)                     │ public      │ Yes       │ EIP-2612: verify signature, set allowance                │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ DOMAIN_SEPARATOR()              │ public view │ Yes       │ Compute EIP-712 domain hash                              │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ nonces(owner)                   │ public view │ Yes       │ Read nonce from seed-based slot                          │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ _mint(to, amt)                  │ internal    │ Yes       │ Increase supply + balance, emit Transfer(0, to)          │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ _burn(from, amt)                │ internal    │ Yes       │ Decrease balance + supply, emit Transfer(from, 0)        │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ _transfer(from, to, amt)        │ internal    │ Yes       │ Move tokens between accounts                             │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ _approve(owner, sp, amt)        │ internal    │ Yes       │ Set allowance + emit Approval                            │
  ├─────────────────────────────────┼─────────────┼───────────┼──────────────────────────────────────────────────────────┤
  │ _spendAllowance(owner, sp, amt) │ internal    │ Yes       │ Deduct from allowance (skip if max)                      │
  └─────────────────────────────────┴─────────────┴───────────┴──────────────────────────────────────────────────────────┘
```

---

## 5. Gas Tricks Summary

```
  ┌───────────────────────────────────────────────┬─────────────────┬──────────────────────────────────┐
  │                     Trick                     │      Where      │             Savings              │
  ├───────────────────────────────────────────────┼─────────────────┼──────────────────────────────────┤
  │ Custom errors (4 bytes, no strings)           │ All reverts     │ ~2000+ gas per revert            │
  ├───────────────────────────────────────────────┼─────────────────┼──────────────────────────────────┤
  │ Pre-computed event topic hashes               │ All events      │ ~30 gas per emit                 │
  ├───────────────────────────────────────────────┼─────────────────┼──────────────────────────────────┤
  │ Scratch space (0x00-0x3f) for hashing         │ Everywhere      │ Avoids memory expansion          │
  ├───────────────────────────────────────────────┼─────────────────┼──────────────────────────────────┤
  │ shr(96, shl(96, addr)) for address cleaning   │ permit, approve │ Cheaper than and(addr, 0xff..ff) │
  ├───────────────────────────────────────────────┼─────────────────┼──────────────────────────────────┤
  │ if not(allowance_) to skip max allowance      │ transferFrom    │ Saves sstore on infinite approve │
  ├───────────────────────────────────────────────┼─────────────────┼──────────────────────────────────┤
  │ Duplicated code paths for Permit2 on/off      │ transferFrom    │ Zero-cost abstraction at runtime │
  ├───────────────────────────────────────────────┼─────────────────┼──────────────────────────────────┤
  │ Seed-based slot computation with or() packing │ Storage access  │ Fewer bytes hashed in keccak256  │
  └───────────────────────────────────────────────┴─────────────────┴──────────────────────────────────┘
```

---

## 6. Storage Layout Deep Dive

### 6.1 Constants

```solidity
uint256 private constant _TOTAL_SUPPLY_SLOT    = 0x05345cdf77eb68f44c;  // 9 bytes — fixed slot
uint256 private constant _BALANCE_SLOT_SEED    = 0x87a211a2;            // 4 bytes — mapping seed
uint256 private constant _ALLOWANCE_SLOT_SEED  = 0x7f5e9f20;            // 4 bytes — mapping seed
uint256 private constant _NONCES_SLOT_SEED     = 0x38377508;            // 4 bytes — mapping seed
```

These are not storage slots — they're ingredients for computing slots. Constants live in bytecode, not storage. They cost 0
gas to access (they're inlined at compile time).

### 6.2 Storage Map

```
  ╔══════════════════════════════════════════════════════════════════════╗
  ║                    SOLADY ERC20 STORAGE MAP                         ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                     ║
  ║  TOTAL SUPPLY                                                       ║
  ║  ┌─────────────────────────────────────────────────────────────┐    ║
  ║  │ Slot: 0x05345cdf77eb68f44c  (fixed, no hashing)             │    ║
  ║  │ Value: uint256 totalSupply                                  │    ║
  ║  │ Access: sload(0x05345cdf77eb68f44c)                         │    ║
  ║  └─────────────────────────────────────────────────────────────┘    ║
  ║                                                                     ║
  ║  BALANCES — mapping(address => uint256)                             ║
  ║  ┌─────────────────────────────────────────────────────────────┐    ║
  ║  │ Slot: keccak256(owner . 0x00000000 00000000 . 0x87a211a2)   │    ║
  ║  │                    ^^^20 bytes^^^  ^^8 bytes^^  ^^4 bytes^^ │    ║
  ║  │                         Total hash input: 32 bytes          │    ║
  ║  │ Value: uint256 balance                                      │    ║
  ║  └─────────────────────────────────────────────────────────────┘    ║
  ║                                                                     ║
  ║  ALLOWANCES — mapping(address => mapping(address => uint256))       ║
  ║  ┌─────────────────────────────────────────────────────────────┐    ║
  ║  │ Slot: keccak256(owner . 0x00..00 . 0x7f5e9f20 . spender)    │    ║
  ║  │                  ^^20^^  ^^8 bytes^^  ^^4 bytes^^  ^^20^^   │    ║
  ║  │                         Total hash input: 52 bytes          │    ║
  ║  │ Value: uint256 allowance                                    │    ║
  ║  └─────────────────────────────────────────────────────────────┘    ║
  ║                                                                     ║
  ║  NONCES — mapping(address => uint256)                               ║
  ║  ┌─────────────────────────────────────────────────────────────┐    ║
  ║  │ Slot: keccak256(owner . 0x00000000 00000000 . 0x38377508)   │    ║
  ║  │                  ^^20 bytes^^  ^^8 bytes^^      ^^4 bytes^^ │    ║
  ║  │                         Total hash input: 32 bytes          │    ║
  ║  │ Value: uint256 nonce                                        │    ║
  ║  └─────────────────────────────────────────────────────────────┘    ║
  ║                                                                     ║
  ║  Slots 0, 1, 2, 3... are COMPLETELY UNUSED                         ║
  ║  Inheriting contracts can safely declare state variables            ║
  ║                                                                     ║
  ╚══════════════════════════════════════════════════════════════════════╝
```

---

### 6.3 Why These Specific Seed Values?

Every seed in Solady follows one rule:

> **Seed = `bytes4(keccak256("<CONSTANT_NAME>"))` — the first 4 bytes of the keccak256 hash of the constant's own variable name.**

This is not arbitrary. Vectorized explicitly documents this pattern in [`OwnableRoles.sol` L41](https://github.com/Vectorized/solady/blob/main/src/auth/OwnableRoles.sol#L41):

> _"Note: This is equivalent to `uint32(bytes4(keccak256("_OWNER_SLOT_NOT")))`."_

#### Proof Table

```
Constant Name             cast keccak Output                                          Seed (first N bytes)
─────────────────────     ──────────────────────────────────────────────────────────   ────────────────────────
_BALANCE_SLOT_SEED        0x87a211a246c0182135f126ff53996f034291eec622c2c84b19a7...   bytes4 = 0x87a211a2  ✓
_ALLOWANCE_SLOT_SEED      0x7f5e9f20d44ecf37f6bb86a31fb481bbbf80f21a47e118e630f9...   bytes4 = 0x7f5e9f20  ✓
_NONCES_SLOT_SEED         0x38377508b49ecec68f7d09494264923eb0bef996d1691bbad63e...   bytes4 = 0x38377508  ✓
_TOTAL_SUPPLY_SLOT        0x05345cdf77eb68f44c1e59c54aa9cb7d84c6fda7194e4a8e34fb...   bytes9 = 0x05345cdf77eb68f44c  ✓
```

#### Why `_TOTAL_SUPPLY_SLOT` Uses 9 Bytes (`bytes9`) Instead of 4

Total supply is a **fixed slot**, not a mapping seed — it doesn't get hashed with an address. Using only 4 bytes (`bytes4`) would place it dangerously close to Solidity's sequential slot range (0, 1, 2, 3...). Using 9 bytes pushes the slot far enough from both:

- **Low slots** (Solidity's sequential range: 0x00–0xFF...)
- **High slots** (keccak256 outputs are 32 bytes, so mapping slots live in the full 2²⁵⁶ space)

9 bytes = `0x05345cdf77eb68f44c` — a "no man's land" that avoids collisions with both patterns.

#### Why This Derivation Method Works

1. **Deterministic & reproducible** — anyone can verify with `cast keccak "<NAME>"`
2. **Self-documenting** — the seed encodes its own identity (hash of its own name)
3. **Collision-resistant between mappings** — different names → different keccak256 → different `bytes4` prefix
4. **Gas-efficient** — 4 bytes = `PUSH4` opcode (5 bytes of bytecode), the cheapest possible constant size
5. **Cross-library consistent** — the same pattern is used across all Solady contracts: `Ownable.sol`, `OwnableRoles.sol`, `ERC721.sol`, `ERC1155.sol`, `ERC6551.sol`, `LibStorage.sol`, `LibTransient.sol`

#### Verify It Yourself (Chisel / Cast)

```bash
# Using cast (Foundry CLI)
cast keccak "_BALANCE_SLOT_SEED"
# → 0x87a211a246c0182135f126ff53996f034291eec622c2c84b19a7bb9702c1d365
# First 4 bytes: 0x87a211a2 ✓

cast keccak "_ALLOWANCE_SLOT_SEED"
# → 0x7f5e9f20d44ecf37f6bb86a31fb481bbbf80f21a47e118e630f97593ad3a6548
# First 4 bytes: 0x7f5e9f20 ✓

cast keccak "_NONCES_SLOT_SEED"
# → 0x38377508b49ecec68f7d09494264923eb0bef996d1691bbad63eaa675ea45b4c
# First 4 bytes: 0x38377508 ✓

cast keccak "_TOTAL_SUPPLY_SLOT"
# → 0x05345cdf77eb68f44c1e59c54aa9cb7d84c6fda7194e4a8e34fbf8618ba91f57
# First 9 bytes: 0x05345cdf77eb68f44c ✓
```

```solidity
// Using Chisel (interactive Solidity REPL)
bytes4(keccak256("_BALANCE_SLOT_SEED"))    // → 0x87a211a2
bytes4(keccak256("_ALLOWANCE_SLOT_SEED"))  // → 0x7f5e9f20
bytes4(keccak256("_NONCES_SLOT_SEED"))     // → 0x38377508
bytes9(keccak256("_TOTAL_SUPPLY_SLOT"))    // → 0x05345cdf77eb68f44c
```

---

## 7. Slot Computation: Byte-by-Byte

### 7.1 Total Supply — No Computation

```solidity
sload(0x05345cdf77eb68f44c)   // That's it. A fixed weird number.
```

Why `0x05345cdf77eb68f44c`? It's 9 bytes — too small to ever collide with a keccak256 output (which is 32 bytes, uniformly
distributed). It also won't collide with Solidity's sequential slots (0, 1, 2...). It's a chosen "island" in the storage
space that nothing else will touch.

---

### 7.2 Balance Slot — balanceOf(owner)

Assembly code (L158-160):

```solidity
mstore(0x0c, _BALANCE_SLOT_SEED)  // Phase 1: write seed
mstore(0x00, owner)                // Phase 2: write owner (overwrites part of Phase 1)
keccak256(0x0c, 0x20)             // hash 32 bytes starting at 0x0c
```

#### Initial Memory State (fresh external call)

Memory is zeroed. The free memory pointer at 0x40 points to 0x80:

```
         0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f
0x00  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
0x10  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
0x20  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
0x30  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
0x40  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
0x50  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   80  <- free mem ptr
0x60  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00  <- zero slot
0x70  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
```

#### Phase 1: `mstore(0x0c, 0x87a211a2)`

Writes 32 bytes at offset 0x0c (range 0x0c-0x2b). The value `0x87a211a2` is only 4 bytes, so
it is left-padded to 32 bytes: `0x0000...000087a211a2`.

```
value = 0x0000000000000000000000000000000000000000000000000000000087a211a2
        <---------------------- 28 zero bytes ----------------------><-4 seed->

         0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f
0x00  |  00   00   00   00   00   00   00   00   00   00   00   00 | 00   00   00   00
         <-------- untouched (12 bytes) -------------------------> <- mstore starts -->
0x10  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
         <--------------------- all zeros (seed left-padding) ----------------------->
0x20  |  00   00   00   00   00   00   00   00   87   a2   11   a2 | 00   00   00   00
         <--- zeros (seed pad) ----------------> <---SEED---------> <- untouched ------
```

Zoomed into the written region (0x0c-0x2b):

```
0x0c: 00 00 00 00  ─┐
0x10: 00 00 00 00   │
0x14: 00 00 00 00   │  28 bytes of zeros
0x18: 00 00 00 00   │  (left-padding of the 32-byte word)
0x1c: 00 00 00 00   │
0x20: 00 00 00 00   │
0x24: 00 00 00 00  ─┘
0x28: 87 a2 11 a2  <- the 4-byte seed (_BALANCE_SLOT_SEED)
```

#### Phase 2: `mstore(0x00, owner)` — owner = `0xcafebabecafebabecafebabecafebabecafebabe`

Writes 32 bytes at offset 0x00 (range 0x00-0x1f). The 20-byte address is left-padded with 12 zero bytes.
This **overwrites** bytes 0x0c-0x1f that Phase 1 wrote (those were zeros anyway — the overlap trick):

```
value = 0x000000000000000000000000cafebabecafebabecafebabecafebabecafebabe
        <---- 12 zero bytes --------><---------- 20-byte address ---------->

         0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f
0x00  |  00   00   00   00   00   00   00   00   00   00   00   00   ca   fe   ba   be
         <-------- 12 zero bytes (addr left-padding) ---------------> <- address starts
0x10  |  ca   fe   ba   be   ca   fe   ba   be   ca   fe   ba   be   ca   fe   ba   be
         <--------------------- address continues (20 bytes total) -------------------->
0x20  |  00   00   00   00   00   00   00   00   87   a2   11   a2 | 00   00   00   00
         <---- survived from Phase 1 -------------> <---SEED-------> <- untouched ------
```

**Key insight**: `mstore(0x00, ...)` writes bytes 0x00-0x1f. The seed at 0x28-0x2b **survives**
because the write only reaches byte 0x1f. The zeros from Phase 1 at 0x0c-0x1f get
replaced by the owner's address — which is exactly what we want.

#### Hash Input: `keccak256(0x0c, 0x20)` — 32 bytes from 0x0c to 0x2b

```
0x0c                                                                              0x2b
 |                                                                                  |
 ca fe ba be ca fe ba be ca fe ba be ca fe ba be ca fe ba be  00 00 00 00 00 00 00 00  87 a2 11 a2
 <-------------------- 20-byte OWNER -----------------------> <---- 8 zero bytes ----> <-4 SEED-->
                                     = 32 bytes total
```

**Result goes on the STACK, not memory.** The EVM executes inside-out:

```
Step 1:  keccak256(0x0c, 0x20)  -> pushes 32-byte hash onto the STACK
Step 2:  sload(^^^)             -> pops that hash, uses it as storage slot key
Step 3:  result :=              -> assigns stack top to return variable
```

Memory is unchanged — the hash never touches memory.

---

### 7.3 Allowance Slot — allowance(owner, spender)

Assembly code (L176-179):

```solidity
mstore(0x20, spender)              // Phase 1: write spender
mstore(0x0c, _ALLOWANCE_SLOT_SEED) // Phase 2: write seed (overwrites part of Phase 1)
mstore(0x00, owner)                // Phase 3: write owner (overwrites part of Phase 2)
keccak256(0x0c, 0x34)              // hash 52 bytes starting at 0x0c
```

#### Phase 1: `mstore(0x20, spender)` — spender = `0xdeadbeafdeadbeafdeadbeafdeadbeafdeadbeaf`

Writes 32 bytes at offset 0x20 (range 0x20-0x3f):

```
         0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f
0x00  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
0x10  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
         <---------------------------- untouched ---------------------------------------->
0x20  |  00   00   00   00   00   00   00   00   00   00   00   00   de   ad   be   af
         <-------- 12 zero bytes (spender left-pad) ------------------> spender starts ->
0x30  |  de   ad   be   af   de   ad   be   af   de   ad   be   af   de   ad   be   af
         <--------------------- spender continues (20 bytes total) -------------------->
```

#### Phase 2: `mstore(0x0c, 0x7f5e9f20)`

Writes 32 bytes at offset 0x0c (range 0x0c-0x2b). **Overwrites** 0x20-0x2b from Phase 1
(the spender's zero padding), but spender's address at 0x2c-0x3f **survives**:

```
         0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f
0x00  |  00   00   00   00   00   00   00   00   00   00   00   00 | 00   00   00   00
         <-------- untouched (12 bytes) --------------------------> <- mstore starts -->
0x10  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
         <--------------------- zeros (seed left-padding) ------------------------------>
0x20  |  00   00   00   00   00   00   00   00   7f   5e   9f   20 | de   ad   be   af
         <---- zeros (seed pad) -----------------> <----SEED-------> <- SURVIVED -------
         ^^^^^^^^^^^^^^^^ OVERWRITTEN (was spender pad) ^^^^^^^^^^^^  (from Phase 1)
0x30  |  de   ad   be   af   de   ad   be   af   de   ad   be   af   de   ad   be   af
         <--------------------- spender address (survived from Phase 1) ---------------->
```

#### Phase 3: `mstore(0x00, owner)` — owner = `0xcafebabecafebabecafebabecafebabecafebabe`

Writes 32 bytes at offset 0x00 (range 0x00-0x1f). **Overwrites** 0x0c-0x1f from Phase 2
(the seed's leading zeros). Seed at 0x28-0x2b and spender at 0x2c-0x3f **survive**:

```
         0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f
0x00  |  00   00   00   00   00   00   00   00   00   00   00   00   ca   fe   ba   be
         <-------- 12 zero bytes (owner left-pad) ------------------> <- owner starts ->
0x10  |  ca   fe   ba   be   ca   fe   ba   be   ca   fe   ba   be   ca   fe   ba   be
         <--------------------- owner address continues (20 bytes total) --------------->
0x20  |  00   00   00   00   00   00   00   00   7f   5e   9f   20   de   ad   be   af
         <---- 8 zero bytes (from Phase 2) -------> <----SEED-------> spender (Phase 1)->
0x30  |  de   ad   be   af   de   ad   be   af   de   ad   be   af   de   ad   be   af
         <--------------------- spender continues (from Phase 1) ----------------------->
```

#### Hash Input: `keccak256(0x0c, 0x34)` — 52 bytes from 0x0c to 0x3f

```
0x0c                                                                                                                            0x3f
 |                                                                                                                                |
 ca fe ba be ca fe ba be ca fe ba be ca fe ba be ca fe ba be  00 00 00 00 00 00 00 00  7f 5e 9f 20  de ad be af de ad be af de ad be af de ad be af de ad be af
 <-------------------- 20-byte OWNER -----------------------> <---- 8 zero bytes ----> <-4 SEED--> <-------------------- 20-byte SPENDER ---------------------->
                                                                        = 52 bytes total (0x34)
```

Structured view:

```
  ┌─────────────────────────────────────────────────────────┐
  │  OWNER          ZEROS        SEED         SPENDER       │
  │  <-- 20 B ---> <-- 8 B --> <-- 4 B --> <-- 20 B ----->  │
  │  0x0c-0x1f     0x20-0x27   0x28-0x2b    0x2c-0x3f       │
  │  20 + 8 + 4 + 20 = 52 bytes = 0x34                      │
  └─────────────────────────────────────────────────────────┘
```

#### Overlap Survival Map — Which Bytes Survived From Which Phase

```
0x00       0x0c       0x1f 0x20       0x27 0x28   0x2b 0x2c             0x3f
+----------+----------+----+----------+----+-------+----+-----------------+
| Phase 3  | Phase 3  |    | Phase 2  |    |Phase 2|    |    Phase 1      |
| 12 zeros | 20B owner|    | 8 zeros  |    | SEED  |    |  20B spender    |
| (pad)    |          |    | (pad)    |    |       |    |                 |
+----------+----------+    +----------+    +-------+    +-----------------+
```

The three `mstore`s are ordered back-to-front (spender, seed, owner) so each write's
padding gets overwritten by the next, while the meaningful data at the tail of each
write survives. One `keccak256` over 52 bytes replaces what Solidity would compute as
two separate hashes over 128 bytes total.

---

### 7.4 Nonce Slot — Same Pattern as Balance

Same 2-mstore technique as balanceOf, with seed `0x38377508` instead of `0x87a211a2`.

Assembly code (L378-381):

```solidity
mstore(0x0c, _NONCES_SLOT_SEED)   // Phase 1: write seed (0x38377508)
mstore(0x00, owner)                // Phase 2: write owner (overwrites part of Phase 1)
result := sload(keccak256(0x0c, 0x20))  // hash 32 bytes starting at 0x0c
```

#### Phase 1: `mstore(0x0c, 0x38377508)`

Writes 32 bytes at offset 0x0c (range 0x0c-0x2b). The value `0x38377508` is only 4 bytes, so
it is left-padded to 32 bytes: `0x0000...0000038377508`.

```
value = 0x0000000000000000000000000000000000000000000000000000000038377508
        <---------------------- 28 zero bytes ----------------------><-4 seed->

         0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f
0x00  |  00   00   00   00   00   00   00   00   00   00   00   00 | 00   00   00   00
         <-------- untouched (12 bytes) -------------------------> <- mstore starts -->
0x10  |  00   00   00   00   00   00   00   00   00   00   00   00   00   00   00   00
         <--------------------- all zeros (seed left-padding) ----------------------->
0x20  |  00   00   00   00   00   00   00   00   38   37   75   08 | 00   00   00   00
         <--- zeros (seed pad) ----------------> <---SEED---------> <- untouched ------
```

Zoomed into the written region (0x0c-0x2b):

```
0x0c: 00 00 00 00  ─┐
0x10: 00 00 00 00   │
0x14: 00 00 00 00   │  28 bytes of zeros
0x18: 00 00 00 00   │  (left-padding of the 32-byte word)
0x1c: 00 00 00 00   │
0x20: 00 00 00 00   │
0x24: 00 00 00 00  ─┘
0x28: 38 37 75 08  <- the 4-byte seed (_NONCES_SLOT_SEED)
```

#### Phase 2: `mstore(0x00, owner)` — owner = `0xcafebabecafebabecafebabecafebabecafebabe`

Writes 32 bytes at offset 0x00 (range 0x00-0x1f). The 20-byte address is left-padded with 12 zero bytes.
This **overwrites** bytes 0x0c-0x1f that Phase 1 wrote (those were zeros — the overlap trick):

```
value = 0x000000000000000000000000cafebabecafebabecafebabecafebabecafebabe
        <---- 12 zero bytes --------><---------- 20-byte address ---------->

         0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f
0x00  |  00   00   00   00   00   00   00   00   00   00   00   00   ca   fe   ba   be
         <-------- 12 zero bytes (addr left-padding) ---------------> <- address starts
0x10  |  ca   fe   ba   be   ca   fe   ba   be   ca   fe   ba   be   ca   fe   ba   be
         <--------------------- address continues (20 bytes total) -------------------->
0x20  |  00   00   00   00   00   00   00   00   38   37   75   08 | 00   00   00   00
         <---- survived from Phase 1 -------------> <---SEED-------> <- untouched ------
```

**Key insight**: `mstore(0x00, ...)` writes bytes 0x00-0x1f. The seed at 0x28-0x2b **survives**
because the write only reaches byte 0x1f. The zeros from Phase 1 at 0x0c-0x1f get
replaced by the owner's address — exactly as designed.

#### Hash Input: `keccak256(0x0c, 0x20)` — 32 bytes from 0x0c to 0x2b

```
0x0c                                                                              0x2b
 |                                                                                  |
 ca fe ba be ca fe ba be ca fe ba be ca fe ba be ca fe ba be  00 00 00 00 00 00 00 00  38 37 75 08
 <-------------------- 20-byte OWNER -----------------------> <---- 8 zero bytes ----> <-4 SEED-->
                                     = 32 bytes total
```

Identical layout to balanceOf — only the seed differs (`38377508` vs `87a211a2`),
which guarantees a completely different storage slot for the same owner.

---

## 8. The or() Optimization

In `balanceOf` (external), Vectorized uses two `mstore`s. But in `_transfer` (L563-565) he uses a single combined write:

```solidity
let from_ := shl(96, from)
mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))
```

This works because:

```
shl(96, from):   (from = 0xcafebabecafebabecafebabecafebabecafebabe)
  0xcafebabecafebabecafebabecafebabecafebabe 000000000000 00000000 00000000
  <------------- 20 byte addr -------------> <------12 bytes of zeros----->

or() with _BALANCE_SLOT_SEED (0x87a211a2):
  0xcafebabecafebabecafebabecafebabecafebabe 000000000000 00000000 87a211a2
  <------------- 20 byte addr -------------> <--8 zeros--> <---4 seed---->
```

Single `mstore(0x0c, result)` -> same memory layout as the 2-mstore version.

Saves 1 `mstore` (3 gas) + the mload setup on every internal transfer/approve. Small savings, but these functions are called
millions of times.

---

## 9. Replicating Slot Computation in Solidity/Chisel

### 9.1 The Wrong Way

```solidity
// WRONG: abi.encodePacked(owner, 0x87a211a2) = 24 bytes (20 + 4)
// Missing the 8 zero bytes that the mstore overlap creates!
keccak256(abi.encodePacked(
    address(0xcafebabecafebabecafebabecafebabecafebabe),
    uint32(0x87a211a2)
))
// This hashes 24 bytes, but Solady hashes 32 bytes -> DIFFERENT slot!
```

### 9.2 Correct: Balance Slot

```solidity
// Method 1: Explicit zero padding
keccak256(abi.encodePacked(
    address(0xcafebabecafebabecafebabecafebabecafebabe),  // 20 bytes
    uint64(0),                                             // 8 zero bytes
    uint32(0x87a211a2)                                     // 4 byte seed
))
// 20 + 8 + 4 = 32 bytes  ✓

// Method 2: Pack seed into 12 bytes (uint96 = 12 bytes in encodePacked)
keccak256(abi.encodePacked(
    address(0xcafebabecafebabecafebabecafebabecafebabe),  // 20 bytes
    uint96(0x87a211a2)                                     // 12 bytes (8 zeros + 4 seed)
))
// 20 + 12 = 32 bytes  ✓
```

### 9.3 Correct: Allowance Slot

```solidity
keccak256(abi.encodePacked(
    address(0xcafebabecafebabecafebabecafebabecafebabe),  // 20 bytes  owner
    uint64(0),                                             // 8 zero bytes
    uint32(0x7f5e9f20),                                    // 4 byte seed
    address(0xdeadbeafdeadbeafdeadbeafdeadbeafdeadbeaf)    // 20 bytes  spender
))
// 20 + 8 + 4 + 20 = 52 bytes  ✓
```

### 9.4 Raw Hex in Chisel

```solidity
// Balance slot (32 bytes):
keccak256(hex"cafebabecafebabecafebabecafebabecafebabe000000000000000087a211a2")

// Allowance slot (52 bytes):
keccak256(hex"cafebabecafebabecafebabecafebabecafebabe00000000000000007f5e9f20deadbeafdeadbeafdeadbeafdeadbeafdeadbeaf")
```

---

## 10. Comparison: Solidity vs Solady

```
  ┌────────────────────────────────────────────────────────────────────┐
  │              SOLIDITY (standard mapping)                           │
  │                                                                    │
  │  balances[owner]:                                                  │
  │    keccak256(abi.encode(owner, uint256(SLOT)))                     │
  │    = keccak256(  32-byte owner  |  32-byte slot number  )          │
  │                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^              │
  │                  64 bytes hashed, 2 mstores                        │
  │                                                                    │
  │  allowances[owner][spender]:                                       │
  │    inner = keccak256(abi.encode(owner, uint256(SLOT)))             │
  │    keccak256(abi.encode(spender, inner))                           │
  │    = TWO keccak256 calls, 128 bytes hashed total                   │
  │                                                                    │
  ├────────────────────────────────────────────────────────────────────┤
  │              SOLADY (seed-based)                                   │
  │                                                                    │
  │  balances[owner]:                                                  │
  │    keccak256( owner | 0x00..00 | 0x87a211a2 )                      │
  │              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^                    │
  │              32 bytes hashed, 2 mstores (or 1 with or())           │
  │                                                                    │
  │  allowances[owner][spender]:                                       │
  │    keccak256( owner | 0x00..00 | 0x7f5e9f20 | spender )            │
  │              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^        │
  │              52 bytes hashed, ONE keccak256, 3 mstores             │
  │                                                                    │
  └────────────────────────────────────────────────────────────────────┘
```

Gas savings:
- Balance lookup:    32 vs 64 bytes hashed -> ~50% less keccak gas
- Allowance lookup:  52 bytes + 1 hash vs 128 bytes + 2 hashes -> ~60% less

---

## 11. Collision Safety

Why won't these slots collide with each other or with inheriting contracts?

1. **Balance vs Nonce vs Allowance** — Different seeds (`87a211a2` vs `38377508` vs `7f5e9f20`) at the same position means different
hash inputs -> different slots
2. **Total Supply** — Fixed at `0x05345cdf77eb68f44c`, a 9-byte value. All keccak256 outputs are 32 bytes with uniform
distribution — the probability of collision is negligible (~2^-200)
3. **Inheriting contracts** — If they declare normal state variables, Solidity assigns slots 0, 1, 2... These tiny numbers
won't collide with keccak256 outputs or the total supply slot
4. **Solady's other contracts** — Use different seed constants, so the hash inputs are always distinct

---

## 12. Advanced Assembly Tricks Deep Dive

### 12.1 `not(allowance_)` Infinite Approval Skip (L271, L313, L607)

```solidity
let allowance_ := sload(allowanceSlot)
// If the allowance is not the maximum uint256 value.
if not(allowance_) {
    // Revert if the amount to be transferred exceeds the allowance.
    if gt(amount, allowance_) {
        mstore(0x00, 0x13be252b) // `InsufficientAllowance()`.
        revert(0x1c, 0x04)
    }
    // Subtract and store the updated allowance.
    sstore(allowanceSlot, sub(allowance_, amount))
}
```

`not(type(uint256).max)` = `not(0xfff...fff)` = `0x000...000` = `0` (falsy).

When allowance is `type(uint256).max` (infinite approval), the entire block is skipped:
- No `gt()` comparison
- No `sstore` (saves 5,000+ gas — cold sstore is 20,000 gas, warm is 5,000)
- No subtraction

This is the standard "infinite approval" pattern used by most DeFi frontends. The naming
reads like English ("if not allowance") but does bitwise NOT — a completely different semantic.

---

### 12.2 Dual-Purpose `_NONCES_SLOT_SEED_WITH_SIGNATURE_PREFIX` (L104, L424)

```solidity
uint256 private constant _NONCES_SLOT_SEED_WITH_SIGNATURE_PREFIX = 0x383775081901;
```

Decomposition:

```
0x383775081901
   ^^^^^^^^      = _NONCES_SLOT_SEED (0x38377508)
       ^^^^      = EIP-191 prefix    (0x1901)
```

At L424: `mstore(0x0e, 0x383775081901)` serves **two purposes** at different execution stages:

**Purpose 1 — Nonce slot computation (immediately, L424-426):**

```
mstore(0x0e, 0x383775081901)   // writes 32 bytes at 0x0e
mstore(0x00, owner)
let nonceSlot := keccak256(0x0c, 0x20)
```

The nonce seed `0x38377508` lands at bytes 0x28-0x2b (same offset pattern as balance/allowance).
The `0x1901` at the end (bytes 0x2c-0x2d) is harmless — it's outside the keccak range.

**Purpose 2 — EIP-191 prefix (later, L444):**

```
mstore(0x2e, keccak256(m, 0xa0))    // domain separator at 0x2e
// ...
mstore(0x4e, keccak256(m, 0xc0))    // struct hash at 0x4e
mstore(0x00, keccak256(0x2c, 0x42)) // EIP-712 digest
```

Memory at 0x2c-0x2d still contains `0x1901` from that earlier mstore. So `keccak256(0x2c, 0x42)` hashes:

```
0x2c: 19 01                         <- EIP-191 prefix (from the mstore at L424!)
0x2e: [32-byte domain separator]    <- written at L434
0x4e: [32-byte struct hash]         <- written at L442
```

One `mstore` does double duty across ~20 lines of assembly. This is the most elegant trick in the entire contract.

---

### 12.3 `shr(96, mload(0x0c))` Event Topic Extraction (L242, L517, L584)

After computing a balance slot for `to`, the `to` address still sits in memory:

```solidity
mstore(0x00, to)                              // to at bytes 0x00-0x1f
let toBalanceSlot := keccak256(0x0c, 0x20)    // hash, result on stack
// ... (store updated balance) ...
mstore(0x20, amount)
log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, caller(), shr(96, mload(0x0c)))
```

`mload(0x0c)` loads 32 bytes starting at 0x0c. After `mstore(0x00, to)`, memory at 0x0c-0x1f
contains the last 20 bytes of the `to` word — i.e., the `to` address itself:

```
Memory after mstore(0x00, to):
0x00: 00 00 00 00 00 00 00 00 00 00 00 00 [ca fe ba be ca fe ba be ...]
                                     0x0c ^--- to address starts here

mload(0x0c) reads:
[ca fe ba be ca fe ba be ca fe ba be ca fe ba be ca fe ba be] [00 00 00 00 00 00 00 00 87 a2 11 a2]
 <----------- 20-byte to address --------------------------->  <---------- 12 trailing bytes ------>

shr(96, ...) right-shifts by 96 bits (12 bytes):
[00 00 00 00 00 00 00 00 00 00 00 00] [ca fe ba be ca fe ba be ca fe ba be ca fe ba be ca fe ba be]
 <---------- 12 zero bytes --------->  <----------- 20-byte to address (clean) ------------------->
```

Zero extra `mstore`s to prepare the event topic — it reads the address from where it already
sits in memory from the slot computation. Pure memory recycling.

---

### 12.4 `ecrecover` Return Value Trick in `permit` (L448-459)

```solidity
let t := staticcall(gas(), 1, 0x00, 0x80, 0x20, 0x20)
// If the ecrecover fails, the returndatasize will be 0x00,
// `owner` will be checked if it equals the hash at 0x00,
// which evaluates to false (i.e. 0), and we will revert.
if iszero(eq(mload(returndatasize()), owner)) {
    mstore(0x00, 0xddafbaef) // `InvalidPermit()`.
    revert(0x1c, 0x04)
}
// Increment and store the updated nonce.
sstore(nonceSlot, add(nonceValue, t)) // `t` is 1 if ecrecover succeeds.
```

Three tricks in one:

```
┌─────────────────────┬─────────────────────────┬──────────────────────────┐
│       Aspect        │   ecrecover succeeds    │    ecrecover fails       │
├─────────────────────┼─────────────────────────┼──────────────────────────┤
│ returndatasize()    │ 0x20 (32 bytes)         │ 0x00 (no return data)    │
│ mload(retdatasize)  │ mload(0x20) = recovered │ mload(0x00) = digest     │
│ eq(..., owner)      │ true (valid signature)  │ false (hash != address)  │
│ t                   │ 1 (staticcall success)  │ 0 (staticcall failure)   │
│ nonce increment     │ add(nonce, 1)           │ reverts before sstore    │
└─────────────────────┴─────────────────────────┴──────────────────────────┘
```

- On **success**: `returndatasize()` = 0x20, so `mload(0x20)` reads the recovered address.
  `t` = 1, so the nonce is incremented by 1.
- On **failure**: `returndatasize()` = 0x00, so `mload(0x00)` reads the digest hash
  (which was stored at 0x00 for ecrecover input). A hash will never equal an address -> revert.
  `t` = 0, but we never reach the sstore.

The `t` value from `staticcall` (1=success) is recycled directly as the nonce increment
amount. No separate `add(nonceValue, 1)` needed.

---

### 12.5 `shr(96, shl(96, addr))` Address Cleaning (L191, L402, L421-422, L549)

```solidity
owner := shr(96, shl(96, owner))
spender := shr(96, shl(96, spender))
```

The double-shift clears the upper 96 bits of a 256-bit word, isolating the 20-byte address:

```
Before:  [XX XX XX XX XX XX XX XX XX XX XX XX] [ca fe ba be ca fe ba be ca fe ba be ca fe ba be ca fe ba be]
          <---- dirty upper 96 bits ---------> <----------- 20-byte address ------------------------------>

shl(96): [ca fe ba be ca fe ba be ca fe ba be ca fe ba be ca fe ba be] [00 00 00 00 00 00 00 00 00 00 00 00]
          <----------- address shifted left 96 bits -----------------> <---- 12 zero bytes --------------->

shr(96): [00 00 00 00 00 00 00 00 00 00 00 00] [ca fe ba be ca fe ba be ca fe ba be ca fe ba be ca fe ba be]
          <---- 12 clean zero bytes ----------> <----------- 20-byte address (clean) ---------------------->
```

Why not `and(owner, 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)`?

Because `and` with a 20-byte mask requires pushing a 20-byte constant onto the stack —
that's 20 bytes of bytecode for the `PUSH20` instruction. In contrast, `shl(96, ...)` and
`shr(96, ...)` each only push the small constant `96` (1 byte for `PUSH1`). Net savings:
~18 bytes of deployed bytecode and ~2 gas per usage.

---

### 12.6 `permit()` Memory Choreography (L419-468)

The `permit` function reuses the same memory region for three sequential computations:

```
Phase 1: Build domain separator hash
  mstore(m,        _DOMAIN_TYPEHASH)      // m+0x00
  mstore(m+0x20,   nameHash)              // m+0x20
  mstore(m+0x40,   versionHash)           // m+0x40
  mstore(m+0x60,   chainid())             // m+0x60
  mstore(m+0x80,   address())             // m+0x80
  mstore(0x2e, keccak256(m, 0xa0))        // store 32-byte result at 0x2e

Phase 2: Build struct hash (reuses m!)
  mstore(m,        _PERMIT_TYPEHASH)      // m+0x00  (overwrites domain typehash)
  mstore(m+0x20,   owner)                 // m+0x20  (overwrites nameHash)
  mstore(m+0x40,   spender)              // m+0x40  (overwrites versionHash)
  mstore(m+0x60,   value)                // m+0x60  (overwrites chainid)
  mstore(m+0x80,   nonceValue)           // m+0x80  (overwrites address)
  mstore(m+0xa0,   deadline)             // m+0xa0
  mstore(0x4e, keccak256(m, 0xc0))       // store 32-byte result at 0x4e

Phase 3: Compute EIP-712 digest
  keccak256(0x2c, 0x42)                  // hash 66 bytes
```

After Phases 1-2, memory at 0x2c-0x6d looks like:

```
0x2c: 19 01                        <- EIP-191 prefix (placed by mstore at L424)
0x2e: [32-byte domain separator]   <- from Phase 1
0x4e: [32-byte struct hash]        <- from Phase 2
      = 66 bytes (0x42) total
```

`keccak256(0x2c, 0x42)` = `keccak256(0x1901 || domainSep || structHash)` — exactly the
EIP-712 digest per the specification.

The offsets `0x2e` and `0x4e` are chosen **precisely** so the results land contiguously
after the 2-byte prefix. The same memory at `m` is reused for both the domain separator
and struct hash computations, then the free memory pointer and zero slot are restored at L466-467.

---

### 12.7 `or(from_, _BALANCE_SLOT_SEED)` Single-Write Optimization (L263-282)

In `transferFrom`, the `from` address is used for both the allowance slot and balance slot
computations. Instead of 2 mstores each time, Vectorized caches `shl(96, from)` and reuses it:

```solidity
let from_ := shl(96, from)                          // L263: cache once

// Allowance slot:
mstore(0x20, caller())                               // L266
mstore(0x0c, or(from_, _ALLOWANCE_SLOT_SEED))        // L267: single write
let allowanceSlot := keccak256(0x0c, 0x34)           // L268

// ... (spend allowance) ...

// Balance slot (reuses from_):
mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))          // L282: single write
let fromBalanceSlot := keccak256(0x0c, 0x20)         // L283

// ... (transfer) ...

// Event topic (reuses from_):
log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE,
     shr(96, from_),                                  // L301: reuse for log topic
     shr(96, mload(0x0c)))
```

One stack variable (`from_`) serves **three purposes**:
1. Combined with `_ALLOWANCE_SLOT_SEED` via `or()` for allowance slot
2. Combined with `_BALANCE_SLOT_SEED` via `or()` for balance slot
3. Right-shifted back via `shr(96, from_)` for the Transfer event topic

---

### 12.8 `revert(0x1c, 0x04)` Pattern

Used universally across Solady for custom error reverts:

```solidity
mstore(0x00, 0xf4d678b8)  // InsufficientBalance() selector
revert(0x1c, 0x04)        // return 4 bytes starting at offset 0x1c
```

How it works:

```
mstore(0x00, 0xf4d678b8) writes the 4-byte selector as a 32-byte word:

0x00: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
0x10: 00 00 00 00 00 00 00 00 00 00 00 00 f4 d6 78 b8
      <----------- 28 zero bytes ----------> <-selector>
                                        0x1c ^-- starts here

revert(0x1c, 0x04) returns bytes 0x1c-0x1f = f4 d6 78 b8
```

The selector is right-aligned in the 32-byte word. `0x1c` = 28, which skips the 28
leading zeros to land exactly on the 4-byte selector. This is the standard Solady
revert pattern — memorize `revert(0x1c, 0x04)` as "revert with custom error selector".

Why not `mstore(0x00, shl(224, 0xf4d678b8))` + `revert(0x00, 0x04)`? That would left-align
the selector and read from 0x00, but `shl(224, ...)` costs an extra opcode. Storing the
raw value and reading from offset 0x1c is one instruction cheaper.
