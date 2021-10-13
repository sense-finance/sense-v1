// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

// Internal references
import { Errors } from "../libs/errors.sol";
import { BaseFeed } from "./BaseFeed.sol";
import { Divider } from "../Divider.sol";
import { wTarget } from "../wrappers/wTarget.sol";

abstract contract BaseFactory is Trust {
    using Clones for address;

    uint256 MAX_INT = 2**256 - 1;

    mapping(address => address) public feeds; // target -> feed (to check if a feed for a given target is deployed)
    address public protocol; // protocol's data contract address
    address public implementation;
    address public divider;
    uint256 public delta;
    address public airdropToken;

    constructor(
        address _protocol,
        address _implementation,
        address _divider,
        uint256 _delta,
        address _airdropToken
    ) Trust(msg.sender) {
        protocol = _protocol;
        implementation = _implementation;
        divider = _divider;
        delta = _delta;
        airdropToken = _airdropToken;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Deploys a feed for the given _target
    /// @param _target Address of the target token
    function deployFeed(address _target) external returns (address clone, address wtarget) {
        require(_exists(_target), Errors.NotSupported);
        require(feeds[_target] == address(0), Errors.FeedAlreadyExists);

        clone = implementation.clone();
        BaseFeed(clone).initialize(_target, divider, delta);
        Divider(divider).setFeed(clone, true);
        wTarget wt = new wTarget(_target, divider, airdropToken); // deploy Target Wrapper
        Divider(divider).setWrapper(address(wt));
        feeds[_target] = clone;
        emit FeedDeployed(clone);
        return (clone, address(wt));
    }

    /* ========== ADMIN FUNCTIONS ========== */

    function setDivider(address _divider) external requiresTrust {
        divider = _divider;
        emit DividerChanged(_divider);
    }

    function setDelta(uint256 _delta) external requiresTrust {
        delta = _delta;
        emit DeltaChanged(_delta);
    }

    function setImplementation(address _implementation) external requiresTrust {
        implementation = _implementation;
        emit ImplementationChanged(_implementation);
    }

    function setProtocol(address _protocol) external requiresTrust {
        protocol = _protocol;
        emit ProtocolChanged(_protocol);
    }

    /* ========== INTERNAL & HELPER FUNCTIONS ========== */

    /// @notice Target validity check that must be overriden by child contracts
    function _exists(address _target) internal virtual returns (bool);

    /* ========== EVENTS ========== */

    event FeedDeployed(address addr);
    event DividerChanged(address divider);
    event DeltaChanged(uint256 delta);
    event ImplementationChanged(address implementation);
    event ProtocolChanged(address protocol);
}