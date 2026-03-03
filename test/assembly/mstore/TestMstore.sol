// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test, console2 as console } from "lib/forge-std/src/Test.sol";
import { MstoreA, MstoreB, MstoreC, MstoreD } from "../../../src/assembly/mstore/Mstore.sol";

contract TestMstore is Test {
    MstoreA mstoreA;
    MstoreB mstoreB;
    MstoreC mstoreC;
    MstoreD mstoreD;

    function setUp() public {
        mstoreA = new MstoreA();
        mstoreB = new MstoreB();
        mstoreC = new MstoreC();
        mstoreD = new MstoreD();
    }

    function test_MstoreA() external {
        vm.prank(address(0xcafe));
        mstoreA.writeMemoryYul();
        vm.snapshotGasLastCall("test_MstoreA");
    }

    function test_MstoreB() external {
        vm.prank(address(0xcafe));
        mstoreB.writeMemoryYul();
        vm.snapshotGasLastCall("test_MstoreB");
    }

    function test_MstoreC() external {
        vm.prank(address(0xcafe));
        mstoreC.writeMemoryYul();
        vm.snapshotGasLastCall("test_MstoreC");
    }

    function test_MstoreD() external {
        vm.prank(address(0xcafe));
        mstoreD.writeMemoryYul();
        vm.snapshotGasLastCall("test_MstoreD");
    }
}
