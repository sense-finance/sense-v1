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
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BaseAdapter as Adapter } from "@sense-finance/v1-core/src/adapters/BaseAdapter.sol";

interface SpaceLike {
    function getFairBPTPrice(uint256 ptTwapDuration) external view returns (uint256);

    function adapter() external view returns (address);
}

contract LPOracle is PriceOracle, Trust {
    using FixedMath for uint256;

    /// @notice PT address -> pool address for oracle reads
    mapping(address => address) public pools;
    uint256 public twapPeriod;

    constructor() Trust(msg.sender) {
        twapPeriod = 5.5 hours;
    }

    function setTwapPeriod(uint256 _twapPeriod) external requiresTrust {
        twapPeriod = _twapPeriod;
    }

    function getUnderlyingPrice(CToken cToken) external view override returns (uint256) {
        // The underlying here will be an LP Token
        return _price(cToken.underlying());
    }

    function price(address pt) external view override returns (uint256) {
        return _price(pt);
    }

    function _price(address _pool) internal view returns (uint256) {
        SpaceLike pool = SpaceLike(_pool);
        address target = Adapter(pool.adapter()).target();

        // Price per BPT in ETH terms, where the PT side of the pool is valued using the TWAP oracle
        return pool.getFairBPTPrice(twapPeriod).fmul(PriceOracle(msg.sender).price(target));
    }
}
