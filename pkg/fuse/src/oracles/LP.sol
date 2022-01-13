// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { PriceOracle, CTokenLike } from "../external/PriceOracle.sol";
import { BalancerOracle } from "../external/BalancerOracle.sol";
import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import { BalancerVault } from "@sense-finance/v1-core/src/external/balancer/Vault.sol";

// Internal references
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { BaseAdapter as Adapter } from "@sense-finance/v1-core/src/adapters/BaseAdapter.sol";

contract LPOracle is PriceOracle, Trust {
    using FixedPointMathLib for uint256;

    /// @notice zero address -> pool address for oracle reads
    mapping(address => address) public pools;
    uint32 public constant TWAP_PERIOD = 1 hours;

    constructor() Trust(msg.sender) {}

    function getUnderlyingPrice(CTokenLike cToken) external view override returns (uint256) {
        // The underlying here will be an LP Token
        address pool = cToken.underlying();
        return _price(pool);
    }

    function price(address zero) external view override returns (uint256) {
        return _price(zero);
    }

    function _price(address _pool) internal view returns (uint256) {
        BalancerOracle pool = BalancerOracle(_pool);

        (ERC20[] memory tokens, uint256[] memory balances, ) = BalancerVault(pool.getVault()).getPoolTokens(
            pool.getPoolId()
        );

        uint256 balanceA = balances[0];
        address tokenA = address(tokens[0]);

        uint256 balanceB = balances[1];
        address tokenB = address(tokens[1]);

        uint256 totalSupply = pool.totalSupply();

        // pool value = price of tokenA * amount of tokenA held + price of tokenB * amount of tokenB held
        uint256 value = PriceOracle(msg.sender).price(tokenA).fmul(balanceA, FixedPointMathLib.WAD) +
            PriceOracle(msg.sender).price(tokenB).fmul(balanceB, FixedPointMathLib.WAD);

        // price per lp token = pool value / total supply of lp tokens
        return value.fdiv(totalSupply, FixedPointMathLib.WAD);
    }
}
