// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// external references
import "@openzeppelin/contracts/proxy/Clones.sol";

// internal references
import "./BaseFeed.sol";
//import "../libs/Errors.sol";
import "../controller/Controller.sol";

contract FeedFactory is Warded {
    using Clones for address;

    address public implementation;
    address public divider;
    address public target;
    address public controller;
    uint256 public delta;

    constructor(
        address _implementation,
        address _divider,
        address _controller,
        uint256 _delta
    ) Warded() {
        implementation = _implementation;
        divider = _divider;
        controller = _controller;
        delta = _delta;
    }

    function setDivider(address _divider) external onlyWards {
        divider = _divider;
        emit DividerChanged(_divider);
    }

    function setDelta(uint256 _delta) external onlyWards {
        delta = _delta;
        emit DeltaChanged(_delta);
    }

    function setImplementation(address _implementation) external onlyWards {
        implementation = _implementation;
        emit ImplementationChanged(_implementation);
    }

    function deployFeed(address _target) external returns (address clone) {
        require(Controller(controller).targets(_target), "Target is not supported");
        //        require(Controller(controller).targets(_target), Errors.NotSupported);
        clone = implementation.clone();
        BaseFeed(clone).initialize(_target, divider, delta);
        Divider(divider).setFeed(clone, true);
        emit FeedDeployed(clone);
    }

    event FeedDeployed(address addr);
    event DividerChanged(address divider);
    event DeltaChanged(uint256 delta);
    event ImplementationChanged(address implementation);
}
