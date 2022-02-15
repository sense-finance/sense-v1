// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

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

    function initialize(
        address[] memory underlyings,
        PriceOracle[] memory _oracles,
        PriceOracle _defaultOracle,
        address _admin,
        bool _canAdminOverwrite
    ) external {
        return;
    }

    function add(address[] calldata underlyings, PriceOracle[] calldata _oracles) external {
        return;
    }
}
