// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { PriceOracle } from "@sense-finance/v1-fuse/external/PriceOracle.sol";
import { CToken } from "@sense-finance/v1-fuse/external/CToken.sol";

contract MockOracle is PriceOracle {
    uint256 public _price = 1e18;

    function getUnderlyingPrice(CToken) external view override returns (uint256) {
        return _price;
    }

    function price(address) external view override returns (uint256) {
        return _price;
    }

    function setPrice(uint256 price_) external {
        _price = price_;
    }

    function initialize(
        address[] memory,
        PriceOracle[] memory,
        PriceOracle,
        address,
        bool
    ) external {
        return;
    }

    function add(address[] calldata underlyings, PriceOracle[] calldata _oracles) external {
        return;
    }

    function setZero(address zero, address pool) external {
        return;
    }
}
