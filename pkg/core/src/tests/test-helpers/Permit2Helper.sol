// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

// Permit2
import { IPermit2 } from "@sense-finance/v1-core/external/IPermit2.sol";
import { Periphery } from "@sense-finance/v1-core/Periphery.sol";
import { Permit2Clone } from "./Permit2Clone.sol";

contract Permit2Helper is Test {
    uint256 private _nonce;
    bytes32 constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 constant PERMIT_TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    bytes32 public constant PERMIT_BATCH_TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitBatchTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    IPermit2 internal permit2;

    constructor() {
        _nonce = uint256(
            keccak256(
                abi.encode(tx.origin, tx.origin.balance, block.number, block.timestamp, block.coinbase, gasleft())
            )
        );
        permit2 = new Permit2Clone();
    }

    function setPermit2(address _permit2) public {
        permit2 = IPermit2(_permit2);
    }

    function generatePermit(
        uint256 ownerPrivKey,
        address spender,
        address token,
        uint256 deadline
    ) public returns (Periphery.PermitData memory permit) {
        return _generatePermit(ownerPrivKey, spender, token, deadline);
    }

    function generatePermit(
        uint256 ownerPrivKey,
        address spender,
        address token
    ) public returns (Periphery.PermitData memory permit) {
        return _generatePermit(ownerPrivKey, spender, token, block.timestamp);
    }

    function _generatePermit(
        uint256 ownerPrivKey,
        address spender,
        address token,
        uint256 deadline
    ) internal returns (Periphery.PermitData memory permit) {
        IPermit2.PermitTransferFrom memory permit = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({ token: ERC20(token), amount: type(uint256).max }),
            nonce: _randomUint256(),
            deadline: deadline
        });
        bytes memory sig = _signPermit(permit, spender, ownerPrivKey);
        return Periphery.PermitData(permit, sig);
    }

    function generatePermit(
        uint256 ownerPrivKey,
        address spender,
        address[] memory tokens
    ) public returns (Periphery.PermitBatchData memory permit) {
        IPermit2.TokenPermissions[] memory permitted = new IPermit2.TokenPermissions[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            permitted[i] = IPermit2.TokenPermissions({ token: ERC20(tokens[i]), amount: type(uint256).max });
        }

        IPermit2.PermitBatchTransferFrom memory permit = IPermit2.PermitBatchTransferFrom({
            permitted: permitted,
            nonce: _randomUint256(),
            deadline: block.timestamp
        });
        bytes memory sig = _signPermit(permit, spender, ownerPrivKey);
        return Periphery.PermitBatchData(permit, sig);
    }

    function _randomBytes32() internal view returns (bytes32) {
        bytes memory seed = abi.encode(_nonce, block.timestamp, gasleft());
        return keccak256(seed);
    }

    function _randomUint256() internal view returns (uint256) {
        return uint256(_randomBytes32());
    }

    // Generate a signature for a permit message.
    function _signPermit(
        IPermit2.PermitTransferFrom memory permit,
        address spender,
        uint256 signerKey
    ) internal returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _getEIP712Hash(permit, spender));
        return abi.encodePacked(r, s, v);
    }

    // Generate a signature for a batched permit message.
    function _signPermit(
        IPermit2.PermitBatchTransferFrom memory permit,
        address spender,
        uint256 signerKey
    ) internal returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _getEIP712Hash(permit, spender));
        return abi.encodePacked(r, s, v);
    }

    // Compute the EIP712 hash of the permit object.
    // Normally this would be implemented off-chain.
    function _getEIP712Hash(IPermit2.PermitTransferFrom memory permit, address spender)
        internal
        view
        returns (bytes32 h)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    Permit2Clone(address(permit2)).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TRANSFER_FROM_TYPEHASH,
                            keccak256(
                                abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted.token, permit.permitted.amount)
                            ),
                            spender,
                            permit.nonce,
                            permit.deadline
                        )
                    )
                )
            );
    }

    // Compute the EIP712 hash of the permit object.
    // Normally this would be implemented off-chain.
    function _getEIP712Hash(IPermit2.PermitBatchTransferFrom memory permit, address spender)
        internal
        view
        returns (bytes32 h)
    {
        bytes32[] memory tokenPermissions = new bytes32[](permit.permitted.length);
        for (uint256 i = 0; i < permit.permitted.length; ++i) {
            tokenPermissions[i] = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted[i]));
        }
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    Permit2Clone(address(permit2)).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_BATCH_TRANSFER_FROM_TYPEHASH,
                            keccak256(abi.encodePacked(tokenPermissions)),
                            spender,
                            permit.nonce,
                            permit.deadline
                        )
                    )
                )
            );
    }
}
