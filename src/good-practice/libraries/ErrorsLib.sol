// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library ErrorsLib {
    error ERRORS__ONLY_OWNER();
    error ERRORS__CANT_BE_ZERO_ADDRESS();

    string internal constant ONLY_OWNER = "Only Owner";
    string internal constant CANT_BE_ZERO_ADDRESS = "Can't be Zero Address";
}
