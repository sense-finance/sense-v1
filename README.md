# Sense Finance

![ci](https://github.com/sense-finance/sense-v1/actions/workflows/ci.yml/badge.svg)

[comment]: <> ([![codecov]&#40;https://codecov.io/gh/Sense/sense-v1/branch/develop/graph/badge.svg&#41;]&#40;https://codecov.io/gh/Sensefinance/sense;)
[comment]: <> ([![npm version]&#40;https://badge.fury.io/js/sense-finance.svg&#41;]&#40;https://badge.fury.io/js/sense-finance&#41;)
[![Discord](https://img.shields.io/discord/790088877381517322.svg?color=768AD4&label=discord&logo=https%3A%2F%2Fdiscordapp.com%2Fassets%2F8c9701b98ad4372b58f13fd9f65f966e.svg)](https://discordapp.com/channels/790088877381517322/)
[![Twitter Follow](https://img.shields.io/twitter/follow/senseprotocol.svg?label=senseprotocol&style=social)](https://twitter.com/senseprotocol)

The Sense Protocol is a decentralized fixed-income protocol on Ethereum, allowing users to manage risk through fixed rates and future yield trading on existing yield bearing-assets.

For the latest documentation see [docs.sense.finance](https://docs.sense.finance/)

You can use Sense at: [app.sense.finance](https://v)

### Community   

[![Discord](https://img.shields.io/discord/790088877381517322.svg?color=768AD4&label=discord&logo=https%3A%2F%2Fdiscordapp.com%2Fassets%2F8c9701b98ad4372b58f13fd9f65f966e.svg)](https://discordapp.com/channels/790088877381517322/) [![Twitter Follow](https://img.shields.io/twitter/follow/senseprotocol.svg?label=senseprotocol&style=social)](https://twitter.com/senseprotocol)

---

## Installation

### Toolset

Install Nix if you haven't already:

```sh
# user must be in sudoers
curl -L https://nixos.org/nix/install | sh

# Run this or login again to use Nix
. "$HOME/.nix-profile/etc/profile.d/nix.sh"
```

Then install dapptools:

```
curl https://dapp.tools/install | sh
```
This configures the dapphub binary cache and installs the `dapp`, `solc`, `seth` and `hevm` executables.

More info about dapptools on https://github.com/dapphub/dapptools

## Project setup
- Clone this repo
```coffeescript
git clone https://github.com/sense-finance/sense-v1.git
```
- Install dependencies
```
make
```

## Sense V1 structure

### Access
We use `Warded.sol` to provide with access control via wards to contracts inheriting from it. Currently, `Divider.sol`, `BaseFactory.sol` and `Recycler.sol` are using it.

### Divider
The Divider contract contains the logic to "divide" Target assets into ERC20 Zeros and Claims, recombine those assets into Target, collect using Claim tokens, and redeem Zeros at or after maturity. The goal is to have the Sense Divider be the home for all yield-bearing asset liquidity in DeFi.

### External
These are libraries we need as part of the protocol that we've imported from other projects and modified for our needs.
- DateTime.sol
- WadMath.sol

### Feed
Feed contracts contain only the logic needed to calculate Scale values. The protocol will have several Feeds, each with similar code, that are granted core access to the Divider by authorized actors. In most cases, the only difference between Feeds will be how they calculate their Scale value.

Each feed has a *delta* value that represents the maximum growth per second a scale can be when retrieving a value from the protocol's scale method. This delta value is the same across all the targets within the same target type and is defined on the feed factory which then sets it to the feed on initialization.

To create a feed implementation, the contract needs to inherit from `BaseFeed.sol` and override `_scale()` which is a function that calls the external protocol to get the current scale value.

### Feed factory
The feed factory allows any person to deploy a feed for a given Target in a permissionless manner.

Sense will deploy one Feed Factory for each protocol it wants to give support to (e.g cTokens Feed Factory, aTokens Feed Factory, etc) and will grant core access to the Divider. 

Most factories will be similar except for how they implement the `_exists(target)`, a method that communicates to a data contract from the external protocol (e.g the Comptroller on Compound Finance) to check whether the target passed is a supported asset of that protocol.

Users can deploy a feed by making a call to `deployFeed(_target)` and sending the address of the target. Only supported targets can be used. You can check if a target is supported by doing a call to `controller.targets()`.

To create a feed factory, the contract needs to inherit from `BaseFactory.sol` and override `_exists()`.

### Modules

A Collection of Modules and Utilities for Sense V1

#### G Claim Wrapper

The G Claim Wrapper is a contract that lets a user deposit their "Collect" Claims and receive "Drag" Claim representations. Specifically, it enables users to backfill interest accrued on their "Collect" Claim so that it can be used in other DeFi projects that don't know how to collect accrued yield for the user. Similarly, users may bring existing gClaims back to the contract to re-extract the PY and reconstitute their Collect Claims.

#### Recycling Module

The Recycling Module is a contract for yield traders who want constantly-preserved IR sensitivity on their balances, and do not want to find reinvestment opportunities for their PY. The contract uses a dutch auction to automatically sell collected PY off at some interval for more Claims, which refocuses users' positions on FY.

### Tokens
This directory contains the tokens contracts. Sense protocol uses [Rari's ERC20 implementation](https://github.com/Rari-Capital/solmate/blob/main/src/erc20/ERC20.sol) and defines:
- `Mintable.sol` as a token which has minting and burning public methods and is also warded,
- `BaseToken.sol` as a `Mintable` token with the addition of `maturity`, `divider` and `feed` address variables and restriction of the `burn()` to only be called from the `wards` and
- `Claim.sol` which inherits from `BaseToken` and defines a `collect()` (which calls `collect()` on `Divider.sol`) and overrides  `transfer()` and `transferFrom()` to also call `collect()`

Note that Zeros are represented with the `BaseToken.sol` contract.

## Developing
|       |   	|
|---	|---	|
| `yarn build` | compiles code  |
| `yarn debug` | run tests using HEVM interactive debugger |
| `yarn test`  | run tests   	|
| `yarn testcov`  | run tests with coverage  	|
| `yarn test-mainnet`  | run tests using a fork from mainnet* |
| `yarn lint`  | run linter |
| `yarn fix`   | runs both prettier and solhint and automatically fix errors |

* Testing on mainnet requires to have a ALCHEMY_KEY set: make a copy of `.env.example`, rename it to `.env`  and set `ALCHEMY_KEY` to your alchemy api key.

## Branching (TBD)

Right now, we will be just using `dev` and  `master` branches.

- `master` represents the contracts live on `mainnet` and all testnets.
- `alpha` is for the newest version of contracts, and is reserved for deploys to `kovan`
- `beta` is for promoted alpha contracts, and is reserved for deploys to `rinkeby`
- `release-candidate` is for promoted beta contracts, and is reserved for deploys to `ropsten`

When a new version of the contracts makes its way through all testnets, it eventually becomes promoted in `master`, with [semver](https://semver.org/) reflecting contract changes in the `major` or `minor` portion of the version (depending on backwards compatibility).