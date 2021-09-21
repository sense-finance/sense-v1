// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./test-helpers/Hevm.sol";
import { DSTest } from "ds-test/test.sol";
import { GClaim } from "../modules/GClaim.sol";

contract DividerMock {}

contract GClaims is DSTest {
    GClaim gclaim;
    DividerMock dividerMock;
    Hevm hevm;

    uint256 constant startTime = 604411200;

    function setUp() public {
        hevm = Hevm(address(HEVM_ADDRESS));
        hevm.warp(startTime);

        dividerMock = new DividerMock();
        gclaim = new GClaim(address(dividerMock));
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
