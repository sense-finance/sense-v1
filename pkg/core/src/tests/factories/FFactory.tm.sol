// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { FAdapter } from "../../adapters/implementations/fuse/FAdapter.sol";
import { FFactory } from "../../adapters/implementations/fuse/FFactory.sol";
import { BaseFactory } from "../../adapters/abstract/factories/BaseFactory.sol";
import { Divider, TokenHandler } from "../../Divider.sol";

import { DSTest } from "../test-helpers/test.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { AddressBook } from "../test-helpers/AddressBook.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { Constants } from "../test-helpers/Constants.sol";

contract FAdapterTestHelper is DSTest {
    FFactory internal factory;
    Divider internal divider;
    TokenHandler internal tokenHandler;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    uint8 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint256 public constant DEFAULT_GUARD = 100000 * 1e18;

    function setUp() public {
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = AddressBook.COMP;

        // deploy fuse adapter factory
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: AddressBook.DAI,
            oracle: AddressBook.RARI_ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            rType: Constants.CROPS,
            tilt: 0,
            guard: DEFAULT_GUARD
        });
        factory = new FFactory(address(divider), Constants.REWARDS_RECIPIENT, factoryParams);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
    }
}

contract FFactories is FAdapterTestHelper {
    function testMainnetDeployFactory() public {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: AddressBook.DAI,
            oracle: AddressBook.RARI_ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            rType: Constants.CROPS,
            tilt: 0,
            guard: DEFAULT_GUARD
        });
        FFactory otherFFactory = new FFactory(address(divider), Constants.REWARDS_RECIPIENT, factoryParams);

        assertTrue(address(otherFFactory) != address(0));
        (
            address oracle,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint256 ifee,
            uint8 mode,
            uint8 rType,
            uint64 tilt,
            uint256 guard
        ) = FFactory(otherFFactory).factoryParams();

        assertEq(FFactory(otherFFactory).divider(), address(divider));
        assertEq(stake, AddressBook.DAI);
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, MODE);
        assertEq(rType, Constants.CROPS);
        assertEq(oracle, AddressBook.RARI_ORACLE);
        assertEq(tilt, 0);
        assertEq(guard, DEFAULT_GUARD);
    }

    function testMainnetDeployAdapter() public {
        // At block 14603884, Convex Tribe Pool has 4 rewards distributors with CVX, CRV, LDO and FXS reward tokens
        // asset --> rewards:
        // FRAX3CRV --> CVX and CRV
        // cvxFXSFXS-f --> CVX, CRV and FXS
        // CVX --> no rewards
        divider.setPeriphery(address(this));
        address f = factory.deployAdapter(AddressBook.f156FRAX3CRV, abi.encode(AddressBook.TRIBE_CONVEX));
        FAdapter adapter = FAdapter(payable(f));
        assertTrue(address(adapter) != address(0));
        assertEq(FAdapter(adapter).target(), address(AddressBook.f156FRAX3CRV));
        assertEq(FAdapter(adapter).divider(), address(divider));
        assertEq(FAdapter(adapter).name(), "Tribe Convex Pool Curve.fi Factory USD Metapool: Frax Adapter");
        assertEq(FAdapter(adapter).symbol(), "fFRAX3CRV-f-156-adapter");
        assertEq(FAdapter(adapter).rewardTokens(0), AddressBook.CVX);
        assertEq(FAdapter(adapter).rewardTokens(1), AddressBook.CRV);
        assertEq(FAdapter(adapter).rewardTokens(2), address(0));
        assertEq(FAdapter(adapter).rewardTokens(3), address(0));

        uint256 scale = FAdapter(adapter).scale();
        assertGt(scale, 0);

        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
        assertGt(guard, 0);
    }

    function testMainnetCantDeployAdapterIfInvalidComptroller() public {
        divider.setPeriphery(address(this));
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector));
        factory.deployAdapter(AddressBook.f18DAI, abi.encode(AddressBook.f18DAI));
    }

    function testMainnetCantDeployAdapterIfNotSupportedTarget() public {
        divider.setPeriphery(address(this));
        hevm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        factory.deployAdapter(AddressBook.f18DAI, abi.encode(AddressBook.TRIBE_CONVEX));
    }

    event RewardTokensChanged(address[] indexed rewardTokens);
    event RewardsDistributorsChanged(address[] indexed rewardsDistributorsList);

    function testMainnetSetRewardsTokens() public {
        divider.setPeriphery(address(this));
        address a = factory.deployAdapter(AddressBook.f156FRAX3CRV, abi.encode(AddressBook.TRIBE_CONVEX));
        FAdapter adapter = FAdapter(payable(a));

        address[] memory rewardTokens = new address[](5);
        rewardTokens[0] = AddressBook.LDO;
        rewardTokens[1] = AddressBook.FXS;

        address[] memory rewardsDistributors = new address[](5);
        rewardsDistributors[0] = AddressBook.REWARDS_DISTRIBUTOR_LDO;
        rewardsDistributors[1] = AddressBook.REWARDS_DISTRIBUTOR_FXS;

        hevm.expectEmit(true, false, false, false);
        emit RewardTokensChanged(rewardTokens);

        hevm.expectEmit(true, false, false, false);
        emit RewardsDistributorsChanged(rewardsDistributors);

        factory.setRewardTokens(a, rewardTokens, rewardsDistributors);

        assertEq(adapter.rewardTokens(0), AddressBook.LDO);
        assertEq(adapter.rewardTokens(1), AddressBook.FXS);
        assertEq(adapter.rewardsDistributorsList(AddressBook.LDO), AddressBook.REWARDS_DISTRIBUTOR_LDO);
        assertEq(adapter.rewardsDistributorsList(AddressBook.FXS), AddressBook.REWARDS_DISTRIBUTOR_FXS);
    }

    function testFuzzMainnetCantSetRewardsTokens(address lad) public {
        if (lad == address(this)) return;
        hevm.prank(divider.periphery());
        address adapter = factory.deployAdapter(AddressBook.f156FRAX3CRV, abi.encode(AddressBook.TRIBE_CONVEX));

        address[] memory rewardTokens = new address[](2);
        address[] memory rewardsDistributors = new address[](2);

        hevm.expectRevert("UNTRUSTED");
        hevm.prank(address(0x111));
        factory.setRewardTokens(rewardTokens, rewardsDistributors);
    }
}
