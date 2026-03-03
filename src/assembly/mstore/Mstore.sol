// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

bytes32 constant __FF__ = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

contract MstoreA {
    function writeMemoryYul() external pure returns (bytes32 res) {
        // 320 gas
        assembly {
            mstore(0x00, __FF__)
            res := mload(0x00)
        }
    }
}

contract MstoreB {
    function writeMemoryYul() external pure returns (bytes32 res) {
        // 322 gas
        assembly {
            mstore(0x20, __FF__)
            res := mload(0x20)
        }
    }
}

contract MstoreC {
    function writeMemoryYul() external pure returns (bytes32 res) {
        // 324 gas
        assembly {
            mstore(0x40, __FF__)
            res := mload(0x40)
            mstore(0x40, 0x0)
        }
    }
}

contract MstoreD {
    function writeMemoryYul() external pure returns (bytes32 res) {
        // 322 gas
        assembly {
            mstore(0x60, __FF__)
            res := mload(0x60)
        }
    }
}
