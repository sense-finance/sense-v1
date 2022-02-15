// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

abstract contract IAdapterFactory {
    function setDivider(address _divider) public virtual;

    function setImplementation(address _implementation) public virtual;

    function deployAdapter(address _target) public virtual returns (address adapterClone, address wtClone);
}
