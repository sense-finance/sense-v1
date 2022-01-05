// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { PriceOracle, CTokenLike } from "@sense-finance/v1-fuse/src/external/PriceOracle.sol";

contract MockOracle is PriceOracle {
    uint256 public _price = 1e18;

    function getUnderlyingPrice(CTokenLike) external view override returns (uint256) {
        return _price;
    }

    function price(address) external view override returns (uint256) {
        return _price;
    }

    function setPrice(uint256 price_) external {
        _price = price_;
    }
}
