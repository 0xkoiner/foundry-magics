// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Errors {
    error ERRORS__CANT_BE_ZERO_ADDRESS();
    error ERRORS__ONLY_OWNER();

    string constant internal CANT_BE_ZERO_ADDRESS = "Can't be Zero Address";
    string constant internal ONLY_OWNER = "Only Owner";
}
