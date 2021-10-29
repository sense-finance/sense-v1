// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./Invariant.sol";

contract InvariantTest is DSTest {
    Invariant invariant;

    function setUp() public {
        invariant = new Invariant();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
