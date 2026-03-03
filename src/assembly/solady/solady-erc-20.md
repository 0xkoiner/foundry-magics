lib/solady-v0.1.26/src/tokens/ERC20.sol

This is Vectorized's gas-optimized ERC20 implementation — the most gas-efficient ERC20 in production today. It implements the standard ERC20 interface plus EIP-2612 (gasless approvals via permit) and native Permit2 integration, all written almost entirely in inline assembly.

Architecture at a Glance

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

  ---
  The 3 Big Design Decisions

  1. No State Variables — Custom Storage Layout

  Solidity normally assigns storage slots sequentially (slot 0, 1, 2...). Solady skips this entirely. Instead, it uses magic
  seed constants to compute storage slots via keccak256:

  balanceOf[owner]     → keccak256(owner . _BALANCE_SLOT_SEED)
  allowance[owner][sp] → keccak256(owner . _ALLOWANCE_SLOT_SEED . spender)
  nonces[owner]        → keccak256(owner . _NONCES_SLOT_SEED)
  totalSupply          → fixed at slot 0x05345cdf77eb68f44c

  Why? This avoids Solidity's mapping overhead (extra hashing, zero-padding to 32 bytes). Vectorized packs the address + seed
   into fewer bytes before hashing, saving gas on every keccak256.

  2. Everything Is Assembly

  Every function body is assembly { ... }. This gives Vectorized:
  - No ABI encoding overhead — calldata/memory is managed manually
  - No redundant checks — Solidity adds overflow checks, zero-address checks, etc. that ERC20 doesn't need
  - Precise memory control — heavy use of scratch space (0x00-0x3f) instead of allocating new memory
  - Optimal event emission — log3 called directly with pre-computed topics

  3. Native Permit2 Integration

  The contract treats Uniswap's Permit2 (0x000000000022D473030F116dDEE9F6B43aC78BA3) as a first-class citizen:
  - allowance() returns type(uint256).max for Permit2 without an sload
  - transferFrom() skips the allowance check entirely when caller() == _PERMIT2
  - approve() and permit() revert if you try to set Permit2's allowance to anything other than max
  - All controlled by _givePermit2InfiniteAllowance() — override to return false to disable

  ---
  Function Map

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

  ---
  Gas Tricks Summary

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

  ---
  This is the 30,000-foot view. Ready to dive into the first section? I'd suggest starting with Storage Layout (lines 72-98)
  — understanding how Vectorized computes storage slots is the key to reading everything else in this contract. Or pick any
  function you want to dissect first.


⏺ Solady ERC20 — Storage Layout Deep Dive                                                                                                                                                                        
                                                                                                                           
  uint256 private constant _TOTAL_SUPPLY_SLOT    = 0x05345cdf77eb68f44c;  // 9 bytes — fixed slot
  uint256 private constant _BALANCE_SLOT_SEED    = 0x87a211a2;            // 4 bytes — mapping seed
  uint256 private constant _ALLOWANCE_SLOT_SEED  = 0x7f5e9f20;            // 4 bytes — mapping seed
  uint256 private constant _NONCES_SLOT_SEED     = 0x38377508;            // 4 bytes — mapping seed

  These are not storage slots — they're ingredients for computing slots. Constants live in bytecode, not storage. They cost 0
   gas to access (they're inlined at compile time).

  ---
  Storage Map

  ╔══════════════════════════════════════════════════════════════════════╗
  ║                    SOLADY ERC20 STORAGE MAP                          ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                      ║
  ║  TOTAL SUPPLY                                                        ║
  ║  ┌─────────────────────────────────────────────────────────────┐     ║
  ║  │ Slot: 0x05345cdf77eb68f44c  (fixed, no hashing)             │     ║
  ║  │ Value: uint256 totalSupply                                  │     ║
  ║  │ Access: sload(0x05345cdf77eb68f44c)                         │     ║
  ║  └─────────────────────────────────────────────────────────────┘     ║
  ║                                                                      ║
  ║  BALANCES — mapping(address => uint256)                              ║
  ║  ┌─────────────────────────────────────────────────────────────┐     ║
  ║  │ Slot: keccak256(owner . 0x00000000 00000000 . 0x87a211a2)   │     ║
  ║  │                    ^^^20 bytes^^^  ^^8 bytes^^  ^^4 bytes^^ │     ║
  ║  │                         Total hash input: 32 bytes          │     ║
  ║  │ Value: uint256 balance                                      │     ║
  ║  └─────────────────────────────────────────────────────────────┘     ║
  ║                                                                      ║
  ║  ALLOWANCES — mapping(address => mapping(address => uint256))        ║
  ║  ┌─────────────────────────────────────────────────────────────┐     ║
  ║  │ Slot: keccak256(owner . 0x00..00 . 0x7f5e9f20 . spender)    │     ║
  ║  │                  ^^20^^  ^^8 bytes^^  ^^4 bytes^^  ^^20^^   │     ║
  ║  │                         Total hash input: 52 bytes          │     ║
  ║  │ Value: uint256 allowance                                    │     ║
  ║  └─────────────────────────────────────────────────────────────┘     ║
  ║                                                                      ║
  ║  NONCES — mapping(address => uint256)                                ║
  ║  ┌─────────────────────────────────────────────────────────────┐     ║
  ║  │ Slot: keccak256(owner . 0x00000000 00000000 . 0x38377508)   │     ║
  ║  │                  ^^20 bytes^^  ^^8 bytes^^      ^^4 bytes^^ │     ║
  ║  │                         Total hash input: 32 bytes          │     ║
  ║  │ Value: uint256 nonce                                        │     ║
  ║  └─────────────────────────────────────────────────────────────┘     ║
  ║                                                                      ║
  ║  ⚠️   Slots 0, 1, 2, 3... are COMPLETELY UNUSED                      ║
  ║  ⚠️   Inheriting contracts can safely declare state variables        ║
  ║                                                                      ║
  ╚══════════════════════════════════════════════════════════════════════╝

  ---
  How Each Slot Is Computed (Memory Diagrams)

  1. Total Supply — No Computation

  sload(0x05345cdf77eb68f44c)   // That's it. A fixed weird number.

  Why 0x05345cdf77eb68f44c? It's 9 bytes — too small to ever collide with a keccak256 output (which is 32 bytes, uniformly
  distributed). It also won't collide with Solidity's sequential slots (0, 1, 2...). It's a chosen "island" in the storage
  space that nothing else will touch.

  ---
  2. Balance Slot — balanceOf(owner)

  Code (line 158-160):
  mstore(0x0c, _BALANCE_SLOT_SEED)  // step 1
  mstore(0x00, owner)                // step 2 (overwrites part of step 1)
  keccak256(0x0c, 0x20)             // hash 32 bytes starting at 0x0c

  Step-by-step memory trace:

  After step 1: mstore(0x0c, 0x87a211a2)
  Write 32 bytes at offset 0x0c:

           0x0c                              0x2b
            │                                  │
            ▼                                  ▼
  Memory: [ 0000000000000000 0000000000000000 0000000000000000 00000000 87a211a2 ]
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
            Bytes 0x0c through 0x2b  (32 bytes, mostly zeros, seed at the end)


  After step 2: mstore(0x00, owner)    (e.g. owner = 0xABCD...1234)
  Write 32 bytes at offset 0x00 — this OVERWRITES bytes 0x0c-0x1f from step 1:

    0x00          0x0c                    0x1f  0x20       0x28    0x2b
     │             │                       │     │          │       │
     ▼             ▼                       ▼     ▼          ▼       ▼
   [ 000000000000  ABCDEF...........1234 | 0000000000000000 87a211a2 ]
     ^^^^^^^^^^^^  ^^^^^^^^^^^^^^^^^^^^    ^^^^^^^^^^^^^^^^ ^^^^^^^^
     12 zero bytes    20-byte address      8 zero bytes     4-byte seed
     (addr padding)   (from step 2)        (survived step1) (survived step1)


  keccak256(0x0c, 0x20) hashes this 32-byte region:
           ┌──────────────────────────────────────────────────┐
           │ ABCDEF...1234  00000000 00000000  87a211a2       │
           │ ◄─20 bytes──►  ◄──8 zero bytes─►  ◄─4 bytes─►    │
           └──────────────────────────────────────────────────┘
                          = balance storage slot

  The trick: The two mstores overlap! The owner's address (last 20 bytes of mstore(0x00)) lands right where step 1's leading
  zeros were, and the seed 87a211a2 at the tail survives because mstore(0x00) only reaches byte 0x1f.

  ---
  3. Allowance Slot — allowance(owner, spender)

  Code (line 176-179):
  mstore(0x20, spender)              // step 1
  mstore(0x0c, _ALLOWANCE_SLOT_SEED) // step 2
  mstore(0x00, owner)                // step 3
  keccak256(0x0c, 0x34)              // hash 52 bytes starting at 0x0c

  After step 1: mstore(0x20, spender)

    0x20          0x2c                    0x3f
     │             │                       │
     ▼             ▼                       ▼
   [ 000000000000  SPENDER_ADDRESS_20B     ]
     ^^^^^^^^^^^^  ^^^^^^^^^^^^^^^^^^^^^^^^
     12 zero pad   20-byte spender


  After step 2: mstore(0x0c, 0x7f5e9f20)
  Writes at 0x0c-0x2b. Overwrites 0x20-0x2b (spender's zero padding), but
  spender's address at 0x2c-0x3f SURVIVES:

    0x0c                              0x28    0x2b 0x2c              0x3f
     │                                 │       │    │                 │
     ▼                                 ▼       ▼    ▼                 ▼
   [ 00000000000000000000000000000000  7f5e9f20  |  SPENDER_ADDR_20B  ]
     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^  ^^^^^^^^     ^^^^^^^^^^^^^^^^^^
     28 bytes of zeros (padding)       4-byte seed  untouched from step 1


  After step 3: mstore(0x00, owner)
  Writes at 0x00-0x1f. Overwrites 0x0c-0x1f zeros from step 2:

    0x0c              0x1f 0x20       0x28    0x2b 0x2c              0x3f
     │                 │    │          │       │    │                 │
     ▼                 ▼    ▼          ▼       ▼    ▼                 ▼
   [ OWNER_ADDR_20B  |  00000000  7f5e9f20  |  SPENDER_ADDR_20B      ]


  keccak256(0x0c, 0x34) hashes this 52-byte region:
  ┌─────────────────────────────────────────────────────────────────────┐
  │ OWNER_20B  00000000 00000000  7f5e9f20  00000000 0000  SPENDER_20B. │
  │ ◄──20 B──► ◄────8 zero B───► ◄─4 B──►  ◄──12 zero B─► ◄──20 B──►.   │
  └─────────────────────────────────────────────────────────────────────┘
                          = allowance storage slot

  Wait — let me correct the spender part. The 12 zero bytes before spender come from step 1's mstore(0x20, spender)
  left-padding, but step 2 wrote over 0x20-0x2b. So bytes 0x20-0x27 are zeros from step 2's padding, and 0x28-0x2b is the
  seed. Then 0x2c-0x3f is the spender address. Let me redraw cleanly:

  keccak256(0x0c, 0x34) hashes 52 bytes:
  ┌─────────────────────────────────────────────────────────┐
  │  OWNER       ZEROS     SEED       SPENDER               │
  │  ◄─20 B──►  ◄─8 B──►  ◄─4 B──►  ◄────20 B──────────►    │
  │  0x0c-0x1f  0x20-0x27  0x28-0x2b  0x2c-0x3f             │
  └─────────────────────────────────────────────────────────┘

  Both addresses and the seed in ONE hash — this is a single keccak256 for a nested mapping that Solidity would compute with
  two separate keccak256 calls.

  ---
  4. Nonce Slot — Same Pattern as Balance

  keccak256(0x0c, 0x20) over:
  ┌──────────────────────────────────────────────────┐
  │  OWNER       ZEROS        SEED                   │
  │  ◄─20 B──►  ◄──8 B───►   ◄─4 B──►                │
  │  address     00000000..   38377508               │
  └──────────────────────────────────────────────────┘

  ---
  The or() Optimization (Internal Functions)

  In balanceOf (external), Vectorized uses two mstores. But in _transfer (line 563-565) he uses a single combined write:

  let from_ := shl(96, from)
  mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))

  This works because:

  shl(96, from):
    0xABCDEF...1234  000000000000 00000000 00000000
    ◄──20 byte addr─► ◄────12 bytes of zeros────────►

  or() with _BALANCE_SLOT_SEED (0x87a211a2):
    0xABCDEF...1234  000000000000 00000000 87a211a2
    ◄──20 byte addr─► ◄──8 zeros──► ◄────4 seed────►

  Single mstore(0x0c, result) → same memory layout as the 2-mstore version

  Saves 1 mstore (3 gas) + the mload setup on every internal transfer/approve. Small savings, but these functions are called
  millions of times.

  ---
  Comparison: Solidity vs Solady Slot Computation

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

  Gas savings:
    Balance lookup:    32 vs 64 bytes hashed → ~50% less keccak gas
    Allowance lookup:  52 bytes + 1 hash vs 128 bytes + 2 hashes → ~60% less

  ---
  Collision Safety

  Why won't these slots collide with each other or with inheriting contracts?

  1. Balance vs Nonce vs Allowance — Different seeds (87a211a2 vs 38377508 vs 7f5e9f20) at the same position means different
  hash inputs → different slots
  2. Total Supply — Fixed at 0x05345cdf77eb68f44c, a 9-byte value. All keccak256 outputs are 32 bytes with uniform
  distribution — the probability of collision is negligible (~2^-200)
  3. Inheriting contracts — If they declare normal state variables, Solidity assigns slots 0, 1, 2... These tiny numbers
  won't collide with keccak256 outputs or the total supply slot
  4. Solady's other contracts — Use different seed constants, so the hash inputs are always distinct