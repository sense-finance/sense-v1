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

## Sense V1 project structure

### Divider
TBD

### Tokens
TBD

### Modules

A Collection of Modules and Utilities for Sense V1

### G Claim Wrapper

The G Claim Wrapper is a contract that lets a user deposit their "Collect" Claims and receive "Drag" Claim representations. Specifically, it enables users to backfill interest accrued on their "Collect" Claim so that it can be used in other DeFi projects that don't know how to collect accrued yield for the user. Similarly, users may bring existing gClaims back to the contract to re-extract the PY and reconstitute their Collect Claims.

### Recycling Module

The Recycling Module is a contract for yield traders who want constantly-preserved IR sensitivity on their balances, and do not want to find reinvestment opportunities for their PY. The contract uses a dutch auction to automatically sell collected PY off at some interval for more Claims, which refocuses users' positions on FY.


## Developing
|       |   	|
|---	|---	|
| `dapp build` | compiles code  |
| `dapp test`  | run tests   	|
| `dapp debug` | run tests using HEVM interactive debugger |
| `yarn lint`  | run linter |
| `yarn prettier`  | fix linter errors |

## Branching (TBD)

Right now, we will be just using `dev` and  `master` branches.

- `master` represents the contracts live on `mainnet` and all testnets.
- `alpha` is for the newest version of contracts, and is reserved for deploys to `kovan`
- `beta` is for promoted alpha contracts, and is reserved for deploys to `rinkeby`
- `release-candidate` is for promoted beta contracts, and is reserved for deploys to `ropsten`

When a new version of the contracts makes its way through all testnets, it eventually becomes promoted in `master`, with [semver](https://semver.org/) reflecting contract changes in the `major` or `minor` portion of the version (depending on backwards compatibility). `patch` changes are simply for changes to the JavaScript interface.

## Testing

Run tests with `dapp test`
TBD: How to get test coverage with dapptools?

`
![ci](https://github.com/sense-finance/sense-v1/actions/workflows/ci.yml/badge.svg)

[comment]: <> ([![codecov]&#40;https://codecov.io/gh/Sense/sense-v1/branch/develop/graph/badge.svg&#41;]&#40;https://codecov.io/gh/Sensefinance/sense;)

Please see [docs.sense.finance/contracts/testing](https://docs.sense.finance/contracts/testing) for an overview of the automated testing methodologies.
