// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// External references
import { Vault, IVault, IWETH, IAuthorizer, IAsset } from "@balancer-labs/v2-vault/contracts/Vault.sol";
import { Authorizer } from "@balancer-labs/v2-vault/contracts/Authorizer.sol";
import { ERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ERC20.sol";

// Internal references
import { DividerLike } from "../../SpaceFactory.sol";

contract ERC20Mintable is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public ERC20(name, symbol) {
        _setupDecimals(decimals);
    }

    function mint(address user, uint256 amount) public virtual {
        _mint(user, amount);
    }
}

// named Space to avoid name collision
contract MockAdapterSpace {
    uint256 internal _scale;
    address public target;
    uint256 public start;
    string public symbol = "ADP";
    string public name = "Adapter";

    constructor(uint8 targetDecimals) public {
        ERC20Mintable _target = new ERC20Mintable("underlying", "underlying", targetDecimals);
        target = address(_target);
        start = block.timestamp;
    }

    function scale() external returns (uint256) {
        if (_scale != 0) return _scale;
        // grow by 0.01 every second after initialization
        return 1e18 + (block.timestamp - start) * 1e12;
    }

    function setScale(uint256 scale_) external returns (uint256) {
        _scale = scale_;
    }
}

// named Space to avoid name collision
contract MockDividerSpace is DividerLike {
    address public zeroAddress;
    address public claimAddress;

    constructor(uint8 zeroClaimDecimals) public {
        ERC20Mintable _zero = new ERC20Mintable("zero", "zero", zeroClaimDecimals);
        ERC20Mintable _claim = new ERC20Mintable("claim", "claim", zeroClaimDecimals);

        zeroAddress = address(_zero);
        claimAddress = address(_claim);
    }

    function series(
        address, // adapter
        uint256 // maturity
    )
        external
        override
        returns (
            address,
            address,
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint128,
            uint128
        )
    {
        return (
            zeroAddress,
            claimAddress,
            address(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint128(0),
            uint128(0)
        );
    }

    function zero(address, uint256) external override returns (address) {
        return zeroAddress;
    }

    function claim(address, uint256) external override returns (address) {
        return claimAddress;
    }
}
