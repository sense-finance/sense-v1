// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@sense-finance/v1-core/src/Divider.sol";
import "@sense-finance/v1-core/src/Periphery.sol";
import "@sense-finance/v1-core/src/adapters/abstract/BaseAdapter.sol";
import "@sense-finance/v1-core/src/adapters/implementations/compound/CFactory.sol";
import "@sense-finance/v1-core/src/adapters/implementations/fuse/FFactory.sol";
import "@sense-finance/v1-core/src/adapters/implementations/lido/WstETHAdapter.sol";
import "@sense-finance/v1-core/src/adapters/implementations/lido/OwnableWstETHAdapter.sol";
import "@sense-finance/v1-core/src/adapters/implementations/claimers/PingPongClaimer.sol";
import "@sense-finance/v1-core/src/adapters/abstract/factories/ERC4626Factory.sol";
import "@sense-finance/v1-core/src/adapters/abstract/factories/ERC4626CropsFactory.sol";
import "@sense-finance/v1-core/src/adapters/abstract/factories/ERC4626CropFactory.sol";
import "@sense-finance/v1-core/src/adapters/abstract/factories/OwnableERC4626Factory.sol";
import "@sense-finance/v1-core/src/adapters/abstract/factories/OwnableERC4626CropFactory.sol";
import "@sense-finance/v1-core/src/adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import "@sense-finance/v1-core/src/adapters/implementations/oracles/MasterPriceOracle.sol";
import "@sense-finance/v1-core/src/tests/test-helpers/mocks/fuse/MockOracle.sol";
import "@sense-finance/v1-core/src/tests/test-helpers/mocks/fuse/MockComptroller.sol";
import "@sense-finance/v1-core/src/tests/test-helpers/mocks/fuse/MockFuseDirectory.sol";
import "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockAdapter.sol";
import "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol";
import "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockTarget.sol";
import "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockFactory.sol";
import "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockERC4626.sol";
import { Permit2Clone } from "@sense-finance/v1-core/src/tests/test-helpers/Permit2Clone.sol";
import { CAdapter } from "@sense-finance/v1-core/src/adapters/implementations/compound/CAdapter.sol";
import { FAdapter } from "@sense-finance/v1-core/src/adapters/implementations/fuse/FAdapter.sol";
import { AuraAdapter } from "@sense-finance/v1-core/src/adapters/implementations/aura/AuraAdapter.sol";
import { OwnableAuraAdapter } from "@sense-finance/v1-core/src/adapters/implementations/aura/OwnableAuraAdapter.sol";
import { AuraVaultWrapper } from "@sense-finance/v1-core/src/adapters/implementations/aura/AuraVaultWrapper.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { NoopPoolManager } from "@sense-finance/v1-fuse/src/NoopPoolManager.sol";
import { EmergencyStop } from "@sense-finance/v1-utils/src/EmergencyStop.sol";
import { MultiRewardsDistributor } from "@sense-finance/v1-core/src/external/MultiRewardsDistributor.sol";

import { EulerERC4626WrapperFactory } from "@sense-finance/v1-core/src/adapters/abstract/erc4626/yield-daddy/euler/EulerERC4626WrapperFactory.sol";
import { RewardsDistributor } from "../lib/morpho-core-v1/contracts/common/rewards-distribution/RewardsDistributor.sol";

import { AutoRollerFactory } from "@auto-roller/src/AutoRollerFactory.sol";
import { AutoRoller, RollerUtils } from "@auto-roller/src/AutoRoller.sol";
import { RollerPeriphery } from "@auto-roller/src/RollerPeriphery.sol";
import { MockOwnableAdapter } from "@auto-roller/src/test/utils/MockOwnedAdapter.sol";

import "./Versioning.sol";