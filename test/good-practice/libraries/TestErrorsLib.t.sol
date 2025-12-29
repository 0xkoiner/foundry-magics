// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ErrorsLib } from "src/good-practice/libraries/ErrorsLib.sol";
import { Test, console2 as console } from "lib/forge-std/src/Test.sol";

contract TestErrorsLib is Test {
    function test_string_errors() external pure {
        if (true) {
            console.log("ErrorsLib.ONLY_OWNER:", ErrorsLib.ONLY_OWNER);
            console.log("ErrorsLib.CANT_BE_ZERO_ADDRESS", ErrorsLib.CANT_BE_ZERO_ADDRESS);
        }
    }

    function test_custom_errors() external pure {
        if (true) {
            console.log("ErrorsLib.ERRORS__ONLY_OWNER:");
            console.logBytes4(ErrorsLib.ERRORS__ONLY_OWNER.selector);

            console.log("ErrorsLib.ERRORS__CANT_BE_ZERO_ADDRESS:");
            console.logBytes4(ErrorsLib.ERRORS__CANT_BE_ZERO_ADDRESS.selector);
        }
    }
}
