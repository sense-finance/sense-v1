// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";

/// @title ERC4626WrapperFactory
/// @author Timeless
/// @notice Abstract base contract for deploying ERC4626 wrappers
/// @dev Uses CREATE2 deterministic deployment, so there can only be a single
/// vault for each asset.
abstract contract ERC4626WrapperFactory is Trust {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using Bytes32AddressLib for bytes32;

    /// -----------------------------------------------------------------------
    /// Params
    /// -----------------------------------------------------------------------

    /// @notice Wrapper admin
    address public restrictedAdmin;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address _restrictedAdmin) Trust(msg.sender) {
        restrictedAdmin = _restrictedAdmin;
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Creates an ERC4626 vault for an asset
    /// @dev Uses CREATE2 deterministic deployment, so there can only be a single
    /// vault for each asset. Will revert if a vault has already been deployed for the asset.
    /// @param asset The base asset used by the vault
    /// @return vault The vault that was created
    function createERC4626(ERC20 asset) external virtual returns (ERC4626 vault);

    /// @notice Computes the address of the ERC4626 vault corresponding to an asset. Returns
    /// a valid result regardless of whether the vault has already been deployed.
    /// @param asset The base asset used by the vault
    /// @return vault The vault corresponding to the asset
    function computeERC4626Address(ERC20 asset) external view virtual returns (ERC4626 vault);

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    /// @notice Computes the address of a contract deployed by this factory using CREATE2, given
    /// the bytecode hash of the contract. Can also be used to predict addresses of contracts yet to
    /// be deployed.
    /// @dev Always uses bytes32(0) as the salt
    /// @param bytecodeHash The keccak256 hash of the creation code of the contract being deployed concatenated
    /// with the ABI-encoded constructor arguments.
    /// @return The address of the deployed contract
    function _computeCreate2Address(bytes32 bytecodeHash) internal view virtual returns (address) {
        return keccak256(abi.encodePacked(bytes1(0xFF), address(this), bytes32(0), bytecodeHash)).fromLast20Bytes();
        // Prefix:
        // Creator:
        // Salt:
        // Bytecode hash: // Convert the CREATE2 hash into an address.
    }

    /// -----------------------------------------------------------------------
    /// Admin functions
    /// -----------------------------------------------------------------------
    function setRestrictedAdmin(address _restrictedAdmin) external requiresTrust {
        emit RestrictedAdminChanged(restrictedAdmin, _restrictedAdmin);
        restrictedAdmin = _restrictedAdmin;
    }

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @notice Emitted when a new ERC4626 vault has been created
    /// @param asset The base asset used by the vault
    /// @param vault The vault that was created
    event CreateERC4626(ERC20 indexed asset, ERC4626 vault);
    event RestrictedAdminChanged(address indexed restrictedAdmin, address indexed newRestrictedAdmin);
}
