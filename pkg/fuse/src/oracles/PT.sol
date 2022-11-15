// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { PriceOracle } from "../external/PriceOracle.sol";
import { CToken } from "../external/CToken.sol";
import { BalancerOracle } from "../external/BalancerOracle.sol";
import { BalancerVault } from "@sense-finance/v1-core/external/balancer/Vault.sol";

// Internal references
import { Trust } from "@sense-finance/v1-utils/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { Token } from "@sense-finance/v1-core/tokens/Token.sol";
import { FixedMath } from "@sense-finance/v1-core/external/FixedMath.sol";
import { BaseAdapter as Adapter } from "@sense-finance/v1-core/adapters/abstract/BaseAdapter.sol";

interface SpaceLike {
    function getImpliedRateFromPrice(uint256 pTPriceInTarget) external view returns (uint256);

    function getPriceFromImpliedRate(uint256 impliedRate) external view returns (uint256);

    function getTotalSamples() external pure returns (uint256);

    function adapter() external view returns (address);
}

contract PTOracle is PriceOracle, Trust {
    using FixedMath for uint256;

    /// @notice PT address -> pool address for oracle reads
    mapping(address => address) public pools;
    /// @notice Minimum implied rate this oracle will tolerate for PTs
    uint256 public floorRate;
    uint256 public twapPeriod;

    constructor() Trust(msg.sender) {
        floorRate = 3e18; // 300%
        twapPeriod = 5.5 hours;
    }

    function setFloorRate(uint256 _floorRate) external requiresTrust {
        floorRate = _floorRate;
    }

    function setTwapPeriod(uint256 _twapPeriod) external requiresTrust {
        twapPeriod = _twapPeriod;
    }

    function setPrincipal(address pt, address pool) external requiresTrust {
        pools[pt] = pool;
    }

    function getUnderlyingPrice(CToken cToken) external view override returns (uint256) {
        // The underlying here will be a Principal Token
        return _price(cToken.underlying());
    }

    function price(address pt) external view override returns (uint256) {
        return _price(pt);
    }

    function _price(address pt) internal view returns (uint256) {
        BalancerOracle pool = BalancerOracle(pools[address(pt)]);
        if (pool == BalancerOracle(address(0))) revert Errors.PoolNotSet();

        // if getSample(buffer_size) returns 0s, the oracle buffer is not full yet and a price can't be read
        // https://dev.balancer.fi/references/contracts/apis/pools/weightedpool2tokens#api
        (, , , , , , uint256 sampleTs) = pool.getSample(SpaceLike(address(pool)).getTotalSamples() - 1);
        // Revert if the pool's oracle can't be used yet, preventing this market from being deployed
        // on Fuse until we're able to read a TWAP
        if (sampleTs == 0) revert Errors.OracleNotReady();

        BalancerOracle.OracleAverageQuery[] memory queries = new BalancerOracle.OracleAverageQuery[](1);
        // The BPT price slot in Space carries the implied rate TWAP
        queries[0] = BalancerOracle.OracleAverageQuery({
            variable: BalancerOracle.Variable.BPT_PRICE,
            secs: twapPeriod,
            ago: 1 hours // take the oracle from 1 hour ago plus twapPeriod ago to 1 hour ago
        });

        uint256[] memory results = pool.getTimeWeightedAverage(queries);
        // note: impliedRate is pulled from the BPT price slot in BalancerOracle.OracleAverageQuery
        uint256 impliedRate = results[0];

        if (impliedRate > floorRate) {
            impliedRate = floorRate;
        }

        address target = Adapter(SpaceLike(address(pool)).adapter()).target();

        // `Principal Token / target` * `target / ETH` = `Price of Principal Token in ETH`
        //
        // Assumes the caller is the master oracle, which will have its own strategy for getting the underlying price
        return
            SpaceLike(address(pool)).getPriceFromImpliedRate(impliedRate).fmul(PriceOracle(msg.sender).price(target));
    }
}
