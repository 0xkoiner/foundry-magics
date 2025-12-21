// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library EventsLib {
    event RevokeSinger(address _revokedSigner);

    event NewOwner(address _oldOwner, address _newOwner);
}
