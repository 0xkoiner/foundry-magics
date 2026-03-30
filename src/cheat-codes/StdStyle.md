# ELI5: StdStyle

## What is StdStyle?

**What It Is:**

`StdStyle` is a forge-std library that adds **ANSI color and font styling** to `console.log` output in your Foundry tests. It wraps your log text with terminal escape codes so you get colored, bold, italic, underlined (and more) output right in your terminal.

**Import:**
```solidity
import {StdStyle} from "forge-std/Test.sol";
```

**Why It's Useful:**

1. **Readable test output** - Instantly spot errors (red) vs successes (green) in long test logs
2. **Visual separation** - Use colored dividers to group log sections
3. **Highlight important values** - Make addresses, balances, or flags stand out
4. **Custom heading helpers** - Build reusable `h1()` / `h2()` functions for consistent formatting

## How It Works Under the Hood

StdStyle uses **ANSI escape codes** — special character sequences that terminals interpret as formatting instructions rather than printable text.

**The Format:**
```
\u001b[<code>m
  ^        ^
  ESC    code number + terminator
```

**The Core Function — `styleConcat`:**
```solidity
function styleConcat(string memory style, string memory self) private pure returns (string memory) {
    return string(abi.encodePacked(style, self, RESET));
}
```

It wraps your text like this:

```
┌──────────────┬────────────────────┬──────────────┐
│  ANSI Code   │    Your Text       │    RESET     │
│  \u001b[91m  │  "Hello World"     │  \u001b[0m   │
├──────────────┼────────────────────┼──────────────┤
│  Turn ON     │  Displayed with    │  Turn OFF    │
│  red color   │  red styling       │  all styles  │
└──────────────┴────────────────────┴──────────────┘
```

**Key detail:** The `RESET` code (`\u001b[0m`) at the end prevents style bleed — without it, every log line after a styled one would inherit that style.

**Non-string types** (uint256, int256, address, bool, bytes, bytes32) are first converted to strings via `vm.toString()` before styling:
```solidity
function red(uint256 self) internal pure returns (string memory) {
    return red(vm.toString(self));  // convert to string, then style
}
```

## Available Colors — Reference Table

| Color   | ANSI Code     | Function               |
|---------|---------------|------------------------|
| Red     | `\u001b[91m`  | `StdStyle.red()`       |
| Green   | `\u001b[92m`  | `StdStyle.green()`     |
| Yellow  | `\u001b[93m`  | `StdStyle.yellow()`    |
| Blue    | `\u001b[94m`  | `StdStyle.blue()`      |
| Magenta | `\u001b[95m`  | `StdStyle.magenta()`   |
| Cyan    | `\u001b[96m`  | `StdStyle.cyan()`      |

> These are "bright" variants (codes 91–96). Standard ANSI colors (31–36) are dimmer and not used by StdStyle.

## Available Font Styles — Reference Table

| Style     | ANSI Code    | Function                 |
|-----------|--------------|--------------------------|
| Bold      | `\u001b[1m`  | `StdStyle.bold()`        |
| Dim       | `\u001b[2m`  | `StdStyle.dim()`         |
| Italic    | `\u001b[3m`  | `StdStyle.italic()`      |
| Underline | `\u001b[4m`  | `StdStyle.underline()`   |
| Inverse   | `\u001b[7m`  | `StdStyle.inverse()`     |

> **Inverse** swaps foreground and background colors — useful for creating "highlighted" text blocks.

## Supported Type Overloads

Every style family (11 total: 6 colors + 5 font styles) provides **7 overloads** for different Solidity types:

| Type      | Function Name         | Example                              |
|-----------|-----------------------|--------------------------------------|
| `string`  | `red()`               | `StdStyle.red("error!")`            |
| `uint256` | `red()`               | `StdStyle.red(uint256(42))`         |
| `int256`  | `red()`               | `StdStyle.red(int256(-1))`          |
| `address` | `red()`               | `StdStyle.red(address(this))`       |
| `bool`    | `red()`               | `StdStyle.red(true)`                |
| `bytes`   | `redBytes()`          | `StdStyle.redBytes(hex"cafe")`      |
| `bytes32` | `redBytes32()`        | `StdStyle.redBytes32("hello")`      |

**Naming convention:** The first 5 types use Solidity's function overloading (`red()` handles string, uint256, int256, address, bool automatically). `bytes` and `bytes32` need distinct names to avoid ambiguity, so they use a suffix: `redBytes()` and `redBytes32()`.

**Total functions in the library:** 11 families x 7 overloads = **77 functions**.

## Usage Examples — from TestStdStyle.t.sol

### Basic Colors

From `test_std_style_colors()`:

```solidity
import {Test, console2 as console, StdStyle} from "forge-std/Test.sol";

// String styling
console.log(StdStyle.red("This is a red log message."));
console.log(StdStyle.green("This is a green log message."));
console.log(StdStyle.blue("This is a blue log message."));

// Non-string types — each converted via vm.toString() automatically
console.log(StdStyle.red(address(this)));            // address
console.log(StdStyle.green(true));                    // bool
console.log(StdStyle.blue(uint256(10e18)));           // uint256
console.log(StdStyle.magenta(int256(-10e18)));        // int256

// bytes and bytes32 use the suffix variants
console.log(StdStyle.cyanBytes(hex"7109709ECfa91a80626fF3989D68f67F5b1DD12D"));
console.log(StdStyle.cyanBytes32("StdStyle.cyanBytes32"));

// Yellow dividers for visual separation
console.log(StdStyle.yellow("--------------------------------------------------"));
```

### Font Weight & Styling

From `test_std_style_font_weight()`:

```solidity
console.log(StdStyle.bold("StdStyle.bold String Test"));   // bold string
console.log(StdStyle.dim(uint256(10e18)));                  // dim uint256
console.log(StdStyle.italic(int256(-10e18)));               // italic int256
console.log(StdStyle.underline(address(0)));                // underlined address

console.log(StdStyle.inverse(true));                        // inverse bool
console.log(StdStyle.inverseBytes(hex"7109709ECfa91a80626fF3989D68f67F5b1DD12D"));
console.log(StdStyle.inverseBytes32("StdStyle.inverseBytes32"));
```

### Combining Styles

From `test_std_style_combine()` — nest calls to apply both a color **and** a font style:

```solidity
// Inner call styles first, outer call wraps with additional style
console.log(StdStyle.red(StdStyle.bold("Red Bold String Test")));
console.log(StdStyle.green(StdStyle.dim(uint256(10e18))));
console.log(StdStyle.yellow(StdStyle.italic(int256(-10e18))));
console.log(StdStyle.blue(StdStyle.underline(address(0))));
console.log(StdStyle.magenta(StdStyle.inverse(true)));
```

**How nesting works:**
```
StdStyle.red(StdStyle.bold("Hello"))

Expands to:
  \u001b[91m  \u001b[1m  Hello  \u001b[0m  \u001b[0m
  ^red        ^bold       ^text   ^reset    ^reset
```
The terminal applies both escape codes — you get red **and** bold.

### Custom Helpers

From `test_std_style_custom()` — create reusable formatting functions:

```solidity
contract TestStdStyle {
    function test_std_style_custom() external {
        console.log(h1("Custom Style 1"));  // cyan + inverse + bold
        console.log(h2("Custom Style 2"));  // magenta + bold + underline
    }

    function h1(string memory a) private pure returns (string memory) {
        return StdStyle.cyan(StdStyle.inverse(StdStyle.bold(a)));
    }

    function h2(string memory a) private pure returns (string memory) {
        return StdStyle.magenta(StdStyle.bold(StdStyle.underline(a)));
    }
}
```

This pattern is great for consistent test output formatting across your entire test suite.

## Running the Tests

```bash
forge test --match-contract TestStdStyle -vvv
```

> **Note:** ANSI colors render in **terminal output only**. If you pipe output to a file or run in CI, colors may appear as raw escape codes. Use `--color always` with forge or pipe through `less -R` to preserve colors.

## Key Takeaways

1. **StdStyle adds color and font styling** to `console.log` output using ANSI escape codes
2. **6 colors** (red, green, yellow, blue, magenta, cyan) and **5 font styles** (bold, dim, italic, underline, inverse)
3. **7 type overloads per style** — string, uint256, int256, address, bool, plus `Bytes()` / `Bytes32()` suffix variants
4. **77 total functions** (11 style families x 7 types)
5. **Combine styles by nesting** — `StdStyle.red(StdStyle.bold("text"))` for red + bold
6. **Build custom helpers** — wrap nested calls in `h1()` / `h2()` functions for reusable formatting
7. **RESET prevents bleed** — each styled string is automatically terminated with `\u001b[0m`
8. **Testing only** — styles render in terminal, not on-chain
