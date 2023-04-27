// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { MockERC4626 } from "../test-helpers/mocks/MockERC4626.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

import { ChainlinkPriceOracle, FeedRegistryLike } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";
import { IPriceFeed } from "../../adapters/abstract/IPriceFeed.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { OwnableERC4626Adapter } from "../../adapters/abstract/erc4626/OwnableERC4626Adapter.sol";
import { OwnableERC4626CropAdapter } from "../../adapters/abstract/erc4626/OwnableERC4626CropAdapter.sol";
import { Divider, TokenHandler } from "../../Divider.sol";

import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";

contract MockOracle is IPriceFeed {
    function price(address) external view returns (uint256 price) {
        return 555e18;
    }
}

contract Opener is Test {
    Divider public divider;
    uint256 public maturity;
    address public adapter;

    constructor(
        Divider _divider,
        uint256 _maturity,
        address _adapter
    ) {
        divider = _divider;
        maturity = _maturity;
        adapter = _adapter;
    }

    function onSponsorWindowOpened(address, uint256) external {
        vm.prank(divider.periphery()); // impersonate Periphery
        divider.initSeries(adapter, maturity, msg.sender);
    }
}

contract OwnableERC4626AdapterTest is Test {
    using FixedMath for uint256;

    MockToken public stake;
    MockToken public underlying;
    MockERC4626 public target;
    MasterPriceOracle public masterOracle;
    ChainlinkPriceOracle public chainlinkOracle;
    Opener public opener;
    Opener public cropOpener;

    Divider public divider;
    OwnableERC4626Adapter public adapter;
    OwnableERC4626CropAdapter public cropAdapter;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint8 public constant MODE = 1; // weekly

    uint256 public constant INITIAL_BALANCE = 1.25e18;

    function setUp() public {
        TokenHandler tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        // Deploy Chainlink price oracle
        chainlinkOracle = new ChainlinkPriceOracle(0);

        // Deploy Sense master oracle
        address[] memory data;
        masterOracle = new MasterPriceOracle(address(chainlinkOracle), data, data);

        stake = new MockToken("Mock Stake", "MS", 18);
        underlying = new MockToken("Mock Underlying", "MU", 18);
        target = new MockERC4626(ERC20(address(underlying)), "Mock ERC-4626", "M4626", ERC20(underlying).decimals());

        underlying.mint(address(this), INITIAL_BALANCE);

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: address(masterOracle),
            stake: address(stake),
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            level: Constants.DEFAULT_LEVEL
        });

        adapter = new OwnableERC4626Adapter(
            address(divider),
            address(target),
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams
        );

        cropAdapter = new OwnableERC4626CropAdapter(
            address(divider),
            address(target),
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams,
            AddressBook.DAI
        );

        // Add adapter to Divider
        divider.setAdapter(address(adapter), true);
        divider.setAdapter(address(cropAdapter), true);

        vm.warp(1631664000); // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0); // Monday
        opener = new Opener(divider, maturity, address(adapter));
        cropOpener = new Opener(divider, maturity, address(cropAdapter));

        // Add Opener as trusted address on ownable adapter
        adapter.setIsTrusted(address(opener), true);
        cropAdapter.setIsTrusted(address(cropOpener), true);
    }

    function testOpenSponsorWindow() public {
        vm.prank(address(0xfede));
        vm.expectRevert("UNTRUSTED");
        adapter.openSponsorWindow();

        // No one can sponsor series directly using Divider (even if it's the Periphery)
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0); // Monday
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        divider.initSeries(address(adapter), maturity, msg.sender);

        // Mint some stake to sponsor Series
        stake.mint(divider.periphery(), 1e18);

        // Periphery approves divider to pull stake to sponsor series
        vm.prank(divider.periphery());
        stake.approve(address(divider), 1e18);

        // Opener can open sponsor window
        vm.prank(address(opener));
        vm.expectCall(address(divider), abi.encodeWithSelector(divider.initSeries.selector));
        adapter.openSponsorWindow();
    }

    function testCropOpenSponsorWindow() public {
        vm.prank(address(0xfede));
        vm.expectRevert("UNTRUSTED");
        cropAdapter.openSponsorWindow();

        // No one can sponsor series directly using Divider (even if it's the Periphery)
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0); // Monday
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        divider.initSeries(address(cropAdapter), maturity, msg.sender);

        // Mint some stake to sponsor Series
        stake.mint(divider.periphery(), 1e18);

        // Periphery approves divider to pull stake to sponsor series
        vm.prank(divider.periphery());
        stake.approve(address(divider), 1e18);

        // Opener can open sponsor window
        vm.prank(address(cropOpener));
        vm.expectCall(address(divider), abi.encodeWithSelector(divider.initSeries.selector));
        cropAdapter.openSponsorWindow();
    }
}
