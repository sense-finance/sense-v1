// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

// Internal references
import { Errors } from "../libs/Errors.sol";
import { BaseFeed } from "./BaseFeed.sol";
import { Divider } from "../Divider.sol";

abstract contract BaseFactory is Trust {
    address public immutable divider;
    address public immutable protocol; // protocol's data contract address
    address public immutable feedImpl; // feed implementation
    address public immutable stake;
    uint256 public immutable stakeSize;
    uint256 public immutable issuanceFee;
    uint256 public immutable minMaturity;
    uint256 public immutable maxMaturity;
    uint256 public delta;

    event FeedDeployed(address addr);
    event DeltaChanged(uint256 delta);
    event FeedImplementationChanged(address implementation);
    event ProtocolChanged(address protocol);

    constructor(
        address _divider,
        address _protocol,
        address _feedImpl,
        address _stake,
        uint256 _stakeSize,
        uint256 _issuanceFee,
        uint256 _minMaturity,
        uint256 _maxMaturity,
        uint256 _delta
    ) Trust(msg.sender) {
        divider  = _divider;
        protocol = _protocol;
        feedImpl = _feedImpl;
        stake  = _stake;
        stakeSize   = _stakeSize;
        issuanceFee = _issuanceFee;
        minMaturity = _minMaturity;
        maxMaturity = _maxMaturity;
        delta  = _delta;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Deploys both a feed and a target wrapper for the given _target
    /// @param _target Address of the Target token
    function deployFeed(address _target) external virtual returns (address feedClone) {
        require(_exists(_target), Errors.NotSupported);

        // clone the feed using the Target address as salt
        // note: duplicate Target addresses will revert
        feedClone = Clones.cloneDeterministic(feedImpl, Bytes32AddressLib.fillLast12Bytes(_target));

        // TODO: see if we can inline this 
        BaseFeed.FeedParams memory feedParams = BaseFeed.FeedParams({
            target: _target,
            delta: delta,
            ifee: issuanceFee,
            stake: stake,
            stakeSize: stakeSize,
            minm: minMaturity,
            maxm: maxMaturity
        });
        BaseFeed(feedClone).initialize(divider, feedParams);

        // authd set feed since this feed factory is only for Sense-vetted feeds
        Divider(divider).setFeed(feedClone, true);

        emit FeedDeployed(feedClone);

        return feedClone;
    }

    /* ========== ADMIN ========== */

    function setDelta(uint256 _delta) external requiresTrust {
        delta = _delta;
        emit DeltaChanged(_delta);
    }

    /* ========== INTERNAL ========== */

    /// @notice Target validity check that must be overriden by child contracts
    function _exists(address _target) internal virtual returns (bool);
}
