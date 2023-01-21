// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { CAdapter } from "../../adapters/implementations/compound/CAdapter.sol";
import { CFactory } from "../../adapters/implementations/compound/CFactory.sol";
import { BaseFactory, ChainlinkOracleLike } from "../../adapters/abstract/factories/BaseFactory.sol";
import { Divider, TokenHandler } from "../../Divider.sol";
import { FixedMath } from "../../external/FixedMath.sol";

import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

contract CAdapterTestHelper is ForkTest {
    CFactory internal factory;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    uint8 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint256 public constant DEFAULT_GUARD = 100000 * 1e18; // 100'000 USD in 18 decimals

    function setUp() public {
        fork();

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = AddressBook.COMP;

        // deploy compound adapter factory
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
        factory = new CFactory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            AddressBook.COMP
        );
        divider.setIsTrusted(address(factory), true); // add factory as a ward
    }
}

contract CFactories is CAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetDeployFactory() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = AddressBook.COMP;

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
        CFactory otherCFactory = new CFactory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            AddressBook.COMP
        );

        assertTrue(address(otherCFactory) != address(0));
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
        ) = CFactory(otherCFactory).factoryParams();

        assertEq(CFactory(otherCFactory).divider(), address(divider));
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
        divider.setPeriphery(address(this));
        address f = factory.deployAdapter(AddressBook.cLINK, "");
        CAdapter adapter = CAdapter(payable(f));
        assertTrue(address(adapter) != address(0));
        assertEq(CAdapter(adapter).target(), address(AddressBook.cLINK));
        assertEq(CAdapter(adapter).divider(), address(divider));
        assertEq(CAdapter(adapter).name(), "Compound ChainLink Token Adapter");
        assertEq(CAdapter(adapter).symbol(), "cLINK-adapter");

        uint256 scale = CAdapter(adapter).scale(); // 18 decimals
        assertTrue(scale > 0);

        // Guard has been calculated with underlying-ETH (18 decimals),
        // target-underlying (18 decimals) and ETH-USD (8 decimals)
        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
        uint256 tDecimals = ERC20(CAdapter(adapter).target()).decimals();

        // On this test we assert that the guard calculated is close to the one calculated below
        // which uses underlying-USD (8 decimals) and target-underlying (18 decimals)

        // LINK-USD price (8 decimals)
        address LINK_USD_FEED = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
        (, int256 linkPrice, , , ) = ChainlinkOracleLike(LINK_USD_FEED).latestRoundData();

        // cLINK-USD price (18 decimals)
        uint256 price = scale.fmul(uint256(linkPrice), 10**tDecimals);

        // Convert DEFAULT_GUARD (which is $100'000 in 18 decimals) to target
        // using target's price (18 decimals)
        uint256 guardInTarget = DEFAULT_GUARD.fdiv(price, 10**tDecimals);
        assertApproxEqAbs(guard, guardInTarget, guard.fmul(0.050e18));
    }

    function testMainnetDeployAdapterWithNonERC20() public {
        divider.setPeriphery(address(this));
        address f = factory.deployAdapter(AddressBook.cUSDT, "");
        CAdapter adapter = CAdapter(payable(f));
        assertTrue(address(adapter) != address(0));
        assertEq(CAdapter(adapter).target(), address(AddressBook.cUSDT));
        assertEq(CAdapter(adapter).divider(), address(divider));
        assertEq(CAdapter(adapter).name(), "Compound USDT Adapter");
        assertEq(CAdapter(adapter).symbol(), "cUSDT-adapter");

        uint256 scale = CAdapter(adapter).scale(); // 18 decimals
        assertTrue(scale > 0);
    }

    function testMainnetCantDeployAdapterIfNotSupportedTarget() public {
        divider.setPeriphery(address(this));
        vm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        factory.deployAdapter(AddressBook.f18DAI, "");
    }
}
