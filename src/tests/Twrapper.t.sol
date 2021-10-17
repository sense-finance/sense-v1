// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "solmate/erc20/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

import { Errors } from "../libs/errors.sol";
import { BaseFeed } from "../feeds/BaseFeed.sol";
import { Divider } from "../Divider.sol";
import { BaseTWrapper } from "../wrappers/BaseTWrapper.sol";

import { MockFeed } from "./test-helpers/mocks/MockFeed.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";

contract FakeFeed is BaseFeed {
    function _scale() internal virtual override returns (uint256 _value) {
        _value = 100e18;
    }

    function doSetFeed(Divider d, address _feed) public {
        d.setFeed(_feed, true);
    }
}

contract tWrappers is TestHelper {
    using FixedMath for uint256;

    function testTWrapperHasParams() public {
        MockToken reward = new MockToken("Reward Airdrop Token", "RAT", 18);
        MockToken target = new MockToken("Compound Dai", "cDAI", 18);
        BaseTWrapper tWrapper = new BaseTWrapper();
        tWrapper.initialize(address(target), address(divider), address(reward));

        assertEq(tWrapper.target(), address(target));
        assertEq(tWrapper.divider(), address(divider));
        assertEq(tWrapper.reward(), address(reward));
    }

    function testDistributeSingleUser() public {}

    function testDistributeMultipleUsers() public {}

    function testDistributeWithClaim() public {}

    function testDistributeZero() public {}
}
