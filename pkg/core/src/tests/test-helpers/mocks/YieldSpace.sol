// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Token } from "../../../tokens/Token.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { BalancerVault } from "../../../external/balancer/Vault.sol";

// Internal references
import { Divider } from "../../../Divider.sol";
import { BaseAdapter as Adapter } from "../../../adapters/BaseAdapter.sol";

contract MockYieldSpacePool {
    using FixedMath for uint256;
    MockBalancerVault public vault;

    constructor(address _vault) {
        vault = MockBalancerVault(_vault);
    }

    function getPoolId() external view returns (bytes32) {
        return bytes32(0);
    }

    function getVault() external view returns (address) {
        return address(vault);
    }

    function totalSupply() external view returns (uint256) {
        return 1e18;
    }
}

contract MockBalancerVault {
    using FixedMath for uint256;
    MockYieldSpacePool public yieldSpacePool;
    uint256 public constant EXCHANGE_RATE = 0.95e18;

    constructor() {}

    function setYieldSpace(address _yieldSapcePool) external {
        yieldSpacePool = MockYieldSpacePool(_yieldSapcePool);
    }

    function swap(
        BalancerVault.SingleSwap memory singleSwap,
        BalancerVault.FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256) {
        Token(address(singleSwap.assetIn)).transferFrom(msg.sender, address(this), singleSwap.amount);
        uint256 amountOut = (singleSwap.amount).fmul(EXCHANGE_RATE, 10**Token(address(singleSwap.assetIn)).decimals());
        Token(address(singleSwap.assetOut)).transfer(msg.sender, amountOut);
        return amountOut;
    }
}

contract MockYieldSpaceFactory {
    MockBalancerVault public vault;
    MockYieldSpacePool public pool;

    constructor(address _vault) {
        vault = MockBalancerVault(_vault);
    }

    function create(
        address _divider,
        address _adapter,
        uint256 _maturity
    ) external returns (address) {
        (address _zero, , , , , , , , ) = Divider(_divider).series(_adapter, uint48(_maturity));
        address _target = Adapter(_adapter).getTarget();

        pool = new MockYieldSpacePool(address(vault));

        vault.setYieldSpace(address(pool));

        return address(pool);
    }
}
