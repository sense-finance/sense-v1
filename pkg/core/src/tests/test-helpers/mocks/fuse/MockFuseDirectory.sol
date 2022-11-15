// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";

contract MockFuseDirectory {
    address public comptroller;

    constructor(address _comptroller) {
        comptroller = _comptroller;
    }

    function deployPool(
        string memory name,
        address implementation,
        bool enforceWhitelist,
        uint256 closeFactor,
        uint256 liquidationIncentive,
        address priceOracle
    ) external returns (uint256, address) {
        return (0, comptroller);
    }
}
