// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { BalancerVault } from "../../../external/balancer/Vault.sol";

// Internal references
import { Divider } from "../../../Divider.sol";
import { BaseAdapter as Adapter } from "../../../adapters/BaseAdapter.sol";


contract MockYieldSpacePool {
    using FixedMath for uint256;

    uint256 public constant EXCHANGE_RATE = 0.95e18;

    constructor(address zero, address target) { }

    function addReserves() external {

    }
}

contract MockBalancerVault {
    MockYieldSpacePool public yieldSpacePool;

    constructor() { }

    function setYieldSpace(address _yieldSapcePool) external {
        yieldSpacePool = MockYieldSpacePool(_yieldSapcePool);
    }
 
    function joinPool(bytes32 poolId, address sender, address recipient, BalancerVault.JoinPoolRequest memory request) external {

    }
         
    function exitPool(bytes32 poolId, address sender, address payable recipient, BalancerVault.ExitPoolRequest memory request) external {

    }

    function swap(
        BalancerVault.SingleSwap memory singleSwap, BalancerVault.FundManagement memory funds, uint256 limit, uint256 deadline
    ) external payable returns (uint256) {

    }
}

contract MockYieldSpaceFactory {
    MockBalancerVault public vault;

    constructor(address _vault) {
        vault = MockBalancerVault(_vault);
    }

    function create(
        address _divider,
        address _adapter,
        uint256 _maturity
    ) external returns (address) {
        (address _zero, , , , , , , , ) = Divider(_divider).series(_adapter, _maturity);
        address _target = Adapter(_adapter).getTarget();

        MockYieldSpacePool pool = new MockYieldSpacePool(_zero, _target);
        vault.setYieldSpace(address(pool));

        return address(pool);
    }
}
