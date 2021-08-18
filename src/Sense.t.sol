pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./Sense.sol";

contract SenseTest is DSTest {
    Sense sense;

    function setUp() public {
        sense = new Sense();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
