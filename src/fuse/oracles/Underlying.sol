// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { PriceOracle, CTokenLike } from "../../external/fuse/PriceOracle.sol";
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { Token } from "../../tokens/Token.sol";
import { BaseAdapter as Adapter } from "../../adapters/BaseAdapter.sol";

contract UnderlyingOracle is PriceOracle, Trust {
    using FixedMath for uint256;
    /// @notice underlying address -> adapter address
    mapping(address => address) public adapters;

    constructor() Trust(msg.sender) { }

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
        require(adapter != Adapter(address(0)), "Underlying must have a adapter set");

        return adapter.getUnderlyingPrice();
    }
}
