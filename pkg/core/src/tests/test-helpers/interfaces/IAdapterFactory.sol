// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

abstract contract IAdapterFactory {
    function setDivider(address _divider) public virtual;

    function setDelta(uint256 _delta) public virtual;

    function setImplementation(address _implementation) public virtual;

    function deployAdapter(address _target) public virtual returns (address adapterClone, address wtClone);
}
