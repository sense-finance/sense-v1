// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { PriceOracle, CTokenLike } from "../external/fuse/PriceOracle.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Token } from "../tokens/Token.sol";
import { BaseAdapter as Adapter } from "../adapters/BaseAdapter.sol";

contract TargetOracle is PriceOracle, Trust {
    using FixedMath for uint256;
    /// @notice target address -> feed address
    mapping(address => address) public adapters;

    constructor() Trust(msg.sender) { }

    function addTarget(address target, address adapter) external requiresTrust {
        adapters[target] = adapter;
    }

    function getUnderlyingPrice(CTokenLike cToken) external view override returns (uint256) {
            // For the sense Fuse pool, the underlying will be the Target. The semantics here can be a little 
            // confusing as we now have two layers of underlying, cToken -> Target -> Target's underlying
            Token target = Token(cToken.underlying());
            
            Adapter adapter = Adapter(adapters[address(target)]);
            require(adapter != Adapter(address(0)), "Target must have a adapter set");
            
            // Target / Target's underlying * price of Target's underlying = Price of Target
            // adapter.scale().fmul(adapter.priceOfUnderlying(), target.decimals())
            return 0;
    }
}

