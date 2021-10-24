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
import { BaseTWrapper as TWrapper } from "../wrappers/BaseTWrapper.sol";

abstract contract BaseFactory is Trust {
    using Clones for address;

    mapping(address => address) public feeds; // target -> feed (to check if a feed for a given target is deployed)
    address public protocol; // protocol's data contract address
    address public feedImpl; // feed implementation
    address public twImpl; // wrapped target implementation
    address public divider;
    uint256 public delta;
    address public reward; // reward token

    constructor(
        address _protocol,
        address _feedImpl,
        address _twImpl,
        address _divider,
        uint256 _delta,
        address _reward
    ) Trust(msg.sender) {
        protocol = _protocol;
        feedImpl = _feedImpl;
        twImpl   = _twImpl;
        divider  = _divider;
        delta    = _delta;
        reward   = _reward;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Deploys both a feed and a target wrapper for the given _target
    /// @param _target Address of the target token
    function deployFeed(address _target) external returns (address feedClone, address wtClone) {
        require(_exists(_target), Errors.NotSupported);
        require(feeds[_target] == address(0), Errors.FeedAlreadyExists);

        // wrapped target deployment
        wtClone = twImpl.clone();
        TWrapper(wtClone).initialize(_target, divider, reward); // deploy Target Wrapper

        // feed deployment
        feedClone = feedImpl.clone();
        BaseFeed(feedClone).initialize(_target, divider, delta, wtClone);
        Divider(divider).setFeed(feedClone, true);
        feeds[_target] = feedClone;
        emit FeedDeployed(feedClone);

        return (feedClone, wtClone);
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

    function setFeedImplementation(address _feedImpl) external requiresTrust {
        feedImpl = _feedImpl;
        emit FeedImplementationChanged(_feedImpl);
    }

    function setTWImplementation(address _twImpl) external requiresTrust {
        twImpl = _twImpl;
        emit TWrapperImplementationChanged(_twImpl);
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
    event FeedImplementationChanged(address implementation);
    event TWrapperImplementationChanged(address implementation);
    event ProtocolChanged(address protocol);
}
