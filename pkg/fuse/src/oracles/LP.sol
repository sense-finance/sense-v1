// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { PriceOracle } from "../external/PriceOracle.sol";
import { CToken } from "../external/CToken.sol";
import { BalancerVault } from "@sense-finance/v1-core/src/external/balancer/Vault.sol";
import { BalancerPool } from "@sense-finance/v1-core/src/external/balancer/Pool.sol";
import { BalancerOracle } from "../external/BalancerOracle.sol";

// Internal references
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { FixedMath } from "@sense-finance/v1-core/src/external/FixedMath.sol";

contract LPOracle is PriceOracle, Trust {
    using FixedMath for uint256;

    /// @notice zero address -> pool address for oracle reads
    mapping(address => address) public pools;
    uint32 public constant TWAP_PERIOD = 6 hours;

    constructor() Trust(msg.sender) {}

    function getUnderlyingPrice(CToken cToken) external view override returns (uint256) {
        // The underlying here will be an LP Token
        return _price(cToken.underlying());
    }

    function price(address zero) external view override returns (uint256) {
        return _price(zero);
    }

    function _price(address _pool) internal view returns (uint256) {
        BalancerPool pool = BalancerOracle(_pool);
        if (pool == BalancerOracle(address(0))) revert Errors.PoolNotSet();

        // if getSample(1023) returns 0s, the oracle buffer is not full yet and a price can't be read
        // https://dev.balancer.fi/references/contracts/apis/pools/weightedpool2tokens#api
        (, , , , , , uint256 sampleTs) = pool.getSample(1023);
        // Revert if the pool's oracle can't be used yet, preventing this market from being deployed
        // on Fuse until we're able to read a TWAP
        if (sampleTs == 0) revert Errors.OracleNotReady();

        BalancerOracle.OracleAverageQuery[] memory queries = new BalancerOracle.OracleAverageQuery[](1);
        queries[0] = BalancerOracle.OracleAverageQuery({
            variable: BalancerOracle.Variable.BPT_PRICE,
            secs: TWAP_PERIOD,
            ago: 120 // take the oracle from 2 mins ago - TWAP_PERIOD to 2 mins ago
        });

        uint256[] memory results = pool.getTimeWeightedAverage(queries);
        (ERC20[] memory tokens, , ) = BalancerVault(pool.getVault()).getPoolTokens(pool.getPoolId());

        // The BPT price is in terms of token 0, which we should have an oracle price for, regardless of which it is
        return PriceOracle(msg.sender).price(tokens[0]).fmul(results[0]);
    }
}
