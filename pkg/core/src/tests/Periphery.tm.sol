// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { PoolManager } from "@sense-finance/v1-fuse/PoolManager.sol";
import { Divider } from "../Divider.sol";
import { BaseFactory } from "../adapters/abstract/factories/BaseFactory.sol";
import { BaseAdapter } from "../adapters/abstract/BaseAdapter.sol";
import { CAdapter } from "../adapters/implementations/compound/CAdapter.sol";
import { FAdapter } from "../adapters/implementations/fuse/FAdapter.sol";
import { CFactory } from "../adapters/implementations/compound/CFactory.sol";
import { FFactory } from "../adapters/implementations/fuse/FFactory.sol";
import { WstETHLike } from "../adapters/implementations/lido/WstETHAdapter.sol";

import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

// Mocks
import { MockOracle } from "./test-helpers/mocks/fuse/MockOracle.sol";
import { MockAdapter, MockCropAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";

// Permit2
import { Permit2Helper } from "./test-helpers/Permit2Helper.sol";
import { IPermit2 } from "@sense-finance/v1-core/external/IPermit2.sol";

// Constants/Addresses
import { Constants } from "./test-helpers/Constants.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";

import { BalancerVault } from "../external/balancer/Vault.sol";
import { BalancerPool } from "../external/balancer/Pool.sol";
import "hardhat/console.sol";

interface SpaceFactoryLike {
    function create(address, uint256) external returns (address);

    function pools(address adapter, uint256 maturity) external view returns (address);

    function setParams(
        uint256 _ts,
        uint256 _g1,
        uint256 _g2,
        bool _oracleEnabled,
        bool _balancerFeesEnabled
    ) external;
}

// Periphery contract wit _fillQuote exposed for testing
contract PeripheryFQ is Periphery {
    constructor(
        address _divider,
        address _poolManager,
        address _spaceFactory,
        address _balancerVault,
        address _permit2,
        address _exchangeProxy
    ) Periphery(_divider, _poolManager, _spaceFactory, _balancerVault, _permit2, _exchangeProxy) {}

    function fillQuote(SwapQuote calldata quote) public payable returns (uint256 boughtAmount) {
        return _fillQuote(quote);
    }

    function transferFrom(
        Periphery.PermitData calldata permit,
        address token,
        uint256 amt
    ) public {
        return _transferFrom(permit, token, amt);
    }
}

contract PeripheryTestHelper is ForkTest, Permit2Helper {
    PeripheryFQ internal periphery;

    CFactory internal cfactory;
    FFactory internal ffactory;

    MockOracle internal mockOracle;
    MockToken internal underlying;
    MockTarget internal mockTarget;
    MockCropAdapter internal mockAdapter;

    // Mainnet contracts for forking
    address internal balancerVault;
    address internal spaceFactory;
    address internal poolManager;
    address internal divider;
    address internal stake;

    uint256 internal bobPrivKey = _randomUint256();
    address internal bob = vm.addr(bobPrivKey);
    uint256 internal jimPrivKey = _randomUint256();
    address internal jim = vm.addr(jimPrivKey);

    // Fee used for testing YT swaps, must be accounted for when doing external ref checks with the yt buying lib
    uint128 internal constant IFEE_FOR_YT_SWAPS = 0.042e18; // 4.2%

    // DAI to stETH quote
    // https://api.0x.org/swap/v1/quote?sellToken=DAI&buyToken=0xae7ab96520de3a18e5e111b5eaab095312d7fe84&sellAmount=1000000000000000000
    bytes internal constant DAI_STETH_SWAP_QUOTE_DATA =
        hex"415565b00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000021adf49ed07e000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000740000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000340000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000002537573686953776170000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002e0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000000000000000000260ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000154c69646f000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000021adf49ed07e000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000040000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000030000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000b67119692563e364e7";

    // stETH to DAI quote
    // https://api.0x.org/swap/v1/quote?sellToken=0xae7ab96520de3a18e5e111b5eaab095312d7fe84&buyToken=DAI&sellAmount=957048107692151
    bytes internal constant STETH_DAI_SWAP_QUOTE_DATA =
        hex"415565b0000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000003666e207df077000000000000000000000000000000000000000000000000141618cc9529b7c200000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000003a00000000000000000000000000000000000000000000000000000000000000760000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000003666e207df077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000154c69646f0000000000000000000000000000000000000000000000000000000000000000000000000003666e207df077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000040000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000360000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000002e0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e6973776170563300000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000141618cc9529b7c2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000e592427a0aece92de3edee1f18e0157c05861564000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000427f39c581f595b53c5cb19bd0b3f8da6c935e2ca00001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000646b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000004ca866b2c363ea5e3e";

    // stETH to ETH quote
    // https://api.0x.org/swap/v1/quote?sellToken=0xae7ab96520de3a18e5e111b5eaab095312d7fe84&buyToken=ETH&sellAmount=97925288322265263
    bytes internal constant STETH_ETH_SWAP_QUOTE_DATA =
        hex"415565b0000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000000000000000000000000000015be687e8f9f0af0000000000000000000000000000000000000000000000000157dfc637b25b4700000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000003e00000000000000000000000000000000000000000000000000000000000000480000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000015be687e8f9f0af000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000143757276650000000000000000000000000000000000000000000000000000000000000000000000015be687e8f9f0af0000000000000000000000000000000000000000000000000157dfc637b25b4700000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000080000000000000000000000000dc24316b9ae028f1497c275eb9192a3ea0f670223df021240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000040000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000001000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000546d5ffb4763f4c578";

    // https://api.0x.org/swap/v1/quote?sellToken=ETH&buyToken=0xae7ab96520de3a18e5e111b5eaab095312d7fe84&sellAmount=1000000000000000000
    // ETH to stETH quote
    bytes internal constant ETH_STETH_SWAP_QUOTE_DATA =
        hex"415565b0000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000dbd425bda847d4800000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000480000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000040000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000001437572766500000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000dbd425bda847d4800000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000080000000000000000000000000dc24316b9ae028f1497c275eb9192a3ea0f670223df021240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000000000000000000099788145ed63f48648";

    // https://api.0x.org/swap/v1/quote?sellToken=USDC&buyToken=DAI&buyAmount=1000000000000000000
    // NOTE we are using buyAmount instead of sellAmount
    bytes internal constant USDC_DAI_SWAP_QUOTE_DATA =
        hex"d9627aa4000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000f66690000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000b559b1466763f333ef";

    function setUp() public {
        _setUp(true);
    }

    function _setUp(bool createFork) internal returns (uint256 timestamp) {
        if (createFork) fork();

        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint256 firstDayOfMonth = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        vm.warp(firstDayOfMonth); // Set to first day of the month

        // Mainnet contracts
        divider = AddressBook.DIVIDER_1_2_0;
        spaceFactory = AddressBook.SPACE_FACTORY_1_3_0;
        balancerVault = AddressBook.BALANCER_VAULT;
        poolManager = AddressBook.POOL_MANAGER_1_2_0;
        permit2 = IPermit2(AddressBook.PERMIT2);

        vm.label(divider, "Divider");
        vm.label(spaceFactory, "SpaceFactory");
        vm.label(balancerVault, "BalancerVault");
        vm.label(poolManager, "PoolManager");

        // Deploy an mock underlying token
        underlying = new MockToken("TestUnderlying", "TU", 18);

        // Deploy a mock target
        mockTarget = new MockTarget(address(underlying), "TestTarget", "TT", 18);

        // Deploy a mock stake token
        stake = address(new MockToken("Stake", "ST", 18));

        // Deploy a mock oracle
        mockOracle = new MockOracle();

        // Deploy a mock crop adapter
        BaseAdapter.AdapterParams memory mockAdapterParams = BaseAdapter.AdapterParams({
            oracle: address(mockOracle),
            stake: stake, // stake size is 0, so the we don't actually need any stake token
            stakeSize: 0,
            minm: 0, // 0 minm, so there's not lower bound on future maturity
            maxm: type(uint64).max, // large maxm, so there's not upper bound on future maturity
            mode: 0, // monthly maturities
            tilt: 0,
            level: Constants.DEFAULT_LEVEL
        });
        mockAdapter = new MockCropAdapter(
            address(divider),
            address(mockTarget),
            mockTarget.underlying(),
            Constants.REWARDS_RECIPIENT,
            IFEE_FOR_YT_SWAPS,
            mockAdapterParams,
            address(new MockToken("Reward", "R", 18))
        );

        // Prep factory params
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: AddressBook.DAI,
            oracle: address(mockOracle),
            ifee: Constants.DEFAULT_ISSUANCE_FEE,
            stakeSize: Constants.DEFAULT_STAKE_SIZE,
            minm: Constants.DEFAULT_MIN_MATURITY,
            maxm: Constants.DEFAULT_MAX_MATURITY,
            mode: Constants.DEFAULT_MODE,
            tilt: Constants.DEFAULT_TILT,
            guard: Constants.DEFAULT_GUARD
        });

        // Deploy a CFactory
        cfactory = new CFactory(
            divider,
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            AddressBook.COMP
        );

        // Deploy an FFactory
        ffactory = new FFactory(divider, Constants.RESTRICTED_ADMIN, Constants.REWARDS_RECIPIENT, factoryParams);

        // Deploy Periphery
        periphery = new PeripheryFQ(
            divider,
            poolManager,
            spaceFactory,
            balancerVault,
            address(permit2),
            AddressBook.EXCHANGE_PROXY
        );

        periphery.setFactory(address(cfactory), true);
        periphery.setFactory(address(ffactory), true);

        // Start multisig (admin) prank calls
        vm.startPrank(AddressBook.SENSE_MULTISIG);

        // Give authority to factories soy they can setGuard when deploying adapters
        Divider(divider).setIsTrusted(address(cfactory), true);
        Divider(divider).setIsTrusted(address(ffactory), true);

        Divider(divider).setPeriphery(address(periphery));
        Divider(divider).setGuard(address(mockAdapter), type(uint256).max);

        PoolManager(poolManager).setIsTrusted(address(periphery), true);
        uint256 ts = 1e18 / (uint256(31536000) * uint256(12));
        uint256 g1 = (uint256(950) * 1e18) / uint256(1000);
        uint256 g2 = (uint256(1000) * 1e18) / uint256(950);
        SpaceFactoryLike(spaceFactory).setParams(ts, g1, g2, true, false);

        vm.stopPrank(); // Stop prank calling

        periphery.onboardAdapter(address(mockAdapter), true);
        periphery.verifyAdapter(address(mockAdapter), true);

        // Set adapter scale to 1
        mockAdapter.setScale(1e18);

        // Give the permit2 approvals for the mock Target
        vm.prank(bob);
        mockTarget.approve(AddressBook.PERMIT2, type(uint256).max);
    }
}

contract PeripheryMainnetTests is PeripheryTestHelper {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

    /* ========== SERIES SPONSORING ========== */

    function testMainnetSponsorSeriesOnCAdapter() public {
        // Set guarded as false to skip setting a guard
        vm.prank(AddressBook.SENSE_MULTISIG);
        Divider(divider).setGuarded(false);

        CAdapter cadapter = CAdapter(payable(periphery.deployAdapter(address(cfactory), AddressBook.cBAT, "")));

        // Calculate maturity
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(
            block.timestamp + Constants.DEFAULT_MIN_MATURITY
        );
        uint256 maturity = DateTimeFull.timestampFromDateTime(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : (month + 1),
            1,
            0,
            0,
            0
        );

        // Mint bob MAX_UINT AddressBook.DAI (for stake)
        deal(AddressBook.DAI, bob, type(uint256).max);

        vm.prank(bob);
        ERC20(AddressBook.DAI).approve(AddressBook.PERMIT2, type(uint256).max);

        Periphery.SwapQuote memory quote = _getQuote(AddressBook.DAI, AddressBook.DAI);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), AddressBook.DAI);
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(address(cadapter), maturity, false, data, quote);

        // Check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(cadapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testMainnetSponsorSeriesFromToken() public {
        // Roll to Feb-08-2023 09:12:23 AM +UTC where we have a real adapter (wstETH adapter)
        vm.rollFork(16583087);

        // Re-deploy Periphery and set everything up
        _setUp(false);

        // Set guarded as false to skip setting a guard
        vm.prank(AddressBook.SENSE_MULTISIG);
        Divider(divider).setGuarded(false);

        CAdapter cadapter = CAdapter(payable(periphery.deployAdapter(address(cfactory), AddressBook.cBAT, "")));

        // Calculate maturity
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(
            block.timestamp + Constants.DEFAULT_MIN_MATURITY
        );
        uint256 maturity = DateTimeFull.timestampFromDateTime(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : (month + 1),
            1,
            0,
            0,
            0
        );

        // Mint bob some AddressBook.USDC (to then swap for DAI to pay stake)
        deal(AddressBook.USDC, bob, type(uint256).max);

        vm.prank(bob);
        ERC20(AddressBook.USDC).approve(AddressBook.PERMIT2, type(uint256).max);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), AddressBook.USDC);
        Periphery.SwapQuote memory quote = Periphery.SwapQuote({
            sellToken: ERC20(AddressBook.USDC),
            buyToken: ERC20(AddressBook.DAI),
            spender: AddressBook.EXCHANGE_PROXY,
            swapTarget: payable(AddressBook.EXCHANGE_PROXY),
            swapCallData: _getSwapCallData(AddressBook.USDC, AddressBook.DAI)
        });
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(address(cadapter), maturity, false, data, quote);

        // Check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(cadapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testMainnetSponsorSeriesFromETH() public {
        // Roll to Feb-08-2023 09:12:23 AM +UTC where we have a real adapter (wstETH adapter)
        vm.rollFork(16583087);

        // Re-deploy Periphery and set everything up
        _setUp(false);

        // Set guarded as false to skip setting a guard
        vm.prank(AddressBook.SENSE_MULTISIG);
        Divider(divider).setGuarded(false);

        CAdapter cadapter = CAdapter(payable(periphery.deployAdapter(address(cfactory), AddressBook.cBAT, "")));

        // Calculate maturity
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(
            block.timestamp + Constants.DEFAULT_MIN_MATURITY
        );
        uint256 maturity = DateTimeFull.timestampFromDateTime(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : (month + 1),
            1,
            0,
            0,
            0
        );

        // Top up bob's account with some ETH (to then swap for DAI to pay stake)
        deal(bob, 10 ether);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), periphery.ETH());
        // https://api.0x.org/swap/v1/quote?sellToken=ETH&buyToken=DAI&buyAmount=500000000000000000000
        // NOTE we are using buyAmount instead of sellAmount
        // TODO: not sure why it's failing to buy a small amount (I'm changing the quote to be to buy 500 DAI instead of 1 DAI to make it pass)
        Periphery.SwapQuote memory quote = Periphery.SwapQuote({
            sellToken: ERC20(periphery.ETH()),
            buyToken: ERC20(AddressBook.DAI),
            spender: address(0),
            swapTarget: payable(AddressBook.EXCHANGE_PROXY),
            swapCallData: hex"3598d8ab000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000001b1ae4d6e2ef5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f46b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000f94bd75c8663f34a98"
        });
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries{ value: 1 ether }(
            address(cadapter),
            maturity,
            false,
            data,
            quote
        );

        // Check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(cadapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testMainnetSponsorSeriesFromTokenWithTokenExcess() public {
        // Roll to Feb-08-2023 09:12:23 AM +UTC where we have a real adapter (wstETH adapter)
        vm.rollFork(16583087);

        // Re-deploy Periphery and set everything up
        _setUp(false);

        // Set guarded as false to skip setting a guard
        vm.prank(AddressBook.SENSE_MULTISIG);
        Divider(divider).setGuarded(false);

        CAdapter cadapter = CAdapter(payable(periphery.deployAdapter(address(cfactory), AddressBook.cBAT, "")));

        // Calculate maturity
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(
            block.timestamp + Constants.DEFAULT_MIN_MATURITY
        );
        uint256 maturity = DateTimeFull.timestampFromDateTime(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : (month + 1),
            1,
            0,
            0,
            0
        );

        // Mint bob some AddressBook.USDC (to then swap for DAI to pay stake)
        deal(AddressBook.USDC, bob, type(uint256).max);

        vm.prank(bob);
        ERC20(AddressBook.USDC).approve(AddressBook.PERMIT2, type(uint256).max);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), AddressBook.USDC);
        // https://api.0x.org/swap/v1/quote?sellToken=USDC&buyToken=DAI&buyAmount=100000000000000000000
        // NOTE we are using a quote to sell 100 USDC which will give us ~100 DAI which is more than the 1 DAI we need to pay the stake
        Periphery.SwapQuote memory quote = Periphery.SwapQuote({
            sellToken: ERC20(AddressBook.USDC),
            buyToken: ERC20(AddressBook.DAI),
            spender: AddressBook.EXCHANGE_PROXY,
            swapTarget: payable(AddressBook.EXCHANGE_PROXY),
            swapCallData: hex"d9627aa40000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000608f5890000000000000000000000000000000000000000000000056bc75e2d6310000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000cfd2818a5e63f372bf"
        });
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(address(cadapter), maturity, false, data, quote);

        // Check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(cadapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);

        // Check that the extra DAI are returned to the user
        assertEq(ERC20(AddressBook.DAI).balanceOf(bob), 99921386850310204870);
    }

    function testMainnetSponsorSeriesOnFAdapter() public {
        // Set guarded as false to skip setting a guard
        vm.prank(AddressBook.SENSE_MULTISIG);
        Divider(divider).setGuarded(false);

        address f = periphery.deployAdapter(
            address(ffactory),
            AddressBook.f156FRAX3CRV,
            abi.encode(AddressBook.TRIBE_CONVEX)
        );
        FAdapter fadapter = FAdapter(payable(f));
        // Mint this address MAX_UINT AddressBook.DAI for stake
        deal(AddressBook.DAI, bob, type(uint256).max);

        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(
            block.timestamp + Constants.DEFAULT_MIN_MATURITY
        );
        uint256 maturity = DateTimeFull.timestampFromDateTime(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : (month + 1),
            1,
            0,
            0,
            0
        );

        vm.prank(bob);
        ERC20(AddressBook.DAI).approve(AddressBook.PERMIT2, type(uint256).max);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), AddressBook.DAI);
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(
            address(fadapter),
            maturity,
            false,
            data,
            _getQuote(AddressBook.DAI, AddressBook.DAI)
        );

        // Check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(fadapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testMainnetSponsorSeriesOnMockAdapter() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // Check that the PT and YT contracts have been deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check that PTs and YTs are onboarded via the PoolManager into Fuse
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(mockAdapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testMainnetSponsorSeriesOnMockAdapterWhenPoolManagerZero() public {
        // 1. Set pool manager to zero address
        periphery.setPoolManager(address(0));

        // 2. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // Check that the PT and YT contracts have been deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));
    }

    /* ========== LIQUIDITY ========== */
    // TODO: add tests for refund protocol fees

    function testMainnetAddLiquidity() public {
        // Roll to Feb-08-2023 09:12:23 AM +UTC where we have a real adapter (wstETH adapter)
        vm.rollFork(16583087);

        // Re-deploy Periphery and set everything up
        _setUp(false);

        // Get the existing adapter (wstETH adapter) and set it up on the Periphery
        (address adapter, uint256 maturity) = _getExistingAdapterAndSeries();

        // 1. Add liquidity from DAI
        ERC20 token = ERC20(AddressBook.DAI);
        uint256 amt = 10**token.decimals(); // 1 DAI
        // Create quote from 0x API to do a 1 DAI to underlying (stETH) swap
        Periphery.SwapQuote memory quote = _getBuyUnderlyingQuote(adapter, AddressBook.DAI);
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(AddressBook.DAI, MockAdapter(adapter).underlying(), 0, 0);
        _addLiquidityFromToken(adapter, maturity, quote, amt);

        // 2. Add liquidity from ETH
        amt = 1e18; // 1 ETH
        // Create quote from 0x API to do a 1 ETH to underlying (stETH) swap
        quote = _getBuyUnderlyingQuote(adapter, periphery.ETH());
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(periphery.ETH(), MockAdapter(adapter).underlying(), 0, 0);
        _addLiquidityFromETH(adapter, maturity, quote, amt);

        // 3.1 Add liquidity from Target
        token = ERC20(MockAdapter(adapter).target());
        amt = 10**token.decimals(); // 1 Target
        // Create quote only with sellToken as target. We don't care about the other params
        // since no swap on 0x will be done
        quote = _getBuyUnderlyingQuote(adapter, address(token));
        _addLiquidityFromToken(adapter, maturity, quote, amt);

        // 3.2 Add liquidity from Target
        token = ERC20(MockAdapter(adapter).target());
        amt = 10**token.decimals(); // 1 Target
        // Create quote only with sellToken as target. We don't care about the other params
        // since no swap on 0x will be done. Eg. We are sending here buyToken = DAI but
        // will be ignored in this case. When adding liquidity, buyToken would always be the LP token
        quote = _getBuyUnderlyingQuote(adapter, address(token));
        quote.buyToken = ERC20(AddressBook.DAI);
        _addLiquidityFromToken(adapter, maturity, quote, amt);

        // 4. Add liquidity from Underlying
        token = ERC20(MockAdapter(adapter).underlying());
        amt = 10**token.decimals(); // 1 Target
        // Create quote only with sellToken as target. We don't care about the other params
        // since no swap on 0x will be done
        quote = _getBuyUnderlyingQuote(adapter, address(token));
        _addLiquidityFromToken(adapter, maturity, quote, amt);

        // 5. Add liquidity with malformed quote: buyToken is not the underlying
        token = ERC20(AddressBook.DAI);
        amt = 10**token.decimals(); // 1 DAI
        // Create quote from 0x API to do a 1 DAI to underlying (stETH) swap
        quote = _getBuyUnderlyingQuote(adapter, AddressBook.DAI);
        // Malform quote by changing buyToken (which is stETH) to USDC
        quote.buyToken = ERC20(AddressBook.USDC);
        // Adding liquidity will do:
        // 1. We pull DAI tokens from the user
        // 2. We succefully execute a 0x swap from DAI to stETH
        // 3. We wrap DAI for target
        // 5. Since buyToken is now USDC (instead of stETH) and we have received 0 USDC, it will revert
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroSwapAmt.selector));
        this._addLiquidityFromToken(adapter, maturity, quote, amt);
        vm.stopPrank();

        // 6. Add liquidity with malformed quote:
        token = ERC20(AddressBook.DAI);
        amt = 10**token.decimals(); // 1 DAI
        // Create quote from 0x API to do a 1 DAI to underlying (stETH) swap
        quote = _getBuyUnderlyingQuote(adapter, AddressBook.DAI);
        // Malform quote by changing sellToken (which is DAI) to USDC
        quote.sellToken = ERC20(AddressBook.USDC);
        // Adding liquidity will do:
        // 1. We pull DAI tokens from the user
        // 2. 0x swap reverts because there's not enough DAI to pull from user
        vm.expectRevert();
        // TODO: fix expectRevert
        // vm.expectRevert(abi.encodeWithSelector(Errors.ZeroExSwapFailed.selector, "Dai/insufficient-balance"));
        this._addLiquidityFromToken(adapter, maturity, quote, amt);
    }

    function testMainnetRemoveLiquidity() public {
        // Roll to Feb-08-2023 09:12:23 AM +UTC where we have a real adapter (wstETH adapter)
        vm.rollFork(16583087);

        // Re-deploy Periphery and set everything up
        _setUp(false);

        // Get the existing adapter (wstETH adapter) and set it up on the Periphery
        (address adapter, uint256 maturity) = _getExistingAdapterAndSeries();

        uint256 amt = 0.1e18; // 1 LP

        // 1. Remove liquidity to DAI
        // Create quote from 0x API to do an underlying (stETH) to DAI swap
        Periphery.SwapQuote memory quote = _getSellUnderlyingQuote(adapter, AddressBook.DAI);
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(address(quote.sellToken), AddressBook.DAI, 0, 0);
        _removeLiquidityToToken(adapter, maturity, quote, amt);

        // 2. Remove liquidity to ETH
        // Create quote from 0x API to do an underlying (stETH) to ETH swap
        quote = _getSellUnderlyingQuote(adapter, periphery.ETH());
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(address(quote.sellToken), periphery.ETH(), 0, 0);
        _removeLiquidityToToken(adapter, maturity, quote, amt);

        // 3.1 Remove liquidity to Target
        // Create quote only with buyToken as target. We don't care about the other params
        // since no swap on 0x will be done
        quote = _getSellUnderlyingQuote(adapter, MockAdapter(adapter).target());
        _removeLiquidityToToken(adapter, maturity, quote, amt);

        // 3.2 Remove liquidity to Target
        // Create quote only with buyToken as target. We don't care about the other params
        // since no swap on 0x will be done. Eg. We are sending here sellToken = DAI but
        // will be ignored in this case. When removing liquidity, sellToken would always be the LP token
        quote = _getSellUnderlyingQuote(adapter, MockAdapter(adapter).target());
        quote.sellToken = ERC20(AddressBook.DAI);
        _removeLiquidityToToken(adapter, maturity, quote, amt);

        // 4. Remove liquidity to Underlying
        // Create quote only with sellToken as target. We don't care about the other params
        // since no swap on 0x will be done
        quote = _getSellUnderlyingQuote(adapter, MockAdapter(adapter).underlying());
        _removeLiquidityToToken(adapter, maturity, quote, amt);

        // 5. Remove liquidity with malformed quote: buyToken is USDC but not DAI
        // Create quote from 0x API to do an underlying (stETH) to DAI swap
        quote = _getSellUnderlyingQuote(adapter, AddressBook.DAI);
        // Malform quote by changing buyToken (which is DAI) to USDC
        quote.buyToken = ERC20(AddressBook.USDC);
        // Removing liquidity will do:
        // 1. We pull LP tokens from the user
        // 2. We swap LP tokens for target (Space)
        // 3. We unwrap target for underlying (stETH)
        // 4. We succefully execute a 0x swap from stETH to DAI (because that's what's in swapCallData)
        // 5. Since buyToken is now USDC and we have received 0 USDC, it will revert
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroSwapAmt.selector));
        this._removeLiquidityToToken(adapter, maturity, quote, amt);
        vm.stopPrank();

        // 6. Remove liquidity with malformed quote: sellToken is USDC but not stETH
        // Create quote from 0x API to do an underlying (stETH) to DAI swap
        quote = _getSellUnderlyingQuote(adapter, AddressBook.DAI);
        // Malform quote by changing sellToken (which is underlying) to USDC
        quote.sellToken = ERC20(AddressBook.USDC);
        // Removing liquidity will do:
        // 1. We pull LP tokens from the user
        // 2. We swap LP tokens for target (Space)
        // 3. We unwrap target for underlying (stETH)
        // Since sellToken is now USDC, _fillQuote will give approval to 0x to pull USDC instead o the underlying
        // (stETH) and the swap will fail
        vm.expectRevert();
        // vm.expectRevert(abi.encodeWithSelector(Errors.ZeroExSwapFailed.selector, "TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE"));
        // TODO: fix expectRevert
        this._removeLiquidityToToken(adapter, maturity, quote, amt);
    }

    /* ========== PT SWAPS ========== */

    function testMainnetSwapAllForPTs() public {
        // Roll to Feb-08-2023 09:12:23 AM +UTC where we have a real adapter (wstETH adapter)
        vm.rollFork(16583087);

        // Re-deploy Periphery and set everything up
        _setUp(false);

        // Get the existing adapter (wstETH adapter) and set it up on the Periphery
        (address adapter, uint256 maturity) = _getExistingAdapterAndSeries();

        // 1. Swap DAI for PTs
        ERC20 token = ERC20(AddressBook.DAI);
        uint256 amt = 10**token.decimals(); // 1 DAI
        // Create quote from 0x API to do a 1 DAI to underlying swap
        Periphery.SwapQuote memory quote = _getBuyUnderlyingQuote(adapter, address(token));
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(address(token), address(quote.buyToken), 0, 0);
        _swapTokenForPTs(adapter, maturity, quote, amt);

        // 2. Swap target for PTs
        ERC20 target = ERC20(MockAdapter(adapter).target());
        amt = 10**(target.decimals() - 1); // 0.1 target
        quote = _getBuyUnderlyingQuote(adapter, address(target));
        _swapTokenForPTs(adapter, maturity, quote, amt);

        // 3. Swap underlying for PTs
        ERC20 underlying = ERC20(MockAdapter(adapter).underlying());
        amt = 10**(underlying.decimals() - 1); // 0.1 underlying
        quote = _getBuyUnderlyingQuote(adapter, address(underlying));
        _swapTokenForPTs(adapter, maturity, quote, amt);

        // 4. Swap DAI for PTs with malformed quote: buyToken is not underlying but USDC
        token = ERC20(AddressBook.DAI);
        amt = 10**token.decimals(); // 1 DAI
        // Create quote from 0x API to do a 1 DAI to underlying swap
        quote = _getBuyUnderlyingQuote(adapter, address(token));
        // Malform quote by changing buyToken (which is underlying) to USDC
        quote.buyToken = ERC20(AddressBook.USDC);
        // swapForPTs will do:
        // 1. We pull DAI tokens from the user
        // 2. We succefully execute a 0x swap from DAI to stETH
        // Since buyToken is now USDC and we have received 0 USDC, it will revert
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroSwapAmt.selector));
        this._swapTokenForPTs(adapter, maturity, quote, amt);

        // 5. Swap DAI for PTs with malformed quote: sellToken is not DAI but USDC and has USDC permit2 approvals and balances
        token = ERC20(AddressBook.DAI);
        amt = 10**token.decimals(); // 1 DAI
        // Create quote from 0x API to do a 1 DAI to underlying swap
        quote = _getBuyUnderlyingQuote(adapter, address(token));
        // Malform quote by changing sellToken (which is DAI) to USDC
        quote.sellToken = ERC20(AddressBook.USDC);
        // swapForPTs will do:
        // 1. We pull USDC (instead of DAI) tokens from the user
        // 2. 0x swap reverts because there's not enough DAI to pull from user
        // TODO: fix expectRevert
        // vm.expectRevert(abi.encodeWithSelector(Errors.ZeroExSwapFailed.selector, "Dai/insufficient-balance"));
        vm.expectRevert();
        this._swapTokenForPTs(adapter, maturity, quote, amt);
    }

    function testMainnetSwapPTsForAll() public {
        // Roll to Feb-08-2023 09:12:23 AM +UTC where we have a real adapter (wstETH adapter)
        vm.rollFork(16583087);

        // Re-deploy Periphery and set everything up
        _setUp(false);

        // Get existing adapter (wstETH adapter)
        (address adapter, uint256 maturity) = _getExistingAdapterAndSeries();

        // 1. Swap PTs for target
        Periphery.SwapQuote memory quote = _getSellUnderlyingQuote(adapter, MockAdapter(adapter).target());
        // _swapPTs(adapter, maturity, quote);

        // // 2. Swap PTs for underlying
        // quote = _getSellUnderlyingQuote(adapter, MockAdapter(adapter).underlying());
        // _swapPTs(adapter, maturity, quote);

        // // 3. Swap PTs for DAI
        // // Create 0x API quote to do a X underlying to token swap
        // // X is the amount of underlying resulting from the swap of PTs that we will be selling on 0x
        // quote = _getSellUnderlyingQuote(adapter, AddressBook.DAI);
        // vm.expectEmit(true, true, false, false);
        // emit BoughtTokens(MockAdapter(adapter).underlying(), AddressBook.DAI, 0, 0);
        // _swapPTs(adapter, maturity, quote);

        // 4. Swap PTs with malformed quote: sellToken is not underlying but USDC
        // Create 0x API quote to do a X underlying to token swap
        // X is the amount of underlying resulting from the swap of PTs that we will be selling on 0x
        quote = _getSellUnderlyingQuote(adapter, AddressBook.DAI);
        // Malform quote by changing sellToken (which is underlying) to USDC
        quote.sellToken = ERC20(AddressBook.USDC);
        // swapPTs will do:
        // 1. We pull USDC (instead of DAI) tokens from the user
        // 2. 0x swap reverts because there's not enough USDC to pull from user
        vm.expectRevert();
        // TODO: fix expectRevert
        // vm.expectRevert(abi.encodeWithSelector(Errors.ZeroExSwapFailed.selector, "Dai/insufficient-balance"));
        this._swapPTs(adapter, maturity, quote);
    }

    /* ========== YT SWAPS ========== */

    function testMainnetSwapYTsForTarget() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // 2. Initialize the pool by joining 0.5 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // 3. Swap 10% of bob's YTs for Target
        vm.startPrank(bob);
        uint256 ytBalPre = ERC20(yt).balanceOf(bob);
        uint256 targetBalPre = mockTarget.balanceOf(bob);
        ERC20(yt).approve(AddressBook.PERMIT2, ytBalPre / 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), yt);
        periphery.swapYTs(
            address(mockAdapter),
            maturity,
            ytBalPre / 10,
            0,
            bob,
            data,
            _getSellUnderlyingQuote(address(mockAdapter), address(mockTarget))
        );
        uint256 ytBalPost = ERC20(yt).balanceOf(bob);
        uint256 targetBalPost = mockTarget.balanceOf(bob);

        // Check that this address has fewer YTs and more Target
        assertLt(ytBalPost, ytBalPre);
        assertGt(targetBalPost, targetBalPre);
    }

    function testMainnetSwapTargetForYTsReturnValues() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // 3. Swap 0.005 of this address' Target for YTs
        uint256 TARGET_IN = 0.0234e18;
        // Calculated using sense-v1/yt-buying-lib
        uint256 TARGET_TO_BORROW = 0.1413769e18;

        uint256 targetBalPre = mockTarget.balanceOf(bob);
        uint256 ytBalPre = ERC20(yt).balanceOf(bob);

        Periphery.SwapQuote memory quote = _getBuyUnderlyingQuote(address(mockAdapter), address(mockTarget));
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapForYTs(
            address(mockAdapter),
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW, // Min out is just the amount of Target borrowed
            // (if at least the Target borrowed is not swapped out, then we won't be able to pay back the flashloan)
            bob,
            data,
            quote
        );
        uint256 targetBalPost = mockTarget.balanceOf(bob);
        uint256 ytBalPost = ERC20(yt).balanceOf(bob);

        // Check that the return values reflect the token balance changes
        assertEq(targetBalPre - targetBalPost + targetReturned, TARGET_IN);
        assertEq(ytBalPost - ytBalPre, ytsOut);
        // Check that the YTs returned are the result of issuing from the borrowed Target + transferred Target
        assertEq(ytsOut, (TARGET_IN + TARGET_TO_BORROW).fmul(1e18 - mockAdapter.ifee()));

        // Check that we got less than 0.000001 Target back
        assertTrue(targetReturned < 0.000001e18);
    }

    // Pattern similar to https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/test/ContinuousGDA.t.sol#L113
    function testMainnetSwapTargetForYTsBorrowCheckOne() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.005e18;
        uint256 TARGET_TO_BORROW = 0.03340541e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckTwo() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.01e18;
        uint256 TARGET_TO_BORROW = 0.06489898e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckThree() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1413769e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckFour() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.00003e18;
        uint256 TARGET_TO_BORROW = 0.0002066353449e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowTooMuch() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        // Check that borrowing too much Target will make it so that we can't pay back the flashloan
        uint256 TARGET_TO_BORROW = 0.1413769e18 + 0.02e18;
        vm.expectRevert("TRANSFER_FROM_FAILED");
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, 0);
    }

    function testMainnetSwapTargetForYTsBorrowTooLittle() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        // Check that borrowing too few Target will cause us to get too many Target back
        uint256 TARGET_TO_BORROW = 0.1413769e18 - 0.02e18;
        vm.expectRevert("TOO_MANY_TARGET_RETURNED");
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, 0);
    }

    function testMainnetSwapTargetForYTsMinOut() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1413769e18;

        vm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        // Check that we won't get TARGET_TO_BORROW out from swapping TARGET_TO_BORROW / 2 + TARGET_IN in
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW / 2, TARGET_TO_BORROW); // external call to catch the revert

        vm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        // Check that we won't get TARGET_TO_BORROW * 1.01 out from swapping TARGET_TO_BORROW + TARGET_IN in
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW.fmul(1.01e18));

        // 3. Get the Target amount we'd get back from buying YTs with these set params, then revert any state changes
        (uint256 targetReturnedPreview, ) = _callStaticBuyYTs(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);

        // Sanity check
        assertGt(targetReturnedPreview, 0);

        // Check that setting the min out to one more than the target we previewed fails
        vm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        this._checkYTBuyingParameters(
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW + targetReturnedPreview + 1
        );

        // Check that setting the min out to exactly the target we previewed succeeds
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW + targetReturnedPreview);
    }

    function testMainnetSwapTargetForYTsTransferOutOfBounds() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1413769e18;
        uint256 TARGET_TRANSFERRED_IN = 0.5e18;

        // Get the Target amount we'd get back from buying YTs with these set params, then revert any state changes
        (uint256 targetReturnedPreview, ) = _callStaticBuyYTs(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);

        mockTarget.mint(address(periphery), TARGET_TRANSFERRED_IN);

        Periphery.SwapQuote memory quote = _getBuyUnderlyingQuote(address(mockAdapter), address(mockTarget));
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapForYTs(
            address(mockAdapter),
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW,
            msg.sender,
            data,
            quote
        );

        assertEq(targetReturnedPreview + TARGET_TRANSFERRED_IN, targetReturned);
        assertEq(ytsOut, (TARGET_IN + TARGET_TO_BORROW).fmul(1e18 - mockAdapter.ifee()));
    }

    function testMainnetFuzzSwapTargetForYTsDifferentDecimals(uint8 underlyingDecimals, uint8 targetDecimals) public {
        // Bound decimals to between 4 and 18, inclusive
        underlyingDecimals = _fuzzWithBounds(underlyingDecimals, 4, 19);
        targetDecimals = _fuzzWithBounds(targetDecimals, 4, 19);
        MockToken newUnderlying = new MockToken("TestUnderlying", "TU", underlyingDecimals);
        MockTarget newMockTarget = new MockTarget(address(newUnderlying), "TestTarget", "TT", targetDecimals);

        // 1. Switch the Target/Underlying tokens out for new ones with different decimals vaules
        vm.etch(mockTarget.underlying(), address(newUnderlying).code);
        vm.etch(address(mockTarget), address(newMockTarget).code);

        // 2. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();
        // Sanity check that the new PT/YT tokens are using the updated decimals
        assertEq(uint256(ERC20(pt).decimals()), uint256(targetDecimals));

        // 3. Initialize the pool by joining 1 base unit of Target in, then swapping 0.5 base unit PTs in for Target
        _initializePool(maturity, ERC20(pt), 10**targetDecimals, 10**targetDecimals / 2);

        // Check buying YT params calculated using sense-v1/yt-buying-lib, adjusted for the target's decimals
        uint256 TARGET_IN = uint256(0.0234e18).fmul(10**targetDecimals);
        uint256 TARGET_TO_BORROW = uint256(0.1413769e18).fmul(10**targetDecimals);
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetFuzzSwapTargetForYTsDifferentScales(uint64 initScale, uint64 scale) public {
        vm.assume(initScale >= 1e9);
        vm.assume(scale >= initScale);

        // 1. Initialize scale
        mockAdapter.setScale(initScale);

        // 2. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 3. Initialize the pool by joining 1 Underlying worth of Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), uint256(1e18).fdivUp(initScale), 0.5e18);

        // 4. Update scale
        mockAdapter.setScale(scale);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib, adjusted with the current scale
        uint256 TARGET_IN = uint256(0.0234e18).fdivUp(scale);
        uint256 TARGET_TO_BORROW = uint256(0.1413769e18).fdivUp(scale);
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, 0);
    }

    /* ========== ZAPS: FILL QUOTE ========== */

    function testMainnetFillQuote() public {
        vm.rollFork(16669120); // Feb-15-2023 01:40:23 PM +UTC

        periphery = new PeripheryFQ(
            divider,
            poolManager,
            spaceFactory,
            balancerVault,
            address(permit2),
            AddressBook.EXCHANGE_PROXY
        );

        // USDC to DAI: https://api.0x.org/swap/v1/quote?sellToken=USDC&buyToken=DAI&sellAmount=1000000
        deal(AddressBook.USDC, address(periphery), 1e6);
        Periphery.SwapQuote memory quote = Periphery.SwapQuote({
            sellToken: ERC20(AddressBook.USDC),
            buyToken: ERC20(AddressBook.DAI),
            spender: AddressBook.EXCHANGE_PROXY, // from 0x API
            swapTarget: payable(AddressBook.EXCHANGE_PROXY), // from 0x API
            swapCallData: hex"d9627aa4000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000dcbcf018b24904300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000001a47bee37d63f3494d"
        });
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(AddressBook.USDC, AddressBook.DAI, 0, 0);
        uint256 daiBalanceBefore = ERC20(AddressBook.DAI).balanceOf(address(periphery));
        uint256 usdcBalanceBefore = ERC20(AddressBook.USDC).balanceOf(address(periphery));
        periphery.fillQuote(quote);
        assertEq(ERC20(AddressBook.USDC).balanceOf(address(periphery)), usdcBalanceBefore - 1e6);
        assertGt(ERC20(AddressBook.DAI).balanceOf(address(periphery)), daiBalanceBefore);

        // DAI to wstETH: https://api.0x.org/swap/v1/quote?sellToken=DAI&buyToken=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&sellAmount=1000000000000000000
        deal(AddressBook.DAI, address(periphery), 1e18);
        quote.sellToken = ERC20(AddressBook.DAI);
        quote.buyToken = ERC20(AddressBook.WSTETH);
        quote.spender = AddressBook.EXCHANGE_PROXY; // from 0x API
        quote.swapTarget = payable(AddressBook.EXCHANGE_PROXY); // from 0x API
        quote
            .swapCallData = hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000001dac0c712aec5000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000005be293b84c63f34953";
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(AddressBook.DAI, AddressBook.WSTETH, 0, 0);
        daiBalanceBefore = ERC20(AddressBook.DAI).balanceOf(address(periphery));
        uint256 wstETHBalanceBefore = ERC20(AddressBook.WSTETH).balanceOf(address(periphery));
        periphery.fillQuote(quote);
        assertEq(ERC20(AddressBook.DAI).balanceOf(address(periphery)), daiBalanceBefore - 1e18);
        assertGt(ERC20(AddressBook.WSTETH).balanceOf(address(periphery)), wstETHBalanceBefore);

        // wstETH to ETH: https://api.0x.org/swap/v1/quote?sellToken=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&buyToken=ETH&sellAmount=1000000000000000000
        deal(AddressBook.WSTETH, address(periphery), 1e18);
        vm.prank(address(periphery));
        quote.sellToken = ERC20(AddressBook.WSTETH);
        quote.buyToken = ERC20(periphery.ETH());
        quote.spender = AddressBook.EXCHANGE_PROXY; // from 0x API
        quote.swapTarget = payable(AddressBook.EXCHANGE_PROXY); // from 0x API
        quote
            .swapCallData = hex"803ba26d00000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000f3e79cc1be1750f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b7f39c581f595b53c5cb19bd0b3f8da6c935e2ca00001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000f45c5a2d7163f34956";
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(AddressBook.WSTETH, periphery.ETH(), 0, 0);
        wstETHBalanceBefore = ERC20(AddressBook.WSTETH).balanceOf(address(periphery));
        uint256 ethBalanceBefore = address(periphery).balance;
        periphery.fillQuote(quote);
        assertEq(ERC20(AddressBook.WSTETH).balanceOf(address(periphery)), wstETHBalanceBefore - 1e18);
        assertGt(address(periphery).balance, ethBalanceBefore);

        // ETH to USDC: https://api.0x.org/swap/v1/quote?sellToken=ETH&buyToken=USDC&sellAmount=1000000000000000000
        deal(address(periphery), 1 ether); // we need 1 ether for the swap and some extra for the gas
        quote.sellToken = ERC20(periphery.ETH());
        quote.buyToken = ERC20(AddressBook.USDC);
        quote.spender = 0x0000000000000000000000000000000000000000; // from 0x API
        quote.swapTarget = payable(AddressBook.EXCHANGE_PROXY); // from 0x API
        quote
            .swapCallData = hex"3598d8ab00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000065216b2a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000064a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000000000000000000035693c291f63f34958";
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(periphery.ETH(), AddressBook.USDC, 0, 0);
        ethBalanceBefore = address(periphery).balance;
        usdcBalanceBefore = ERC20(AddressBook.USDC).balanceOf(address(periphery));
        vm.prank(address(periphery));
        periphery.fillQuote{ value: 1 ether }(quote);
        assertEq(address(periphery).balance, ethBalanceBefore - 1 ether);
        assertGt(ERC20(AddressBook.USDC).balanceOf(address(periphery)), usdcBalanceBefore);

        // Potentially conflictive tokens ///

        // USDT to WETH: https://api.0x.org/swap/v1/quote?sellToken=USDT&buyToken=WETH&sellAmount=1000000
        deal(AddressBook.USDT, address(periphery), 1e6);
        quote.sellToken = ERC20(AddressBook.USDT);
        quote.buyToken = ERC20(AddressBook.WETH);
        quote.spender = AddressBook.EXCHANGE_PROXY; // from 0x API
        quote.swapTarget = payable(AddressBook.EXCHANGE_PROXY); // from 0x API
        quote
            .swapCallData = hex"d9627aa4000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000020b707ccd777700000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000000000000000000064f89ce49863f3495b";

        // Make an approval so the allowance is not 0
        vm.prank(address(periphery));
        ERC20(AddressBook.USDT).safeApprove(address(periphery), 1e6);

        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(AddressBook.USDT, AddressBook.WETH, 0, 0);
        uint256 usdtBalanceBefore = ERC20(AddressBook.USDT).balanceOf(address(periphery));
        uint256 wethBalanceBefore = ERC20(AddressBook.WETH).balanceOf(address(periphery));
        periphery.fillQuote(quote);
        assertEq(ERC20(AddressBook.USDT).balanceOf(address(periphery)), usdtBalanceBefore - 1e6);
        assertGt(ERC20(AddressBook.WETH).balanceOf(address(periphery)), wethBalanceBefore);

        // ETH to USDC (small amount): https://api.0x.org/swap/v1/quote?sellToken=ETH&buyToken=USDC&buyAmount=500000000
        // TODO: not working with amounts < 500 USDC, why????
        deal(address(periphery), 2 ether); // we need 1 ether for the swap and some extra for the gas
        quote.sellToken = ERC20(periphery.ETH());
        quote.buyToken = ERC20(AddressBook.USDC);
        quote.spender = 0x0000000000000000000000000000000000000000; // from 0x API
        quote.swapTarget = payable(AddressBook.EXCHANGE_PROXY); // from 0x API
        quote
            .swapCallData = hex"3598d8ab0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000001dcd65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000064a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000e3d2f616d563f34a09";
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(periphery.ETH(), AddressBook.USDC, 0, 0);
        ethBalanceBefore = address(periphery).balance;
        usdcBalanceBefore = ERC20(AddressBook.USDC).balanceOf(address(periphery));
        vm.prank(address(periphery));
        periphery.fillQuote{ value: 1 ether }(quote);
        assertEq(address(periphery).balance, ethBalanceBefore - 1 ether);
        assertGt(ERC20(AddressBook.USDC).balanceOf(address(periphery)), usdcBalanceBefore);
    }

    function testMainnetFillQuoteEdgeCases() public {
        vm.rollFork(16669120); // Feb-15-2023 01:40:23 PM +UTC

        periphery = new PeripheryFQ(
            divider,
            poolManager,
            spaceFactory,
            balancerVault,
            address(permit2),
            AddressBook.EXCHANGE_PROXY
        );

        // USDC to DAI: https://api.0x.org/swap/v1/quote?sellToken=USDC&buyToken=DAI&sellAmount=1000000
        bytes
            memory USDC_DAI_SWAP_QUOTE = hex"d9627aa4000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000dcbcf018b24904300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000001a47bee37d63f3494d";

        // 1. Revert if sell token is address(0)
        deal(AddressBook.USDC, address(periphery), 1e6);
        Periphery.SwapQuote memory quote = Periphery.SwapQuote({
            sellToken: ERC20(address(0)),
            buyToken: ERC20(AddressBook.DAI),
            spender: AddressBook.EXCHANGE_PROXY, // from 0x API
            swapTarget: payable(AddressBook.EXCHANGE_PROXY), // from 0x API
            swapCallData: USDC_DAI_SWAP_QUOTE
        });
        vm.expectRevert();
        periphery.fillQuote(quote);

        // 2. Revert if buy token is address(0)
        deal(AddressBook.USDC, address(periphery), 1e6);
        quote = Periphery.SwapQuote({
            sellToken: ERC20(address(0)),
            buyToken: ERC20(AddressBook.DAI),
            spender: AddressBook.EXCHANGE_PROXY, // from 0x API
            swapTarget: payable(AddressBook.EXCHANGE_PROXY), // from 0x API
            swapCallData: USDC_DAI_SWAP_QUOTE
        });
        vm.expectRevert();
        periphery.fillQuote(quote);

        // 3. Does NOT revert if sell token does not match the one in the swap call data
        // but there's enough allowance and balance to spend the token of the swapCallData
        // We assume there's approval from periphery to Exchange Proxy to spend USDC (probably from a previous swap)
        deal(AddressBook.USDC, address(periphery), 1e6);
        vm.prank(address(periphery));
        ERC20(AddressBook.USDC).safeApprove(AddressBook.EXCHANGE_PROXY, type(uint256).max);

        deal(AddressBook.USDT, address(periphery), 1e6);
        quote = Periphery.SwapQuote({
            sellToken: ERC20(AddressBook.USDT),
            buyToken: ERC20(AddressBook.DAI),
            spender: AddressBook.EXCHANGE_PROXY, // from 0x API
            swapTarget: payable(AddressBook.EXCHANGE_PROXY), // from 0x API
            swapCallData: USDC_DAI_SWAP_QUOTE
        });
        periphery.fillQuote(quote);

        // 4. Revert if sell token does not match the one in the swap call data
        // and allowance is 0
        // Reset approval from periphery to Exchange Proxy
        vm.prank(address(periphery));
        ERC20(AddressBook.USDC).safeApprove(AddressBook.EXCHANGE_PROXY, 0);

        // Load USDT (NOT USDC)
        deal(AddressBook.USDT, address(periphery), 1e6);
        quote = Periphery.SwapQuote({
            sellToken: ERC20(AddressBook.USDT),
            buyToken: ERC20(AddressBook.DAI),
            spender: AddressBook.EXCHANGE_PROXY, // from 0x API
            swapTarget: payable(AddressBook.EXCHANGE_PROXY), // from 0x API
            swapCallData: USDC_DAI_SWAP_QUOTE
        });
        vm.expectRevert();
        periphery.fillQuote(quote);

        // 4. Revert if sell token does not match the one in the swap call data
        // there's enough allowance but no balance
        deal(AddressBook.USDC, address(periphery), 0);

        // Load USDT (NOT USDC)
        deal(AddressBook.USDT, address(periphery), 1e6);
        quote = Periphery.SwapQuote({
            sellToken: ERC20(AddressBook.USDT),
            buyToken: ERC20(AddressBook.DAI),
            spender: AddressBook.EXCHANGE_PROXY, // from 0x API
            swapTarget: payable(AddressBook.EXCHANGE_PROXY), // from 0x API
            swapCallData: USDC_DAI_SWAP_QUOTE
        });
        vm.expectRevert();
        periphery.fillQuote(quote);
    }

    function testMainnetCantFillQuoteIfNotEnoughBalance() public {
        vm.rollFork(16664305); // Feb-15-2023 01:40:23 PM +UTC

        periphery = new PeripheryFQ(
            divider,
            poolManager,
            spaceFactory,
            balancerVault,
            address(permit2),
            AddressBook.EXCHANGE_PROXY
        );

        // USDC to DAI: https://api.0x.org/swap/v1/quote?sellToken=USDC&buyToken=DAI&sellAmount=1000000
        deal(AddressBook.USDC, address(periphery), 0.1e6);
        Periphery.SwapQuote memory quote = Periphery.SwapQuote({
            sellToken: ERC20(AddressBook.USDC),
            buyToken: ERC20(AddressBook.DAI),
            spender: AddressBook.EXCHANGE_PROXY, // from 0x API
            swapTarget: payable(AddressBook.EXCHANGE_PROXY), // from 0x API
            swapCallData: hex"d9627aa4000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000db2bafbe3d0747500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000d9bcd8ea3863f265f8"
        });
        vm.expectRevert();
        periphery.fillQuote(quote);
    }

    function testMainnetTransferFromOldSchool() public {
        Periphery.PermitData memory permit;

        // Revert if not enough allowance
        vm.expectRevert();
        periphery.transferFrom(permit, AddressBook.USDC, 1e6);

        // Revert if approved but not enough balance
        ERC20(AddressBook.USDC).safeApprove(address(periphery), 1e6);
        vm.expectRevert();
        periphery.transferFrom(permit, AddressBook.USDC, 1e6);

        // Work if approved and enough balance
        deal(AddressBook.USDC, address(this), 1e6);
        periphery.transferFrom(permit, AddressBook.USDC, 1e6);
        assertEq(ERC20(AddressBook.USDC).balanceOf(address(periphery)), 1e6);
        assertEq(ERC20(AddressBook.USDC).balanceOf(address(this)), 0);
    }

    function testMainnetPermitTransferFrom() public {
        Periphery.PermitData memory permit;

        // Fail it not enough allowance and using wrong private key
        permit = generatePermit(jimPrivKey, address(periphery), AddressBook.USDC);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        vm.prank(bob);
        periphery.transferFrom(permit, AddressBook.USDC, 1e6);

        deal(AddressBook.USDC, bob, 2e6);

        // Fail if not enough allowance but enough balance and correct private key
        permit = generatePermit(bobPrivKey, address(periphery), AddressBook.USDC);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(bob);
        periphery.transferFrom(permit, AddressBook.USDC, 1e6);

        // Fail if enough allowance and balance but using wrong private key
        vm.prank(bob);
        ERC20(AddressBook.USDC).approve(AddressBook.PERMIT2, 2e6);
        permit = generatePermit(jimPrivKey, address(periphery), AddressBook.USDC);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        vm.prank(bob);
        periphery.transferFrom(permit, AddressBook.USDC, 1e6);

        // Work if enough allowance and balance and correct private key
        permit = generatePermit(bobPrivKey, address(periphery), AddressBook.USDC);
        vm.prank(bob);
        periphery.transferFrom(permit, AddressBook.USDC, 1e6);
        assertEq(ERC20(AddressBook.USDC).balanceOf(bob), 1e6);
        assertEq(ERC20(AddressBook.USDC).balanceOf(address(periphery)), 1e6);

        // Can't re-use permit
        vm.expectRevert(abi.encodeWithSignature("InvalidNonce()"));
        vm.prank(bob);
        periphery.transferFrom(permit, AddressBook.USDC, 1e6);

        // TODO: test that even though approval to PERMIT2 can be unlimited
        // if permit message if for X amount, only X amount can be transferred
    }

    // INTERNAL HELPERS ––––––––––––

    function _sponsorSeries()
        public
        returns (
            uint256 maturity,
            address pt,
            address yt
        )
    {
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        maturity = DateTimeFull.timestampFromDateTime(year + 1, month, 1, 0, 0, 0);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (pt, yt) = periphery.sponsorSeries(
            address(mockAdapter),
            maturity,
            false,
            data,
            _getQuote(address(stake), address(stake))
        );
    }

    function _initializePool(
        uint256 maturity,
        ERC20 pt,
        uint256 targetToJoin,
        uint256 ptsToSwapIn
    ) public {
        MockTarget target = MockTarget(mockAdapter.target());

        {
            // Issue some PTs (& YTs) we'll use to initialize the pool with
            uint256 targetToIssueWith = ptsToSwapIn.fdivUp(1e18 - mockAdapter.ifee()).fdivUp(mockAdapter.scale());
            deal(address(target), bob, targetToIssueWith + targetToJoin);

            vm.startPrank(bob);
            target.approve(address(divider), targetToIssueWith);
            Divider(divider).issue(address(mockAdapter), maturity, targetToIssueWith);
            // Sanity check that we have the PTs we need to swap in, either exactly, or close to (modulo rounding)
            assertTrue(pt.balanceOf(bob) >= ptsToSwapIn && pt.balanceOf(bob) <= ptsToSwapIn + 100);
        }

        {
            // Add Liquidity from Target to the Space pool
            periphery.addLiquidity(
                address(mockAdapter),
                maturity,
                targetToJoin,
                0,
                0,
                1,
                bob,
                generatePermit(bobPrivKey, address(periphery), address(target)),
                _getBuyUnderlyingQuote(address(mockAdapter), address(target))
            );
        }

        {
            // Swap PT balance for Target to initialize the PT side of the pool
            pt.approve(AddressBook.PERMIT2, ptsToSwapIn);
            Periphery.SwapQuote memory quote = _getSellUnderlyingQuote(address(mockAdapter), address(target));
            periphery.swapPTs(
                address(mockAdapter),
                maturity,
                ptsToSwapIn,
                0,
                bob,
                generatePermit(bobPrivKey, address(periphery), address(pt)),
                quote
            );
        }

        vm.stopPrank();
    }

    function _checkYTBuyingParameters(
        uint256 maturity,
        uint256 targetIn,
        uint256 targetToBorrow,
        uint256 minOut
    ) public {
        Periphery.SwapQuote memory quote = _getBuyUnderlyingQuote(address(mockAdapter), address(mockTarget));
        Periphery.PermitData memory permit = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapForYTs(
            address(mockAdapter),
            maturity,
            targetIn,
            targetToBorrow,
            minOut,
            bob,
            permit,
            quote
        );

        // Check that less than 0.01% of our Target got returned
        require(targetReturned <= targetIn.fmul(0.0001e18), "TOO_MANY_TARGET_RETURNED");
    }

    function _callStaticBuyYTs(
        uint256 maturity,
        uint256 targetIn,
        uint256 targetToBorrow,
        uint256 minOut
    ) public returns (uint256 targetReturnedPreview, uint256 ytsOutPreview) {
        try this._callRevertBuyYTs(maturity, targetIn, targetToBorrow, minOut) {} catch Error(string memory retData) {
            (targetReturnedPreview, ytsOutPreview) = abi.decode(bytes(retData), (uint256, uint256));
        }
    }

    function _callRevertBuyYTs(
        uint256 maturity,
        uint256 targetIn,
        uint256 targetToBorrow,
        uint256 minOut
    ) public {
        Periphery.SwapQuote memory quote = _getBuyUnderlyingQuote(address(mockAdapter), address(mockTarget));
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapForYTs(
            address(mockAdapter),
            maturity,
            targetIn,
            targetToBorrow,
            minOut,
            msg.sender,
            data,
            quote
        );

        revert(string(abi.encode(targetReturned, ytsOut)));
    }

    // Fuzz with bounds, inclusive of the lower bound, not inclusive of the upper bound
    function _fuzzWithBounds(
        uint8 number,
        uint8 lBound,
        uint8 uBound
    ) public returns (uint8) {
        return lBound + (number % (uBound - lBound));
    }

    function _getExistingAdapterAndSeries() public returns (address adapter, uint256 maturity) {
        // We use the wstETH adapter to have a real Series to test with
        adapter = 0x6fC4843aac4786b4420e954a2271BE16f225a482; // wstETH adapter
        maturity = 1811808000; // June 1st 2027

        // 1. Set Divider as unguarded
        vm.prank(AddressBook.SENSE_MULTISIG);
        Divider(divider).setGuarded(false);

        // 2. Set Periphery on Divider
        vm.prank(AddressBook.SENSE_MULTISIG);
        Divider(divider).setPeriphery(address(periphery));

        // 3. Onboard & Verify adapter into Periphery
        periphery.onboardAdapter(adapter, false);
        periphery.verifyAdapter(adapter, false);
    }

    /// @notice Get the swap call data for a swap from underlying
    /// We assume stETH to be underlying for these tests
    /// @dev if fromToken is either target or underlying, we just return the token, no quote is needed
    function _getSellUnderlyingQuote(address adapter, address toToken)
        public
        returns (Periphery.SwapQuote memory quote)
    {
        MockAdapter adapter = MockAdapter(adapter);
        if (toToken == adapter.underlying() || toToken == adapter.target()) {
            // Create a quote where we only fill the buyToken (with target or underlying) and the rest
            // is empty. This is used by the Periphery so it knows it does not have to perform a swap.
            quote.buyToken = ERC20(toToken);
        } else {
            // Quote to swap underlying for token via 0x
            address underlying = MockAdapter(adapter).underlying();
            quote.sellToken = ERC20(underlying);
            quote.buyToken = ERC20(toToken);
            quote.spender = AddressBook.EXCHANGE_PROXY; // from 0x API
            quote.swapTarget = payable(AddressBook.EXCHANGE_PROXY); // from 0x API
            if (address(quote.buyToken) == AddressBook.DAI)
                quote.swapCallData = _getSwapCallData(AddressBook.STETH, AddressBook.DAI);
            if (address(quote.buyToken) == periphery.ETH())
                quote.swapCallData = _getSwapCallData(AddressBook.STETH, periphery.ETH());
        }
    }

    /// @notice Get the swap call data for a swap to underlying
    /// We assume stETH to be underlying for these tests
    /// @dev if fromToken is either target or underlying, we just return the token, no quote is needed
    function _getBuyUnderlyingQuote(address adapter, address fromToken)
        public
        returns (Periphery.SwapQuote memory quote)
    {
        MockAdapter adapter = MockAdapter(adapter);
        if (fromToken == adapter.underlying() || fromToken == adapter.target()) {
            // Create a quote where we only fill the sellToken (with target or underlying) and the rest
            // is empty. This is used by the Periphery so it knows it does not have to perform a swap.
            quote.sellToken = ERC20(fromToken);
        } else {
            // Quote to swap token for underlying via 0x
            address underlying = MockAdapter(adapter).underlying();
            quote.sellToken = ERC20(fromToken);
            quote.buyToken = ERC20(underlying);
            quote.spender = AddressBook.EXCHANGE_PROXY; // from 0x API
            quote.swapTarget = payable(AddressBook.EXCHANGE_PROXY); // from 0x API
            if (address(quote.sellToken) == AddressBook.DAI)
                quote.swapCallData = _getSwapCallData(AddressBook.DAI, AddressBook.STETH);
            if (address(quote.sellToken) == periphery.ETH())
                quote.swapCallData = _getSwapCallData(periphery.ETH(), AddressBook.STETH);
        }
    }

    /// @dev If fromToken is the same as the toToken, we don't need to swao so we return
    /// the quote with the tokens as they are. No swap call data is returned.
    function _getQuote(address fromToken, address toToken) public returns (Periphery.SwapQuote memory quote) {
        if (fromToken == toToken) {
            quote.sellToken = ERC20(fromToken);
            quote.buyToken = ERC20(toToken);
            return quote;
        }
    }

    // function _getQuote(
    //     address adapter,
    //     address fromToken,
    //     address toToken
    // ) public returns (Periphery.SwapQuote memory quote) {
    //     if (fromToken == toToken) {
    //         quote.sellToken = ERC20(fromToken);
    //         quote.buyToken = ERC20(toToken);
    //         return quote;
    //     }
    //     MockAdapter adapter = MockAdapter(adapter);
    //     if (fromToken == address(0)) {
    //         if (toToken == adapter.underlying() || toToken == adapter.target()) {
    //             // Create a quote where we only fill the buyToken (with target or underlying) and the rest
    //             // is empty. This is used by the Periphery so it knows it does not have to perform a swap.
    //             quote.buyToken = ERC20(toToken);
    //         } else {
    //             // Quote to swap underlying for token via 0x
    //             address underlying = MockAdapter(adapter).underlying();
    //             quote.sellToken = ERC20(underlying);
    //             quote.buyToken = ERC20(toToken);
    //             quote.spender = AddressBook.EXCHANGE_PROXY; // from 0x API
    //             quote.swapTarget = payable(AddressBook.EXCHANGE_PROXY); // from 0x API
    //             if (address(quote.buyToken) == AddressBook.DAI) _getSwapCallData(AddressBook.STETH, AddressBook.DAI);
    //             if (address(quote.buyToken) == periphery.ETH()) _getSwapCallData(AddressBook.STETH, periphery.ETH());
    //         }
    //     } else {
    //         if (fromToken == adapter.underlying() || fromToken == adapter.target()) {
    //             // Create a quote where we only fill the sellToken (with target or underlying) and the rest
    //             // is empty. This is used by the Periphery so it knows it does not have to perform a swap.
    //             quote.sellToken = ERC20(fromToken);
    //         } else {
    //             // Quote to swap token for underlying via 0x
    //             address underlying = MockAdapter(adapter).underlying();
    //             quote.sellToken = ERC20(fromToken);
    //             quote.buyToken = ERC20(underlying);
    //             quote.spender = AddressBook.EXCHANGE_PROXY; // from 0x API
    //             quote.swapTarget = payable(AddressBook.EXCHANGE_PROXY); // from 0x API
    //             if (address(quote.sellToken) == AddressBook.DAI) _getSwapCallData(AddressBook.DAI, AddressBook.STETH);
    //             if (address(quote.sellToken) == periphery.ETH()) _getSwapCallData(periphery.ETH(), AddressBook.STETH);
    //         }
    //     }
    // }

    function _getSwapCallData(address from, address to) internal view returns (bytes memory) {
        if (from == AddressBook.DAI && to == AddressBook.STETH) {
            return DAI_STETH_SWAP_QUOTE_DATA;
        }
        if (from == AddressBook.STETH && to == AddressBook.DAI) {
            return STETH_DAI_SWAP_QUOTE_DATA;
        }
        if (from == AddressBook.STETH && to == periphery.ETH()) {
            return STETH_ETH_SWAP_QUOTE_DATA;
        }
        if (from == periphery.ETH() && to == AddressBook.STETH) {
            return ETH_STETH_SWAP_QUOTE_DATA;
        }
        if (from == AddressBook.USDC && to == AddressBook.DAI) {
            return USDC_DAI_SWAP_QUOTE_DATA;
        }
    }

    function _swapTokenForPTs(
        address adapter,
        uint256 maturity,
        Periphery.SwapQuote memory quote,
        uint256 amt
    ) public {
        ERC20 token = ERC20(address(quote.sellToken));

        // 0. Get PT address
        address pt = Divider(divider).pt(adapter, maturity);

        // 1. Load token into Bob's address
        if (address(token) == AddressBook.STETH) {
            // get steth by unwrapping wsteth because `deal()` won't work
            deal(AddressBook.WSTETH, bob, amt);
            vm.prank(bob);
            WstETHLike(AddressBook.WSTETH).unwrap(amt);
        } else {
            deal(address(token), bob, amt);
        }

        // 2. Approve PERMIT2 to spend token
        vm.prank(bob);
        token.approve(AddressBook.PERMIT2, type(uint256).max);

        // 3. Generate permit message and signature
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(token));

        // 4. Swap Token for PTs
        uint256 ptBalPre = ERC20(pt).balanceOf(bob);
        uint256 tokenBalPre = token.balanceOf(bob);

        vm.prank(bob);
        uint256 ptBal = periphery.swapForPTs(adapter, maturity, amt, 0, bob, data, quote);

        uint256 tokenBalPost = token.balanceOf(bob);
        uint256 ptBalPost = ERC20(pt).balanceOf(bob);

        // Check that the return values reflect the token balance changes
        assertEq(tokenBalPre, tokenBalPost + amt);
        assertEq(ptBalPost, ptBalPre + ptBal);
    }

    function _swapPTs(
        address adapter,
        uint256 maturity,
        Periphery.SwapQuote memory quote
    ) public {
        ERC20 token = ERC20(address(quote.buyToken));
        // 0. Get PT address
        address pt = Divider(divider).pt(adapter, maturity);
        ERC20 ptToken = ERC20(pt);

        // 1. Approve PERMIT2 to spend PTs
        vm.prank(bob);
        ptToken.approve(AddressBook.PERMIT2, type(uint256).max);

        {
            // 2. Issue PTs from 1 target
            ERC20 target = ERC20(MockAdapter(adapter).target());
            uint256 amt = 1 * 10**(target.decimals() - 1);
            deal(address(target), bob, amt);
            vm.prank(bob);
            target.approve(divider, type(uint256).max);
            vm.prank(bob);
            Divider(divider).issue(adapter, maturity, amt);
        }

        // 3. Generate permit message and signature
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), pt);

        {
            // 4. Swap PTs for Token
            uint256 ptBalPre = ERC20(pt).balanceOf(bob);
            uint256 tokenBalPre = token.balanceOf(bob);

            vm.prank(bob);
            uint256 tokenBal = periphery.swapPTs(adapter, maturity, ptBalPre, 0, bob, data, quote);
            uint256 tokenBalPost = token.balanceOf(bob);
            uint256 ptBalPost = ERC20(pt).balanceOf(bob);

            // Check that the return values reflect the token balance changes
            assertEq(ptBalPost, 0);
            assertApproxEqAbs(tokenBalPre, tokenBalPost + 1 - tokenBal, 1); // +1 because of Lido's 1 wei corner case: https://docs.lido.fi/guides/steth-integration-guide#1-wei-corner-case
        }
    }

    function _addLiquidityFromToken(
        address adapter,
        uint256 maturity,
        Periphery.SwapQuote memory quote,
        uint256 amt
    ) public {
        ERC20 token = ERC20(address(quote.sellToken));

        // 1. Load token into Bob's address
        // deal(address(token), bob, amt);
        if (address(token) == AddressBook.STETH) {
            // get steth by unwrapping wsteth because `deal()` won't work
            deal(AddressBook.WSTETH, bob, amt);
            vm.prank(bob);
            WstETHLike(AddressBook.WSTETH).unwrap(amt);
        } else {
            deal(address(token), bob, amt);
        }

        // 2. Approve PERMIT2 to spend token
        vm.prank(bob);
        token.approve(AddressBook.PERMIT2, type(uint256).max);

        // 3. Add liquidity from Token
        uint256 tokenBalPre = token.balanceOf(bob);
        uint256 lpBalPre = ERC20(SpaceFactoryLike(spaceFactory).pools(address(adapter), maturity)).balanceOf(bob);

        {
            uint256 lpShares = _addLiquidity(adapter, maturity, quote, amt);
            // Check that the return values reflect the token balance changes
            assertApproxEqAbs(tokenBalPre, token.balanceOf(bob) + amt, 1);
            assertEq(
                ERC20(SpaceFactoryLike(spaceFactory).pools(address(adapter), maturity)).balanceOf(bob),
                lpBalPre + lpShares
            );
        }
    }

    function _addLiquidityFromETH(
        address adapter,
        uint256 maturity,
        Periphery.SwapQuote memory quote,
        uint256 amt
    ) public {
        address sellToken = address(quote.sellToken);

        // 1. Load ETH into Bob's address
        deal(bob, amt + 1 ether);

        // 2. Add liquidity from Token
        uint256 ethBalPre = address(bob).balance;
        uint256 lpBalPre = ERC20(SpaceFactoryLike(spaceFactory).pools(address(adapter), maturity)).balanceOf(bob);

        {
            uint256 lpShares = _addLiquidity(adapter, maturity, quote, amt);
            // Check that the return values reflect the token balance changes
            assertEq(ethBalPre, address(bob).balance + amt);
            assertEq(
                ERC20(SpaceFactoryLike(spaceFactory).pools(address(adapter), maturity)).balanceOf(bob),
                lpBalPre + lpShares
            );
        }
    }

    function _addLiquidity(
        address adapter,
        uint256 maturity,
        Periphery.SwapQuote memory quote,
        uint256 amt
    ) internal returns (uint256 lpShares) {
        vm.startPrank(bob);
        (, , lpShares) = periphery.addLiquidity{ value: address(quote.sellToken) == periphery.ETH() ? amt : 0 }(
            adapter,
            maturity,
            amt,
            0,
            0,
            1,
            bob,
            generatePermit(bobPrivKey, address(periphery), address(quote.sellToken)),
            quote
        );
        vm.stopPrank();
    }

    function _removeLiquidityToToken(
        address adapter,
        uint256 maturity,
        Periphery.SwapQuote memory quote,
        uint256 amt
    ) public {
        bool isETH = address(quote.buyToken) == periphery.ETH();
        ERC20 token = quote.buyToken;
        ERC20 pt = ERC20(Divider(divider).pt(adapter, maturity));
        ERC20 lp = ERC20(SpaceFactoryLike(spaceFactory).pools(address(adapter), maturity));

        // 1. Load LP into Bob's address
        deal(address(lp), bob, amt);

        // 2. Approve PERMIT2 to spend LP
        vm.prank(bob);
        lp.approve(AddressBook.PERMIT2, type(uint256).max);

        // 3. Remove liquidity to Token
        uint256 lpBalPre = lp.balanceOf(bob);
        uint256 tokenBalPre = isETH ? address(bob).balance : token.balanceOf(bob);
        uint256 ptBalPre = pt.balanceOf(bob);

        {
            (uint256 tBal, uint256 ptBal) = _removeLiquidity(adapter, maturity, quote, amt);
            // Check that the return values reflect the token balance changes
            assertEq(lp.balanceOf(bob), lpBalPre - amt);
            assertEq(pt.balanceOf(bob), ptBalPre + ptBal);
            uint256 tokenBal = isETH ? address(bob).balance : token.balanceOf(bob);
            assertTrue(tokenBal > 0);
            assertApproxEqAbs(tokenBal, tokenBalPre + tBal, 1);
        }
    }

    function _removeLiquidity(
        address adapter,
        uint256 maturity,
        Periphery.SwapQuote memory quote,
        uint256 amt
    ) internal returns (uint256 tBal, uint256 ptBal) {
        address lp = SpaceFactoryLike(spaceFactory).pools(address(adapter), maturity);
        vm.startPrank(bob);
        (tBal, ptBal) = periphery.removeLiquidity(
            adapter,
            maturity,
            amt,
            new uint256[](2),
            0,
            true, // swap PTs for tokens
            bob,
            generatePermit(bobPrivKey, address(periphery), lp),
            quote
        );
        vm.stopPrank();
    }

    // required for refunds
    receive() external payable {}

    /* ========== LOGS ========== */

    event BoughtTokens(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 indexed boughtAmount
    );
}
