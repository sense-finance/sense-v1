// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// Internal references
import { CAdapter } from "../adapters/compound/CAdapter.sol";
import { CFactory } from "../adapters/compound/CFactory.sol";
import { BaseFactory } from "../adapters/BaseFactory.sol";
import { Divider, TokenHandler } from "../Divider.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";
import { Assets } from "./test-helpers/Assets.sol";

contract CAdapterTestHelper is DSTest {
    CFactory internal factory;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    uint16 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint48 public constant MIN_MATURITY = 2 weeks;
    uint48 public constant MAX_MATURITY = 14 weeks;

    function setUp() public {
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        // deploy compound adapter factory
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: Assets.DAI,
            oracle: Assets.RARI_ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0
        });
        factory = new CFactory(address(divider), factoryParams, Assets.COMP);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
    }
}

contract CFactories is CAdapterTestHelper {
    function testMainnetDeployFactory() public {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: Assets.DAI,
            oracle: Assets.RARI_ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0
        });
        CFactory otherCFactory = new CFactory(address(divider), factoryParams, Assets.COMP);

        assertTrue(address(otherCFactory) != address(0));
        (
            address oracle,
            uint64 ifee,
            address stake,
            uint256 stakeSize,
            uint48 minm,
            uint48 maxm,
            uint16 mode,
            uint64 tilt
        ) = CFactory(otherCFactory).factoryParams();

        assertEq(CFactory(otherCFactory).divider(), address(divider));
        assertEq(CFactory(otherCFactory).reward(), Assets.COMP);
        assertEq(stake, Assets.DAI);
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, MODE);
        assertEq(oracle, Assets.RARI_ORACLE);
        assertEq(tilt, 0);
    }

    function testMainnetDeployAdapter() public {
        address f = factory.deployAdapter(Assets.cDAI);
        CAdapter adapter = CAdapter(payable(f));
        assertTrue(address(adapter) != address(0));
        assertEq(CAdapter(adapter).target(), address(Assets.cDAI));
        assertEq(CAdapter(adapter).divider(), address(divider));
        assertEq(CAdapter(adapter).name(), "Compound Dai Adapter");
        assertEq(CAdapter(adapter).symbol(), "cDAI-adapter");

        uint256 scale = CAdapter(adapter).scale();
        assertTrue(scale > 0);
    }
}
