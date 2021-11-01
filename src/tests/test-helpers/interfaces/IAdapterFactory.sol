// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

abstract contract IAdapterFactory {

    function setDivider(address _divider) virtual public;

    function setDelta(uint256 _delta) virtual public;

    function setImplementation(address _implementation) virtual public;

    function deployAdapter(address _target) public virtual returns (address adapterClone, address wtClone);

}
