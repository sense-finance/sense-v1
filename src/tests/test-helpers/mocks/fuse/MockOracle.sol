// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { PriceOracle, CTokenLike } from "../../../../fuse/Oracle.sol";

contract MockOracle is PriceOracle {
    uint256 public price = 1e18;
    
    function getUnderlyingPrice(CTokenLike) external view override returns (uint256) {
        return price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }
}
