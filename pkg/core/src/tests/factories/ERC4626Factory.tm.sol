// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { ERC4626Adapter } from "../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { ERC4626CropsAdapter } from "../../adapters/abstract/erc4626/ERC4626CropsAdapter.sol";
import { ERC4626Factory } from "../../adapters/abstract/factories/ERC4626Factory.sol";
import { ChainlinkPriceOracle } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";
import { BaseFactory } from "../../adapters/abstract/factories/BaseFactory.sol";
import { Divider, TokenHandler } from "../../Divider.sol";
import { Hevm } from "../test-helpers/Hevm.sol";

import { DSTest } from "../test-helpers/test.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { AddressBook } from "../test-helpers/AddressBook.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

contract ERC4626TestHelper is DSTest {
    ERC4626Factory internal factory;
    Divider internal divider;
    TokenHandler internal tokenHandler;
    MasterPriceOracle internal masterOracle;

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

        // Deploy Chainlink price oracle
        ChainlinkPriceOracle chainlinkOracle = new ChainlinkPriceOracle(0);

        // Deploy Sense master price oracle
        address[] memory data;
        masterOracle = new MasterPriceOracle(address(chainlinkOracle), data, data);

        // deploy ERC4626 adapter factory
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: AddressBook.WETH,
            oracle: address(masterOracle),
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0
        });
        factory = new ERC4626Factory(address(divider), factoryParams);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
        factory.supportTarget(AddressBook.IMUSD, true);
    }
}

contract ERC4626Factories is ERC4626TestHelper {
    function testMainnetDeployFactory() public {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: AddressBook.DAI,
            oracle: address(masterOracle),
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0
        });
        ERC4626Factory otherFactory = new ERC4626Factory(address(divider), factoryParams);

        assertTrue(address(otherFactory) != address(0));
        (
            address oracle,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint256 ifee,
            uint16 mode,
            uint64 tilt
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
    }

    function testMainnetDeployAdapter() public {
        // Prepare date for non-crop adapter
        address[] memory rewardTokens;
        bytes memory data = abi.encode(0, rewardTokens);

        // Deploy non-crop adapter
        address f = factory.deployAdapter(AddressBook.IMUSD, data);
        ERC4626Adapter adapter = ERC4626Adapter(payable(f));

        assertTrue(address(adapter) != address(0));
        assertEq(adapter.target(), address(AddressBook.IMUSD));
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.name(), "Interest bearing mUSD Adapter");
        assertEq(adapter.symbol(), "imUSD-adapter");

        uint256 scale = adapter.scale();
        assertTrue(scale > 0);
    }

    function testMainnetDeployCropsAdapter() public {
        // Prepare data for crops adapter
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = AddressBook.DAI;
        rewardTokens[1] = AddressBook.WETH;
        bytes memory data = abi.encode(1, rewardTokens);

        // Deploy crops adapter
        address f = factory.deployAdapter(AddressBook.IMUSD, data);
        ERC4626CropsAdapter adapter = ERC4626CropsAdapter(payable(f));

        assertTrue(address(adapter) != address(0));
        assertEq(adapter.target(), address(AddressBook.IMUSD));
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.name(), "Interest bearing mUSD Adapter");
        assertEq(adapter.symbol(), "imUSD-adapter");
        assertEq(adapter.rewardTokens(0), AddressBook.DAI);
        assertEq(adapter.rewardTokens(1), AddressBook.WETH);

        uint256 scale = adapter.scale();
        assertTrue(scale > 0);
    }

    function testMainnetCantDeployAdapterIfNotSupportedTarget() public {
        // Prepare data for adapter
        address[] memory rewardTokens;
        bytes memory data = abi.encode(0, rewardTokens);

        hevm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        factory.deployAdapter(AddressBook.DAI, data);
    }

    function testMainnetCanDeployAdapterIfNotSupportedTargetButPermissionless() public {
        // Unsupport IMUSD target
        factory.supportTarget(AddressBook.IMUSD, false);

        // Turn on permissionless mode
        Divider(factory.divider()).setPermissionless(true);

        // Prepare data for adapter
        address[] memory rewardTokens;
        bytes memory data = abi.encode(0, rewardTokens);

        factory.deployAdapter(AddressBook.IMUSD, data);
    }

    function testMainnetCanSupportTarget() public {
        assertTrue(!factory.supportedTargets(AddressBook.cDAI));
        factory.supportTarget(AddressBook.cDAI, true);
        assertTrue(factory.supportedTargets(AddressBook.cDAI));
    }

    function testMainnetCantSupportTargetIfNotTrusted() public {
        assertTrue(!factory.supportedTargets(AddressBook.cDAI));
        hevm.prank(address(1));
        hevm.expectRevert("UNTRUSTED");
        factory.supportTarget(AddressBook.cDAI, true);
    }
}
