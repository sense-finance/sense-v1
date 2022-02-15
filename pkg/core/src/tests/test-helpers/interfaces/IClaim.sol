// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

abstract contract IClaim {
    function collect() external virtual returns (uint256 _collected);
}
