// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { Authorizer } from "@balancer-labs/v2-vault/contracts/Authorizer.sol";
import { Vault } from "@balancer-labs/v2-vault/contracts/Vault.sol";
import { Space } from "../lib/v1-space/src/Space.sol";
import { SpaceFactory } from "../lib/v1-space/src/SpaceFactory.sol";