// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { PriceOracle, CTokenLike } from "../external/PriceOracle.sol";
import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

// Internal references
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { BaseAdapter as Adapter } from "@sense-finance/v1-core/src/adapters/BaseAdapter.sol";

contract UnderlyingOracle is PriceOracle, Trust {
    using FixedPointMathLib for uint256;
    /// @notice underlying address -> adapter address
    mapping(address => address) public adapters;

    constructor() Trust(msg.sender) {}

    function setUnderlying(address underlying, address adapter) external requiresTrust {
        adapters[underlying] = adapter;
    }

    function getUnderlyingPrice(CTokenLike cToken) external view override returns (uint256) {
        Token underlying = Token(cToken.underlying());
        return _price(address(underlying));
    }

    function price(address underlying) external view override returns (uint256) {
        return _price(underlying);
    }

    function _price(address underlying) internal view returns (uint256) {
        Adapter adapter = Adapter(adapters[address(underlying)]);
        if (adapter == Adapter(address(0))) revert Errors.AdapterNotSet();

        return adapter.getUnderlyingPrice();
    }
}
