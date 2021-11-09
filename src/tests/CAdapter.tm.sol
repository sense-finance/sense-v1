// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider, TokenHandler } from "../Divider.sol";
import { CAdapter, CTokenInterface } from "../adapters/compound/CAdapter.sol";
import { CFactory } from "../adapters/compound/CFactory.sol";
import { BaseFactory } from "../adapters/BaseFactory.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

contract CAdapterTestHelper is DSTest {
    CAdapter adapter;
    CFactory internal factory;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant ORACLE = 0x6D2299C48a8dD07a872FDd0F8233924872Ad1071;

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

        //        factory.addTarget(cDAI, true);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
        address f = factory.deployAdapter(cDAI);
        adapter = CAdapter(f); // deploy a cDAI adapter
    }
}

contract CAdapters is CAdapterTestHelper {
    using FixedMath for uint256;

    function testCAdapterScale() public {
        CTokenInterface underlying = CTokenInterface(DAI);
        CTokenInterface ctoken = CTokenInterface(cDAI);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ctoken.exchangeRateCurrent().fdiv(10**(18 - 8 + uDecimals), 10**uDecimals);
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
