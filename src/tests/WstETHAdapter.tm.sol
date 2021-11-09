// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider, TokenHandler } from "../Divider.sol";
import { WstETHAdapter, WstETHInterface } from "../adapters/lido/WstETHAdapter.sol";
import { BaseAdapter } from "../adapters/BaseAdapter.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

contract WstETHAdapterTestHelper is DSTest {
    WstETHAdapter adapter;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    uint256 public constant DELTA = 150;
    uint256 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    address public constant ORACLE = 0x6D2299C48a8dD07a872FDd0F8233924872Ad1071; // compound's oracle

    function setUp() public {
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));
        adapter = new WstETHAdapter(); // wstETH adapter
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: WSTETH,
            delta: DELTA,
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stake: DAI,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0
        });
        adapter.initialize(address(divider), adapterParams);
    }
}

contract WstETHAdapters is WstETHAdapterTestHelper {
    using FixedMath for uint256;

    function testWstETHAdapterScale() public {
        WstETHInterface wstETH = WstETHInterface(WSTETH);

        uint256 scale = wstETH.stEthPerToken();
        assertEq(adapter.scale(), scale);
    }

    function testGetUnderlyingPrice() public {
        return;
        // TODO: to be implemented on tests refactors
    }

    function testUnwrapTarget() public {
        return;
        // TODO: to be implemented on tests refactors
    }

    function testWrapUnderlying() public {
        return;
        // TODO: to be implemented on tests refactors
    }
}
