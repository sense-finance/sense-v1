// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { PriceOracle, CTokenLike } from "../../external/fuse/PriceOracle.sol";
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { Token } from "../../tokens/Token.sol";
import { BaseAdapter as Adapter } from "../../adapters/BaseAdapter.sol";

contract TargetOracle is PriceOracle, Trust {
    using FixedMath for uint256;
    /// @notice target address -> feed address
    mapping(address => address) public adapters;

    constructor() Trust(msg.sender) { }

    function setTarget(address target, address adapter) external requiresTrust {
        adapters[target] = adapter;
    }

    function getUnderlyingPrice(CTokenLike cToken) external view override returns (uint256) {
        // For the sense Fuse pool, the underlying will be the Target. The semantics here can be a little confusing
        // as we now have two layers of underlying, cToken -> Target (cToken's underlying) -> Target's underlying
        Token target = Token(cToken.underlying());
        return _price(address(target));
    }

    function price(address target) external view override returns (uint256) {
        return _price(target);
    }

    function _price(address target) internal view returns (uint256) {
        Adapter adapter = Adapter(adapters[address(target)]);
        require(adapter != Adapter(address(0)), "Target must have a adapter set");

        // Use the cached scale for view function compatibility 
        // (this updates with every call to scale elsehwere, is that ok?)
        (, uint256 scale) = adapter._lscale();

        // `Target/Target's underlying` * `Target's underlying/ ETH` = `Price of Target in ETH`
        // scale and the value returned by getUnderlyingPrice are expected to be in WAD form
        return scale.fmul(adapter.getUnderlyingPrice(), FixedMath.WAD);
    }
}
