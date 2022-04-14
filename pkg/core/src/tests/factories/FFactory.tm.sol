// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { FAdapter } from "../../adapters/fuse/FAdapter.sol";
import { FFactory } from "../../adapters/fuse/FFactory.sol";
import { BaseFactory } from "../../adapters/BaseFactory.sol";
import { Divider, TokenHandler } from "../../Divider.sol";

import { DSTest } from "../test-helpers/DSTest.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { User } from "../test-helpers/User.sol";
import { Assets } from "../test-helpers/Assets.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Hevm } from "../test-helpers/Hevm.sol";

contract FAdapterTestHelper is DSTest {
    FFactory internal factory;
    Divider internal divider;
    TokenHandler internal tokenHandler;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    uint16 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    function setUp() public {
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = Assets.COMP;

        // deploy fuse adapter factory
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
        factory = new FFactory(address(divider), factoryParams);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
    }
}

contract FFactories is FAdapterTestHelper {
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
        FFactory otherFFactory = new FFactory(address(divider), factoryParams);

        assertTrue(address(otherFFactory) != address(0));
        (
            address oracle,
            uint256 ifee,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint16 mode,
            uint64 tilt
        ) = FFactory(otherFFactory).factoryParams();

        assertEq(FFactory(otherFFactory).divider(), address(divider));
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
        // At block 14570060, Convex Tribe Pool has 4 rewards distributors with CVX, CRV, LDO and FXS reward tokens
        // asset --> rewards:
        // FRAX3CRV --> CVX and CRV
        // cvxFXSFXS-f --> CVX, CRV and FXS
        // CVX --> no rewards
        hevm.roll(14561510);
        divider.setPeriphery(address(this));
        address f = factory.deployAdapter(Assets.f156FRAX3CRV, abi.encode(Assets.TRIBE_CONVEX));
        FAdapter adapter = FAdapter(payable(f));
        assertTrue(address(adapter) != address(0));
        assertEq(FAdapter(adapter).target(), address(Assets.f156FRAX3CRV));
        assertEq(FAdapter(adapter).divider(), address(divider));
        assertEq(FAdapter(adapter).name(), "Tribe Convex Pool Curve.fi Factory USD Metapool: Frax Adapter");
        assertEq(FAdapter(adapter).symbol(), "fFRAX3CRV-f-156-adapter");
        assertEq(FAdapter(adapter).rewardTokens(0), Assets.CVX);
        assertEq(FAdapter(adapter).rewardTokens(1), Assets.CRV);
        assertEq(FAdapter(adapter).rewardTokens(2), address(0));
        assertEq(FAdapter(adapter).rewardTokens(3), address(0));

        uint256 scale = FAdapter(adapter).scale();
        assertTrue(scale > 0);
    }

    function testMainnetCantDeployAdapterIfInvalidComptroller() public {
        divider.setPeriphery(address(this));
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector));
        factory.deployAdapter(Assets.f18DAI, abi.encode(Assets.f18DAI));
    }

    function testMainnetCantDeployAdapterIfNotSupportedTarget() public {
        divider.setPeriphery(address(this));
        hevm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        factory.deployAdapter(Assets.f18DAI, abi.encode(Assets.TRIBE_CONVEX));
    }
}
