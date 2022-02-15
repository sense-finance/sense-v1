// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

abstract contract IController {
    function supportTarget(address _target, bool _support) external virtual;
}
