// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { Vault } from "../../../external/balancer/Vault.sol";

// Internal references
import { Divider } from "../../../Divider.sol";
import { BaseAdapter as Adapter } from "../../../adapters/BaseAdapter.sol";


contract YieldSpacePool {
    using FixedMath for uint256;

    uint256 public constant EXCHANGE_RATE = 0.95e18;

    constructor(address zero, address target) { }

    function addReserves() external {

    }

    receive() external payable {}
}

contract BalancerVault {
    YieldSpacePool public yieldSpacePool;

    constructor() { }

    function setYieldSpace(address _yieldSapcePool) external {
        yieldSpacePool = _yieldSapcePool;
    }
 
    function joinPool(bytes32 poolId, address sender, address recipient, Vault.JoinPoolRequest memory request) external {

    }
         
    function exitPool(bytes32 poolId, address sender, address payable recipient, Vault.ExitPoolRequest memory request) external {

    }

    function swap(
        Vault.SingleSwap memory singleSwap, Vault.FundManagement memory funds, uint256 limit, uint256 deadline
    ) external payable returns (uint256) {

    }
}

contract YieldSpaceFactory {
    BalancerVault public vault;

    constructor(BalancerVault _vault) {
        vault = _vault;
    }

    function create(
        address _divider,
        address _adapter,
        address _maturity
    ) external returns (address) {
        (address _zero, , , , , , , , ) = Divider(_divider).series(_adapter, _maturity);
        address _target = Adapter(_adapter).getTarget();

        YieldSpacePool pool = new YieldSpacePool(_zero, _target);
        vault.setYieldSpace(pool);

        return address(pool);
    }
}
