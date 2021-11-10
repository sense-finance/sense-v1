// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider, TokenHandler } from "../Divider.sol";
import { WstETHAdapter, WstETHInterface, PriceOracleInterface } from "../adapters/lido/WstETHAdapter.sol";
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
    address public constant ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D; // rari's oracle
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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
        PriceOracleInterface oracle = PriceOracleInterface(ORACLE);
        uint256 price = oracle.price(WETH);
        assertEq(adapter.getUnderlyingPrice(), price);
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
