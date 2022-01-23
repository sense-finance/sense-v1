// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { PriceOracle, CTokenLike } from "../external/PriceOracle.sol";
import { BalancerOracle } from "../external/BalancerOracle.sol";
import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import { BalancerVault } from "@sense-finance/v1-core/src/external/balancer/Vault.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

// Internal references
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { BaseAdapter as Adapter } from "@sense-finance/v1-core/src/adapters/BaseAdapter.sol";

contract ZeroOracle is PriceOracle, Trust {
    using FixedPointMathLib for uint256;
    /// @notice zero address -> pool address for oracle reads
    mapping(address => address) public pools;
    uint32 public constant TWAP_PERIOD = 1 hours;

    constructor() Trust(msg.sender) { }

    function setZero(address zero, address pool) external requiresTrust {
        pools[zero] = pool;
    }

    function getUnderlyingPrice(CTokenLike cToken) external view override returns (uint256) {
        // The underlying here will be a Zero
        address zero = cToken.underlying();
        return _price(zero);
    }

    function price(address zero) external view override returns (uint256) {
        return _price(zero);
    }

    function _price(address zero) internal view returns (uint256) {
        BalancerOracle pool = BalancerOracle(pools[address(zero)]);
        if (pool == BalancerOracle(address(0))) revert Errors.PoolNotSet();

        // if getSample(1023) returns 0s, the oracle buffer is not full yet and a price can't be read
        // https://dev.balancer.fi/references/contracts/apis/pools/weightedpool2tokens#api
        (, , , , , , uint256 sampleTs) = pool.getSample(1023);
        if (sampleTs == 0) {
            // revert if the pool's oracle can't be used yet, preventing this market from being deployed
            // on Fuse until we're able to read a TWAP
            revert Errors.OracleNotReady();
        }

        BalancerOracle.OracleAverageQuery[] memory queries = new BalancerOracle.OracleAverageQuery[](1);
        queries[0] = BalancerOracle.OracleAverageQuery({
            variable: BalancerOracle.Variable.PAIR_PRICE,
            secs: TWAP_PERIOD,
            ago: 0
        });

        uint256[] memory results = pool.getTimeWeightedAverage(queries);
        // get the price of Zeros in terms of underlying
        (uint8 zeroi, uint8 targeti) = pool.getIndices();
        uint256 zeroPrice = results[zeroi];

        (ERC20[] memory tokens, , ) = BalancerVault(pool.getVault()).getPoolTokens(pool.getPoolId());
        address underlying = address(tokens[targeti]);

        // `Zero / underlying` * `underlying / ETH` = `Price of Zero in ETH`
        //
        // Assumes the caller is the maser oracle, which will have its own strategy for getting the underlying price
        return zeroPrice.fmul(PriceOracle(msg.sender).price(underlying), FixedPointMathLib.WAD);
    }
}
