// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { PriceOracle, CTokenLike } from "../external/PriceOracle.sol";
import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import { BalancerVault } from "@sense-finance/v1-core/src/external/balancer/Vault.sol";

// Internal references
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { BaseAdapter as Adapter } from "@sense-finance/v1-core/src/adapters/BaseAdapter.sol";

interface BalancerOracleLike {
    function getTimeWeightedAverage(OracleAverageQuery[] memory queries)
        external
        view
        returns (uint256[] memory results);

    enum Variable {
        PAIR_PRICE,
        BPT_PRICE,
        INVARIANT
    }
    struct OracleAverageQuery {
        Variable variable;
        uint256 secs;
        uint256 ago;
    }

    function getSample(uint256 index)
        external
        view
        returns (
            int256 logPairPrice,
            int256 accLogPairPrice,
            int256 logBptPrice,
            int256 accLogBptPrice,
            int256 logInvariant,
            int256 accLogInvariant,
            uint256 timestamp
        );

    function getPoolId() external view returns (bytes32);

    function getVault() external view returns (address);

    function getIndices() external view returns (uint8 _zeroi, uint8 _targeti);
}

contract ZeroOracle is PriceOracle, Trust {
    using FixedPointMathLib for uint256;
    /// @notice zero address -> pool address for oracle reads
    mapping(address => address) public pools;
    uint32 public constant TWAP_PERIOD = 1 hours;

    constructor() Trust(msg.sender) {}

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
        BalancerOracleLike pool = BalancerOracleLike(pools[address(zero)]);
        require(pool != BalancerOracleLike(address(0)), "Zero must have a pool set");

        // if getSample(1023) returns 0s, the oracle buffer is not full yet and a price can't be read
        // https://dev.balancer.fi/references/contracts/apis/pools/weightedpool2tokens#api
        (, , , , , , uint256 sampleTs) = pool.getSample(1023);
        if (sampleTs == 0) {
            // revert if the pool's oracle can't be used yet, preventing this market from being deployed
            // on Fuse until we're able to read a TWAP
            revert("Zero pool oracle not yet ready");
        }

        BalancerOracleLike.OracleAverageQuery[] memory queries = new BalancerOracleLike.OracleAverageQuery[](1);
        queries[0] = BalancerOracleLike.OracleAverageQuery({
            variable: BalancerOracleLike.Variable.PAIR_PRICE,
            secs: TWAP_PERIOD,
            ago: 0
        });

        uint256[] memory results = pool.getTimeWeightedAverage(queries);
        // get the price of Zeros in terms of underlying
        (uint8 zeroi, ) = pool.getIndices();
        uint256 zeroPrice = results[zeroi];

        (ERC20[] memory tokens, , ) = BalancerVault(pool.getVault()).getPoolTokens(pool.getPoolId());
        address underlying;
        if (address(zero) == address(tokens[0])) {
            underlying = address(tokens[1]);
        } else {
            underlying = address(tokens[0]);
        }

        // `Zero/underlying` * `underlying/ETH` = `Price of Zero in ETH`
        // assumes the caller is the maser oracle, which will have its own way to get the underlying price
        return zeroPrice.fmul(PriceOracle(msg.sender).price(underlying), FixedPointMathLib.WAD);
    }
}
