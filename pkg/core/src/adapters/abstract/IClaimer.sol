// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

interface IClaimer {
    /// @dev Claims rewards on protocol.
    function claim() external;
}
