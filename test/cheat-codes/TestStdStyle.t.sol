// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console2 as console, StdStyle} from "forge-std/Test.sol";

contract TestStdStyle {
    function test_std_style_colors() external {
        console.log("This is a normal log message.");

        console.log(StdStyle.yellow("--------------------------------------------------"));
        console.log(StdStyle.yellow("--------------------------------------------------"));

        console.log(StdStyle.red("This is a red log message."));
        console.log(StdStyle.green("This is a green log message."));
        console.log(StdStyle.blue("This is a blue log message."));

        console.log(StdStyle.yellow("--------------------------------------------------"));
        console.log(StdStyle.yellow("--------------------------------------------------"));

        console.log(StdStyle.red(address(this)));
        console.log(StdStyle.green(true));
        console.log(StdStyle.blue(uint256(10e18)));
        console.log(StdStyle.magenta(int256(-10e18)));
        console.log(StdStyle.cyanBytes(hex"7109709ECfa91a80626fF3989D68f67F5b1DD12D"));
        console.log(StdStyle.cyanBytes32("StdStyle.cyanBytes32"));

        console.log(StdStyle.yellow("--------------------------------------------------"));
        console.log(StdStyle.yellow("--------------------------------------------------"));
    }

    function test_std_style_font_weight() external { 
        console.log("This is a normal log message.");

        console.log(StdStyle.yellow("--------------------------------------------------"));
        console.log(StdStyle.yellow("--------------------------------------------------"));

        console.log(StdStyle.bold("StdStyle.bold String Test"));
        console.log(StdStyle.dim(uint256(10e18)));
        console.log(StdStyle.italic(int256(-10e18)));
        console.log(StdStyle.underline(address(0)));

        console.log(StdStyle.inverse(true));
        console.log(StdStyle.inverseBytes(hex"7109709ECfa91a80626fF3989D68f67F5b1DD12D"));
        console.log(StdStyle.inverseBytes32("StdStyle.inverseBytes32"));

        console.log(StdStyle.yellow("--------------------------------------------------"));
        console.log(StdStyle.yellow("--------------------------------------------------"));

    }

    function test_std_style_combine() external {
        console.log("This is a normal log message.");

        console.log(StdStyle.yellow("--------------------------------------------------"));
        console.log(StdStyle.yellow("--------------------------------------------------"));

        console.log(StdStyle.red(StdStyle.bold("Red Bold String Test")));
        console.log(StdStyle.green(StdStyle.dim(uint256(10e18))));
        console.log(StdStyle.yellow(StdStyle.italic(int256(-10e18))));
        console.log(StdStyle.blue(StdStyle.underline(address(0))));
        console.log(StdStyle.magenta(StdStyle.inverse(true)));

        console.log(StdStyle.yellow("--------------------------------------------------"));
        console.log(StdStyle.yellow("--------------------------------------------------"));
    }

    function test_std_style_custom() external {
        console.log("This is a normal log message.");

        console.log(StdStyle.yellow("--------------------------------------------------"));
        console.log(StdStyle.yellow("--------------------------------------------------"));

        console.log(h1("Custom Style 1"));
        console.log(h2("Custom Style 2"));

        console.log(StdStyle.yellow("--------------------------------------------------"));
        console.log(StdStyle.yellow("--------------------------------------------------"));
    }

    function h1(string memory a) private pure returns (string memory) {
        return StdStyle.cyan(StdStyle.inverse(StdStyle.bold(a)));
    }

    function h2(string memory a) private pure returns (string memory) {
        return StdStyle.magenta(StdStyle.bold(StdStyle.underline(a)));
    }
}