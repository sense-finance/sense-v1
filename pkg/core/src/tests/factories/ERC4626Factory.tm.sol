// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { ERC4626Adapter } from "../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { ERC4626CropsAdapter } from "../../adapters/abstract/erc4626/ERC4626CropsAdapter.sol";
import { ERC4626Factory } from "../../adapters/abstract/factories/ERC4626Factory.sol";
import { ERC4626CropsFactory } from "../../adapters/abstract/factories/ERC4626CropsFactory.sol";
import { ChainlinkPriceOracle } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";
import { BaseFactory, ChainlinkOracleLike } from "../../adapters/abstract/factories/BaseFactory.sol";
import { Divider, TokenHandler } from "../../Divider.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

contract ERC4626TestHelper is ForkTest {
    ERC4626Factory internal factory;
    ERC4626CropsFactory internal cropsFactory;
    Divider internal divider;
    TokenHandler internal tokenHandler;
    MasterPriceOracle internal masterOracle;

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

        // Deploy Chainlink price oracle
        ChainlinkPriceOracle chainlinkOracle = new ChainlinkPriceOracle(0);

        // Deploy Sense master price oracle (with mStable oracle)
        address[] memory underlyings = new address[](1);
        underlyings[0] = AddressBook.MUSD;

        address[] memory oracles = new address[](1);
        oracles[0] = AddressBook.RARI_MSTABLE_ORACLE;
        masterOracle = new MasterPriceOracle(address(chainlinkOracle), underlyings, oracles);
        assertEq(masterOracle.oracles(AddressBook.MUSD), AddressBook.RARI_MSTABLE_ORACLE);

        // deploy ERC4626 adapter factory
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: AddressBook.WETH,
            oracle: address(masterOracle),
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            guard: DEFAULT_GUARD
        });
        factory = new ERC4626Factory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams
        );
        divider.setIsTrusted(address(factory), true); // add factory as a ward
        factory.supportTarget(AddressBook.IMUSD, true);

        cropsFactory = new ERC4626CropsFactory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams
        );
        divider.setIsTrusted(address(cropsFactory), true); // add factory as a ward
        cropsFactory.supportTarget(AddressBook.IMUSD, true);
    }
}

contract ERC4626Factories is ERC4626TestHelper {
    using FixedMath for uint256;

    function testMainnetDeployFactory() public {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: AddressBook.DAI,
            oracle: address(masterOracle),
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            guard: DEFAULT_GUARD
        });
        ERC4626Factory otherFactory = new ERC4626Factory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams
        );

        assertTrue(address(otherFactory) != address(0));
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
        ) = ERC4626Factory(otherFactory).factoryParams();

        assertEq(ERC4626Factory(otherFactory).divider(), address(divider));
        assertEq(stake, AddressBook.DAI);
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, MODE);
        assertEq(oracle, address(masterOracle));
        assertEq(tilt, 0);
        assertEq(guard, DEFAULT_GUARD);
    }

    function testMainnetDeployAdapter() public {
        // Deploy non-crop adapter
        vm.prank(divider.periphery());
        ERC4626Adapter adapter = ERC4626Adapter(factory.deployAdapter(AddressBook.IMUSD, ""));

        assertTrue(address(adapter) != address(0));
        assertEq(adapter.target(), address(AddressBook.IMUSD));
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.name(), "Interest bearing mUSD Adapter");
        assertEq(adapter.symbol(), "imUSD-adapter");

        uint256 scale = adapter.scale();
        assertTrue(scale > 0);

        // Guard has been calculated with underlying-ETH (18 decimals),
        // target-underlying (18 decimals) and ETH-USD (8 decimals)
        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
        uint256 tDecimals = ERC20(adapter.target()).decimals();

        // On this test we assert that the guard calculated is close to the one calculated below
        // which uses Rari's mStable underlying-USD (8 decimals) and target-undelying (18 decimals)

        // mUSD-ETH price (18 decimals)
        uint256 underlyingPriceInEth = adapter.getUnderlyingPrice();

        // ETH-USD price (8 decimals)
        (, int256 ethPrice, , , ) = ChainlinkOracleLike(AddressBook.ETH_USD_PRICEFEED).latestRoundData();

        // mUSD-USD price (18 decimals)
        uint256 price = underlyingPriceInEth.fmul(uint256(ethPrice), 1e8);

        // imUSD-USD price (normalised to target decimals)
        price = scale.fmul(price, 10**tDecimals);

        // Convert DEFAULT_GUARD (which is $100'000 in 18 decimals) to target
        // using target's price (in target's decimals)
        uint256 guardInTarget = DEFAULT_GUARD.fdiv(price, 10**tDecimals);
        assertApproxEqAbs(guard, guardInTarget, guard.fmul(0.010e18));
    }

    function testMainnetDeployCropsAdapter() public {
        // Prepare data for crops adapter
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = AddressBook.DAI;
        rewardTokens[1] = AddressBook.WETH;
        bytes memory data = abi.encode(rewardTokens);

        // Deploy crops adapter
        vm.prank(divider.periphery());
        ERC4626CropsAdapter adapter = ERC4626CropsAdapter(cropsFactory.deployAdapter(AddressBook.IMUSD, data));

        assertTrue(address(adapter) != address(0));
        assertEq(adapter.target(), address(AddressBook.IMUSD));
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.name(), "Interest bearing mUSD Adapter");
        assertEq(adapter.symbol(), "imUSD-adapter");
        assertEq(adapter.rewardTokens(0), AddressBook.DAI);
        assertEq(adapter.rewardTokens(1), AddressBook.WETH);

        uint256 scale = adapter.scale();
        assertTrue(scale > 0);

        // As we are testing with a stablecoin here (mUSD), we can think the scale
        // as the imUSD - USD rate, so we want to assert that the guard (which should be $100'000)
        // in target terms is approx 100'000 / scale (within 10%).
        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
        assertApproxEqAbs(guard, (100000 * 1e36) / scale, guard.fmul(0.010e18));
    }

    function testMainnetCantDeployAdapterIfNotSupportedTarget() public {
        // Prepare data for adapter
        address[] memory rewardTokens;
        bytes memory data = abi.encode(rewardTokens);

        divider.setPeriphery(address(this));
        vm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        factory.deployAdapter(AddressBook.DAI, data);
    }

    function testMainnetCanDeployAdapterIfNotSupportedTargetButPermissionless() public {
        // Unsupport IMUSD target
        factory.supportTarget(AddressBook.IMUSD, false);

        // Turn on permissionless mode
        Divider(factory.divider()).setPermissionless(true);

        // Prepare data for adapter
        address[] memory rewardTokens;
        bytes memory data = abi.encode(rewardTokens);

        vm.prank(divider.periphery());
        factory.deployAdapter(AddressBook.IMUSD, data);
    }

    function testMainnetCanSupportTarget() public {
        assertTrue(!factory.supportedTargets(AddressBook.cDAI));
        factory.supportTarget(AddressBook.cDAI, true);
        assertTrue(factory.supportedTargets(AddressBook.cDAI));
    }

    function testMainnetCantSupportTargetIfNotTrusted() public {
        assertTrue(!factory.supportedTargets(AddressBook.cDAI));
        vm.prank(address(1));
        vm.expectRevert("UNTRUSTED");
        factory.supportTarget(AddressBook.cDAI, true);
    }
}
