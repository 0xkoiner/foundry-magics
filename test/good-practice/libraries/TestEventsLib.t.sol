// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "lib/forge-std/src/Test.sol";
import { EventsLib } from "src/good-practice/libraries/EventsLib.sol";

contract TestEventsLib is Test {
    function test_events() external {
        Events events = new Events();

        // Test NewOwner event
        vm.expectEmit(true, true, true, true);
        emit EventsLib.NewOwner(address(0xdead), address(0xbabe));
        events.newOwner();

        // Test RevokeSinger event
        vm.expectEmit(true, true, true, true);
        emit EventsLib.RevokeSinger(address(0xdeadbeef));
        events.revokeSigner();
    }
}

contract Events {
    function newOwner() external {
        emit EventsLib.NewOwner(address(0xdead), address(0xbabe));
    }

    function revokeSigner() external {
        emit EventsLib.RevokeSinger(address(0xdeadbeef));
    }
}
