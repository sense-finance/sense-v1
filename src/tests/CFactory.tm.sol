// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { CAdapter } from "../adapters/compound/CAdapter.sol";
import { CFactory } from "../adapters/compound/CFactory.sol";
import { BaseFactory } from "../adapters/BaseFactory.sol";
import { Divider, TokenHandler } from "../Divider.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

contract CAdapterTestHelper is DSTest {
    CFactory internal factory;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D; // rari's oracle

    uint8 public constant MODE = 0;
    uint256 public constant DELTA = 150;
    uint256 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    function setUp() public {
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));
        CAdapter adapterImpl = new CAdapter(); // compound adapter implementation
        // deploy compound adapter factory
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: DAI,
            oracle: ORACLE,
            delta: DELTA,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE
        });
        factory = new CFactory(address(divider), address(adapterImpl), factoryParams, COMP);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
    }
}

contract CFactories is CAdapterTestHelper {
    function testDeployFactory() public {
        CAdapter adapterImpl = new CAdapter();
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: DAI,
            oracle: ORACLE,
            delta: DELTA,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE
        });
        CFactory otherCFactory = new CFactory(address(divider), address(adapterImpl), factoryParams, COMP);

        assertTrue(address(otherCFactory) != address(0));
        (
            address oracle,
            uint256 delta,
            uint256 ifee,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint8 mode
        ) = CFactory(otherCFactory).factoryParams();
        assertEq(CFactory(otherCFactory).adapterImpl(), address(adapterImpl));
        assertEq(CFactory(otherCFactory).divider(), address(divider));
        assertEq(delta, DELTA);
        assertEq(CFactory(otherCFactory).reward(), COMP);
        assertEq(stake, DAI);
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, MODE);
    }

    function testDeployAdapter() public {
        address f = factory.deployAdapter(cDAI);
        CAdapter adapter = CAdapter(f);
        (, , uint256 delta, , , , , , ) = CAdapter(adapter).adapterParams();
        assertTrue(address(adapter) != address(0));
        assertEq(CAdapter(adapter).getTarget(), address(cDAI));
        assertEq(CAdapter(adapter).divider(), address(divider));
        assertEq(delta, DELTA);
        assertEq(CAdapter(adapter).name(), "Compound Dai Adapter");
        assertEq(CAdapter(adapter).symbol(), "cDAI-adapter");

        uint256 scale = CAdapter(adapter).scale();
        assertTrue(scale > 0);
    }
}
