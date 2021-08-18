pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "../Divider.sol";

contract DividerTest is DSTest {
    Divider divider;

    function setUp() public {
        divider = new Divider();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
