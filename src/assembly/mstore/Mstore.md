# mstore — Writing to the Reserved Memory Slots

## Contracts: [Mstore.sol](./Mstore.sol)
## Tests: [TestMstore.sol](../../../test/assembly/mstore/TestMstore.sol)
## Gas Benchmarks: [snapshots/TestMstore.json](../../../snapshots/TestMstore.json)

---

## EVM Memory Layout (First 128 Bytes)

The EVM reserves the first four 32-byte words for specific purposes:

```
Offset     Size      Purpose                    Reserved By
─────────────────────────────────────────────────────────────
0x00-0x1f  32 bytes  Scratch space              Solidity compiler
0x20-0x3f  32 bytes  Scratch space              Solidity compiler
0x40-0x5f  32 bytes  Free memory pointer        Solidity compiler
0x60-0x7f  32 bytes  Zero slot (always 0x00)    Solidity compiler
─────────────────────────────────────────────────────────────
0x80+                Free memory starts here
```

"Reserved" means the Solidity compiler expects these slots to hold certain values. But in inline assembly, **you bypass the compiler** — you can write to any of them.

The question is: **what happens when you do, and what does it cost?**

---

## The 4 Experiments

Each contract writes `0xff...ff` to a different reserved slot and reads it back:

### MstoreA — Scratch Space 0x00 (320 gas)

```solidity
assembly {
    mstore(0x00, __FF__)   // Write to scratch space word 1
    res := mload(0x00)     // Read it back
}
```

**Behavior:** Completely safe. Scratch space (0x00-0x3f) exists exactly for this — temporary values between assembly statements. The compiler does not rely on anything persisting here. Solady uses this constantly for hashing:

```solidity
// Solady pattern: use 0x00 for keccak256 input
mstore(0x00, owner)
mstore(0x20, slot_seed)
let slot := keccak256(0x00, 0x40)
```

### MstoreB — Scratch Space 0x20 (322 gas)

```solidity
assembly {
    mstore(0x20, __FF__)   // Write to scratch space word 2
    res := mload(0x20)     // Read it back
}
```

**Behavior:** Also safe. Same scratch region as 0x00. The 2-gas difference from MstoreA is because writing to 0x20 may trigger a small memory expansion cost if memory was only "active" up to 0x1f before this call.

### MstoreC — Free Memory Pointer 0x40 (324 gas)

```solidity
assembly {
    mstore(0x40, __FF__)   // Overwrite free memory pointer!
    res := mload(0x40)     // Read it back
    mstore(0x40, 0x0)    
}
```

**Behavior:** Dangerous! Slot 0x40 holds the **free memory pointer** — the compiler reads this to know where to allocate next. If you overwrite it and don't restore it, any subsequent Solidity code (`abi.encode`, `new bytes(...)`, event emission, external calls) will allocate memory at a corrupt offset, leading to **silent data corruption**.

**Why it costs 324 gas:** Three `mstore` operations instead of two. The mandatory reset (`mstore(0x40, 0x0)`) adds the extra cost. In practice you would restore the original value, not zero:

```solidity
assembly {
    let fmp := mload(0x40)      // Save original
    mstore(0x40, someValue)     // Use it
    // ... do work ...
    mstore(0x40, fmp)           // Restore original
}
```

### MstoreD — Zero Slot 0x60 (322 gas)

```solidity
assembly {
    mstore(0x60, __FF__)   // Overwrite the zero slot!
    res := mload(0x60)     // Read it back
}
```

**Behavior:** Dangerous! Slot 0x60 is the **zero slot** — the compiler uses it as a source of 32 zero bytes for initializing dynamic memory types (`bytes memory`, `string memory`, `uint256[] memory`). If you overwrite it, any subsequent Solidity memory allocation may contain garbage instead of zeros.

**Why no reset in the test?** The test function returns immediately after reading, so no Solidity code runs after the corruption. In real contracts you **must** restore it:

```solidity
assembly {
    mstore(0x60, someValue)
    // ... use it ...
    mstore(0x60, 0)            // Restore zero slot
}
```

Solady always does this — see `SafeTransferLib.safeTransferFrom`:

```solidity
// After using 0x60 for calldata encoding:
mstore(0x60, 0)   // Restore zero slot
mstore(0x40, m)   // Restore free memory pointer
```

---

## Gas Benchmarks

From `snapshots/TestMstore.json` (execution gas only, excludes call overhead):

```
┌───────────┬────────┬──────────────────┬──────────────────────────────┐
│ Contract  │  Gas   │  Slot            │  Notes                       │
├───────────┼────────┼──────────────────┼──────────────────────────────┤
│ MstoreA   │  320   │  0x00 (scratch)  │  Cheapest. No side effects.  │
│ MstoreB   │  322   │  0x20 (scratch)  │  +2 gas (memory expansion)   │
│ MstoreC   │  324   │  0x40 (free ptr) │  +4 gas (needs 3rd mstore)   │
│ MstoreD   │  322   │  0x60 (zero)     │  +2 gas (memory expansion)   │
└───────────┴────────┴──────────────────┴──────────────────────────────┘
```

### Why the Gas Differences?

The EVM charges for **memory expansion** — the first time you touch a higher memory offset, you pay extra. At function entry, the compiler initializes the free memory pointer (`mstore(0x40, 0x80)`), which means memory up to 0x5f is already "active":

```
0x00 ─┐
      │  Already active from function prologue
0x5f ─┘  (compiler wrote mstore(0x40, 0x80) which touches up to 0x5f)

0x60 ─┐
      │  First touch of this word costs +2 gas memory expansion
0x7f ─┘
```

- **MstoreA (0x00):** Already active. Pure mstore+mload = 3 + 3 + overhead = **320**
- **MstoreB (0x20):** Already active. Same cost as 0x00 but +2 from slight expansion = **322**
- **MstoreC (0x40):** Already active, but needs a third mstore to reset = **324**
- **MstoreD (0x60):** First touch beyond 0x5f, memory expansion cost = **322**

---

## Safety Cheat Sheet

```
┌────────┬───────────────────┬──────────┬─────────────────────────────┐
│ Slot   │ Name              │ Safe to  │ Must Reset?                 │
│        │                   │ Override │                             │
├────────┼───────────────────┼──────────┼─────────────────────────────┤
│ 0x00   │ Scratch space 1   │ YES      │ NO  — designed for this     │
│ 0x20   │ Scratch space 2   │ YES      │ NO  — designed for this     │
│ 0x40   │ Free memory ptr   │ CAREFUL  │ YES — restore original FMP  │
│ 0x60   │ Zero slot         │ CAREFUL  │ YES — restore to 0x00       │
└────────┴───────────────────┴──────────┴─────────────────────────────┘
```

### Rules

1. **0x00, 0x20 (scratch space):** Use freely between assembly statements. This is the cheapest memory available. Solady uses it for all `keccak256` hashing, temporary values, and return data.

2. **0x40 (free memory pointer):** You can temporarily overwrite it to avoid memory allocation costs, but you **must** save and restore the original value. Failing to do so corrupts all subsequent Solidity memory operations.

3. **0x60 (zero slot):** You can temporarily use it as extra scratch space (Solady does this to avoid allocating memory for call encoding), but you **must** write `0` back. Failing to do so corrupts zero-initialization of dynamic types.

4. **When you return immediately** (like these test contracts), resetting 0x40/0x60 is not strictly necessary because no Solidity code runs after. But in real internal functions that return control to Solidity, **always reset**.
