// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { PriceOracle } from "../external/PriceOracle.sol";
import { CToken } from "../external/CToken.sol";
import { BalancerVault } from "@sense-finance/v1-core/src/external/balancer/Vault.sol";
import { BalancerPool } from "@sense-finance/v1-core/src/external/balancer/Pool.sol";

// Internal references
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { FixedMath } from "@sense-finance/v1-core/src/external/FixedMath.sol";

contract LPOracle is PriceOracle, Trust {
    using FixedMath for uint256;

    /// @notice zero address -> pool address for oracle reads
    mapping(address => address) public pools;

    constructor() Trust(msg.sender) {}

    function getUnderlyingPrice(CToken cToken) external view override returns (uint256) {
        // The underlying here will be an LP Token
        return _price(cToken.underlying());
    }

    function price(address zero) external view override returns (uint256) {
        return _price(zero);
    }

    function _price(address _pool) internal view returns (uint256) {
        BalancerPool pool = BalancerPool(_pool);

        (ERC20[] memory tokens, uint256[] memory balances, ) = BalancerVault(pool.getVault()).getPoolTokens(
            pool.getPoolId()
        );

        uint256 balanceA = balances[0];
        address tokenA = address(tokens[0]);

        uint256 balanceB = balances[1];
        address tokenB = address(tokens[1]);

        // pool value as a WAD = price of tokenA * amount of tokenA held + price of tokenB * amount of tokenB held
        uint256 value = PriceOracle(msg.sender).price(tokenA).fmul(balanceA, 10**ERC20(tokenA).decimals()) +
            PriceOracle(msg.sender).price(tokenB).fmul(balanceB, 10**ERC20(tokenB).decimals());

        // price per lp token = pool value / total supply of lp tokens
        //
        // As per Balancer's convention, lp shares will also be WADs
        return value.fdiv(pool.totalSupply());
    }
}
