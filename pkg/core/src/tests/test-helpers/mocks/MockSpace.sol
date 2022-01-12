// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Token } from "../../../tokens/Token.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { BalancerVault, IAsset } from "../../../external/balancer/Vault.sol";
import { BalancerPool } from "../../../external/balancer/Pool.sol";

// Internal references
import { Divider } from "../../../Divider.sol";
import { BaseAdapter as Adapter } from "../../../adapters/BaseAdapter.sol";

import { MockToken } from "./MockToken.sol";

contract MockSpacePool is MockToken {
    using FixedMath for uint256;

    MockBalancerVault public vault;
    address public zero;
    address public target;

    constructor(
        address _vault,
        address _target,
        address _zero
    ) MockToken("Mock Yield Space Pool Token", "MYSPT", 18) {
        vault = MockBalancerVault(_vault);
        zero = _zero;
        target = _target;
    }

    function getPoolId() external view returns (bytes32) {
        return bytes32(0);
    }

    function getVault() external view returns (address) {
        return address(vault);
    }

    function onSwap(
        BalancerPool.SwapRequest memory request,
        uint256, /* _reservesInAmount */
        uint256 /* _reservesOutAmount */
    ) external view returns (uint256) {
        if (address(request.tokenIn) == zero) {
            if (request.kind == BalancerVault.SwapKind.GIVEN_IN) {
                return request.amount.fmul(vault.EXCHANGE_RATE(), 1e18);
            } else {
                return request.amount.fmul(FixedMath.WAD.fdiv(vault.EXCHANGE_RATE(), FixedMath.WAD), 1e18);
            }
        } else {
            if (request.kind == BalancerVault.SwapKind.GIVEN_IN) {
                return request.amount.fmul(FixedMath.WAD.fdiv(vault.EXCHANGE_RATE(), FixedMath.WAD), 1e18);
            } else {
                return request.amount.fmul(vault.EXCHANGE_RATE(), 1e18);
            }
        }
    }

    function getIndices() public view returns (uint8 zeroi, uint8 targeti) {
        // Indices to match MockBalancerVault's balances array
        zeroi = 1;
        targeti = 0;
    }
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
        uint256 amountInOrOut;
        if (address(singleSwap.assetIn) == yieldSpacePool.zero()) {
            if (singleSwap.kind == BalancerVault.SwapKind.GIVEN_IN) {
                amountInOrOut = (singleSwap.amount).fmul(EXCHANGE_RATE, 1e18);
            } else {
                amountInOrOut = (singleSwap.amount).fdiv(EXCHANGE_RATE, 1e18);
            }
        } else {
            if (singleSwap.kind == BalancerVault.SwapKind.GIVEN_IN) {
                amountInOrOut = (singleSwap.amount).fdiv(EXCHANGE_RATE, 1e18);
            } else {
                amountInOrOut = (singleSwap.amount).fmul(EXCHANGE_RATE, 1e18);
            }
        }
        Token(address(singleSwap.assetOut)).transfer(msg.sender, amountInOrOut);
        return amountInOrOut;
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
        uint256 lpBal = abi.decode(request.userData, (uint256));
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
        tokens[0] = ERC20(yieldSpacePool.target());
        tokens[1] = ERC20(yieldSpacePool.zero());

        balances = new uint256[](2);
        balances[0] = ERC20(yieldSpacePool.target()).balanceOf(address(this));
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

    function create(address _adapter, uint256 _maturity) external returns (address) {
        Divider.Series memory series = Divider(divider).series(_adapter, _maturity);
        address _target = Adapter(_adapter).target();

        pool = new MockSpacePool(address(vault), _target, series.zero);
        pools[_adapter][_maturity] = address(pool);

        vault.setYieldSpace(address(pool));

        return address(pool);
    }
}
