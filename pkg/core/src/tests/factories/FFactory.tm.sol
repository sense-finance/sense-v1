// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { FAdapter } from "../../adapters/implementations/fuse/FAdapter.sol";
import { FFactory } from "../../adapters/implementations/fuse/FFactory.sol";
import { BaseFactory } from "../../adapters/abstract/factories/BaseFactory.sol";
import { Divider, TokenHandler } from "../../Divider.sol";

import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

contract FAdapterTestHelper is ForkTest {
    FFactory internal factory;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    uint8 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint256 public constant DEFAULT_GUARD = 100000 * 1e18;

    function setUp() public {
        fork();

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
            tilt: 0,
            guard: DEFAULT_GUARD
        });
        factory = new FFactory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams
        );
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
            tilt: 0,
            guard: DEFAULT_GUARD
        });
        FFactory otherFFactory = new FFactory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams
        );

        assertTrue(address(otherFFactory) != address(0));
        (
            address oracle,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint256 ifee,
            uint16 mode,
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
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParam.selector));
        factory.deployAdapter(AddressBook.f18DAI, abi.encode(AddressBook.f18DAI));
    }

    function testMainnetCantDeployAdapterIfNotSupportedTarget() public {
        divider.setPeriphery(address(this));
        vm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
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

        vm.expectEmit(true, false, false, false);
        emit RewardTokensChanged(rewardTokens);

        vm.expectEmit(true, false, false, false);
        emit RewardsDistributorsChanged(rewardsDistributors);

        vm.prank(Constants.RESTRICTED_ADMIN);
        adapter.setRewardTokens(rewardTokens, rewardsDistributors);

        assertEq(adapter.rewardTokens(0), AddressBook.LDO);
        assertEq(adapter.rewardTokens(1), AddressBook.FXS);
        assertEq(adapter.rewardsDistributorsList(AddressBook.LDO), AddressBook.REWARDS_DISTRIBUTOR_LDO);
        assertEq(adapter.rewardsDistributorsList(AddressBook.FXS), AddressBook.REWARDS_DISTRIBUTOR_FXS);
    }

    function testFuzzMainnetCantSetRewardsTokens(address lad) public {
        if (lad == address(this)) return;
        vm.prank(divider.periphery());
        address adapter = factory.deployAdapter(AddressBook.f156FRAX3CRV, abi.encode(AddressBook.TRIBE_CONVEX));

        address[] memory rewardTokens = new address[](2);
        address[] memory rewardsDistributors = new address[](2);

        vm.expectRevert("UNTRUSTED");
        vm.prank(lad);
        FAdapter(payable(adapter)).setRewardTokens(rewardTokens, rewardsDistributors);
    }
}
