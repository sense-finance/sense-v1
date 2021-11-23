// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Token } from "../../../tokens/Token.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { BalancerVault, IAsset } from "../../../external/balancer/Vault.sol";

// Internal references
import { Divider } from "../../../Divider.sol";
import { BaseAdapter as Adapter } from "../../../adapters/BaseAdapter.sol";
import { BalancerVault, IAsset } from "../../../external/balancer/Vault.sol";

import { MockToken } from "./MockToken.sol";

contract MockSpacePool is MockToken {
    using FixedMath for uint256;
    MockBalancerVault public vault;
    address public zero;
    address public underlying;

    constructor(
        address _vault,
        address _underlying,
        address _zero
    ) MockToken("Mock Yield Space Pool Token", "MYSPT", 18) {
        vault = MockBalancerVault(_vault);
        zero = _zero;
        underlying = _underlying;
    }

    function getPoolId() external view returns (bytes32) {
        return bytes32(0);
    }

    function getVault() external view returns (address) {
        return address(vault);
    }

    function onSwapGivenOut(
        bool _zeroIn,
        uint256 _amountOut,
        uint256 _reservesInAmount,
        uint256 _reservesOutAmount
    ) external view returns (uint256) {
        return 10e18;
    }

    // function totalSupply() external view returns (uint256) {
    //     return 1e18;
    // }
}

contract MockBalancerVault {
    using FixedMath for uint256;
    MockSpacePool public yieldSpacePool;
    uint256 public constant EXCHANGE_RATE = 0.95e18;

    constructor() {}

    function setYieldSpace(address _yieldSapcePool) external {
        yieldSpacePool = MockSpacePool(_yieldSapcePool);
    }

    function swap(
        BalancerVault.SingleSwap memory singleSwap,
        BalancerVault.FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256) {
        Token(address(singleSwap.assetIn)).transferFrom(msg.sender, address(this), singleSwap.amount);
        uint256 amountOut;
        if (address(singleSwap.assetIn) == yieldSpacePool.zero()) {
            amountOut = (singleSwap.amount).fmul(EXCHANGE_RATE, 10**Token(address(singleSwap.assetIn)).decimals());
        } else {
            amountOut = (singleSwap.amount).fdiv(EXCHANGE_RATE, 10**Token(address(singleSwap.assetIn)).decimals());
        }
        Token(address(singleSwap.assetOut)).transfer(msg.sender, amountOut);
        return amountOut;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        BalancerVault.JoinPoolRequest memory request
    ) external payable {
        IAsset[] memory assets = request.assets;
        uint256[] memory maxAmountsIn = request.maxAmountsIn;
        MockToken(address(assets[0])).transferFrom(sender, address(this), maxAmountsIn[0]);
        MockToken(address(assets[1])).transferFrom(sender, address(this), maxAmountsIn[1]);
        uint256 amountOut = 100e18; // pool tokens
        MockToken(yieldSpacePool).mint(recipient, amountOut);
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        BalancerVault.ExitPoolRequest memory request
    ) external payable {
        IAsset[] memory assets = request.assets;
        uint256[] memory minAmountsOut = request.minAmountsOut;
        (uint8 mode, uint256 lpBal) = abi.decode(request.userData, (uint8, uint256));
        MockToken(yieldSpacePool).burn(recipient, lpBal);
        MockToken(address(assets[0])).transfer(recipient, minAmountsOut[0]);
        MockToken(address(assets[1])).transfer(recipient, minAmountsOut[1]);
    }

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            ERC20[] memory tokens,
            uint256[] memory balances,
            uint256 maxBlockNumber
        )
    {
        tokens = new ERC20[](2);
        tokens[0] = ERC20(yieldSpacePool.underlying());
        tokens[1] = ERC20(yieldSpacePool.zero());

        balances = new uint256[](2);
        balances[0] = ERC20(yieldSpacePool.underlying()).balanceOf(address(this));
        balances[1] = ERC20(yieldSpacePool.zero()).balanceOf(address(this));
    }

    function getPool(bytes32 poolId) external view returns (address, BalancerVault.PoolSpecialization) {
        return (address(yieldSpacePool), BalancerVault.PoolSpecialization.GENERAL);
    }
}

contract MockSpaceFactory {
    MockBalancerVault public vault;
    MockSpacePool public pool;
    Divider public divider;

    mapping(address => mapping(uint256 => address)) public pools;

    constructor(address _vault, address _divider) {
        vault = MockBalancerVault(_vault);
        divider = Divider(_divider);
    }

    function create(
        address _adapter,
        uint48 _maturity
    ) external returns (address) {
        (address _zero, , , , , , , , ) = Divider(divider).series(_adapter, uint48(_maturity));
        address _underlying = Adapter(_adapter).underlying();

        pool = new MockSpacePool(address(vault), _underlying, _zero);
        pools[_adapter][_maturity] = address(pool);

        vault.setYieldSpace(address(pool));

        return address(pool);
    }
}
