# Sense Finance

![ci](https://github.com/sense-finance/sense-v1/actions/workflows/ci.yml/badge.svg)

[comment]: <> ([![codecov]&#40;https://codecov.io/gh/Sense/sense-v1/branch/develop/graph/badge.svg&#41;]&#40;https://codecov.io/gh/Sensefinance/sense;)
[comment]: <> ([![npm version]&#40;https://badge.fury.io/js/sense-finance.svg&#41;]&#40;https://badge.fury.io/js/sense-finance&#41;)


The Sense Protocol is a decentralized fixed-income protocol on Ethereum, allowing users to manage risk through fixed rates and future yield trading on existing yield bearing-assets.

For the latest documentation see [docs.sense.finance](https://docs.sense.finance/)

You can use Sense at: [app.sense.finance](https://v)

Active development occurs in this repository, which means some contracts in it might not be production-ready. Proceed with caution.

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

Note: This repo is configured with this version of `dapp` && `solc`:
```
dapp 0.34.0
solc, the solidity compiler commandline interface
Version: 0.8.6+commit.11564f7e.Darwin.appleclang
hevm 0.48.1
```

Install just:

```sh
brew install just
# or
cargo install just
```


## Project setup
Clone this repo & install dependencies
```
git clone https://github.com/sense-finance/sense-v1.git
yarn
dapp update
yarn build
```

## Sense V1 Architecture

# <img src="contracts-diagram.png" alt="sense smart contract user/contract interaction diagram">

The `Divider` is the accounting engine of the Sense Protocol. It allows users to "divide" `Target` assets into ERC20 `Zeros` & `Claims` with the help of numerous auxilary contracts including `Adapters`, `Adapter Factories`, and the `Periphery` contract. Each Target can have an arbitrary numnber of active instances or `series` of Zeros and Claims, and each series is uniquely identified by their `maturity`. The Divider reads [`Scale` values](https://docs.sense.finance/litepaper/#rate-accumulator) from Adapters to determine how much Target to distribute to Zero & Claim holders at or before maturity. Constituing as the "core" of Sense, these contracts fully implement the [Sense Lifecycle](https://docs.sense.finance/litepaper/#divider) as well as permissionless series management & onboarding of arbitrary Target yield-bearing assets. 

The core is surrounded by the following `modules`:
- `Space`, a Zero/Target AMM Pool that offers an LP position that is principal protected, yield-generating, and IL minimized
- `Pool Manager`, manager of the [Sense Fuse Lending Facility](https://medium.com/sensefinance/sense-finance-x-rari-capital-5c0e0b6289d4)

### Divider
The Divider contract contains the logic to `issue()` ERC20 Zeros and Claims, re-`combine()` those assets into Target before their `maturity`, `collect()` Target with Claim tokens, and `redeemZero()` at or after maturity.

### Adapter
Following a hub and spoke model, Adapters surround the Divider and hold logic related to their particular Divider Application, such as stripping yield from yield-bearing assets. Once an Adapter is onboarded, users can initialize/settle series, issue Zeros/Claims, and collect/redeem their Target via the Divider.

The Adapter holds the Target before a series' maturity and contains logic to handle arbitrary airdrops from native or 3rd party liquidity mining programs. Typically denominated in another asset, airdropped tokens are distributed to Claim holders in addition to the yield accrued from the Target. In addition to asset custody, Adapters store parameters related to their individual applications, which gives guidance to the Divider when performing the above-mentioned operations. The parameters include:

1. `target` - address to the Target 
2. `oracle` - address to the Oracle of the Target's Underlying
3. `delta` - max growth per second allowed in the scale, as retrieved from the Target's protocol
4. `ifee` - issuance fee
5. `stake` - token to stake at issuance
6. `stakeSize` - amount to stake at issuance
7. `minm` - min maturity
8. `maxm` - max maturity
9. `mode` - maturity date type (0 for monthly, 1 for weekly)

To create an Adapter implementation without airdrops, the contract needs to inherit from `BaseAdapter.sol` and override `_scale()`, `underlying()`, `wrapUnderlying()`, `unwrapTarget()`, `getUnderlyingPrice()`, and `notify()`. 

There are two types of Adapters:
1. Sense Sponsored Adapters - these are verified by the Sense team and can be permissionessly deployed by Adapter Factories
2. Unverified Adapters - there are unverified by the Sense team and could be controlled by malicious actors

At the time of launch, the Divider will interface only with the Sense Sponsored Adapters. However, once the `permissionless` flag is enabled, users can permissionessly onboard Adapters via `Divider.addAdapter()` and leverage Sense's infrastructure to build new fixed-income products, structured products, and yield primitives never before seen in DeFi.

### Adapter factory
The Adapter factory allows any person to deploy a Sense Sponsored Adapter for a given Target in a permissionless manner.

Following a gradual expansion, Sense Finance will deploy one Adapter Factory for each protocol (e.g cTokens Adapter Factory, Curve LP Share Adapter Factory, etc).

Most factories will be similar except for how they implement `_exists(target)`, a method that communicates to a data contract from the external protocol (e.g the Comptroller on Compound Finance) to check whether the Target passed is a supported asset of that protocol.

Users can deploy a Sense Sponsored Adapter by making a call to the `Periphery` contract, which has authority to call `deployAdapter(_target)` on the Adapter Factory.

To create an Adapter Factory, the contract needs to inherit from `BaseFactory.sol` and override `_exists()`.

### Periphery
The Periphery contract contains bundled actions for Series Actors and general users. 

For Series Actors, the Periphery exposes the public entry points to deploy Sense-Sponsored Adapters for new Targets and to initialize Series within existing adapters. The Target Sponsor calls `onboardAdapter` which will deploy an Adapter via an Adapter Factory and onboard the Target to the Sense Fuse Pool. The Series Sponsor calls `sponsorSeries` to initialize a series in the Divider and create a Space for Zero / Target trading.

Because the BalancerV2 only holds Zeros & Targets, users need to execute additional steps to `issue()` and `combine()` in order to enter/exit into/from a Claim position. The Periphery allows users to bundle the necessary calls behind a single function interface and perform the following operations atomically, flash loaning Target from an Adapter when need be:
- swap[Target|Underlying]ForZeros
- swap[Target|Underlying]ForClaims
- swapZerosFor[Target|Underlying]
- swapClaimsFor[Target|Underlying]

Similarily, the Periphery exposes several atomic transactions for LP management through Space.
- addLiquidityFrom[Target|Underlying]
- removeLiquidityTo[Target|Underlying]
- migrateLiquidity

### Tokens
This directory contains the tokens contracts. Sense Protocol uses [Rari's ERC20 implementation](https://github.com/Rari-Capital/solmate/blob/main/src/erc20/ERC20.sol) and defines:
- `Token.sol` as a minimalist ERC20 implementation with auth'd `burn()` and `mint()`. Used for Zeros.
- `Claim.sol` as a minimalist yield token implementation that:
    1. inherits from `Token`
    2. adds `maturity`, `divider` and `adapter` address variables
    3. defines `collect()` (which calls `Divider.collect()`) and overrides `transfer()` and `transferFrom()` to also call `collect()`

### Modules
A Collection of Modules and Utilities for Sense V1

#### Space
`Space` is an Zero/Target AMM Pool built on Balancer V2. It implements the [Yieldspace](https://yield.is/YieldSpace.pdf) invariant but introduces a meaningful improvement by allowing LPs to deposit a yield-generating _quote_ asset, i.e. the Target, instead of the Zero's Underlying, as was originally concieved. Because its TWAP price is utilized by the Sense Fuse Pool, Space is heavily inspired by Balancer's [Weighted 2 Token Pool](https://github.com/balancer-labs/balancer-v2-monorepo/blob/c40b9a783e328d817892693bd13b4a14e4dcff4d/pkg/pool-weighted/contracts/WeightedPool2Tokens.sol) and its oracle functionality. Each Series will have a unique `Space` for Zero/Target trading, which will be deployed and initialized through the `Space Factory`. More context on `Space`'s development can be found here (TODO, add link)

#### Pool Manager
`PoolManager` manages the Sense Fuse Pool, a collection of borrowing/lending markets serving all Zeros, the Space LP Shares, and their respective Targets. It allows users to permissionlessly onboard new Target (`addTarget()`), Zeros and their Space LP shares (`queueSeries()` & `addSeries()`). Once new assets are onboarded, the Sense Fuse Pool will query price data from the `Master Oracle` which exposes a mapping, linking token addresses to oracle addresses. 

#### G Claim Manager [WIP]
`GClaimManager` lets a user deposit their "Collect" Claims and receive "Drag" Claim representations. Specifically, it enables users to backfill interest accrued on their "Collect" Claim so that it can be used in other DeFi projects that don't know how to collect accrued yield for the user. Similarly, users may bring existing gClaims back to the contract to re-extract the PY and reconstitute their Collect Claims. More information between Collect and Drag Claims can [be found here](https://medium.com/sensefinance/designing-yield-tokens-d20c34d96f56). Note that some Claims within Sense have PY composed of native yield as well as airdrop rewards, the latter of which can balloon and shrink in value, causing wide fluctuations in the gClaim valuation. 

#### Recycling Module [WIP]
The Recycling Module is a contract for yield traders who want constantly-preserved IR sensitivity on their balances, and do not want to find reinvestment opportunities for their PY. The contract uses a dutch auction to automatically sell collected PY off at some interval for more Claims, which refocuses users' positions on FY.


### Access
We use `Trust.sol` to provide access control via `requiresTrust` to contracts inheriting from it. In some contracts, we introduce per-function access control for greater granularity, such as `peripherOnly`.

### Admin

The long-term goal of the Sense Protocol is to be as governance minimized as possible. However, out of caution, we’re taking a progressive decentralization approach, where Sense Finance Inc retains certain privileged permissions of Sense-v1 to ensure the system scales safely as well as pause the system in case of an emergency (vulnerability, hack, etc). The following list elaborates on these permissions:

1. `Divider.setIsTrusted` - give auth to a new Adapter Factory
2. `Divider.setAdapter` - pause a faulty adapter
3. `Divider.backfillScale` - fix a faulty scale value / pass in a scale if no settlement occurs
4. `Divider.setPause` - pause the Divider (emergencies only)
5. `Divider.setGuard` - set the cap for the Guarded launch
6. `Divider.setGuarded` - release the Guards
7. `Divider.setPeriphery` - point to the Periphery
8. `Periphery.setFactory` - onboard a new Adapter Factory
8. `PoolManager.deployPool` - deploy the Sense Fuse Pool
9. `PoolManager.setParams` - set parameters for the Sense Fuse Pool

### External
These are libraries we need as part of the protocol that we've imported from other projects and modified for our needs.
- DateTime.sol
- FixedMath.sol
- FullMath.sol
- OracleLibrary.sol
- PoolAddress.sol


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


### Environment

1. Create a local `.env` file in the root directory of this project
2. Set `ALCHEMY_KEY` to a valid Alchemy API key
3. Set `MNEMONIC` to a valid seed phrase for deployments

## Branching (TBD)

Right now, we will be just using `dev` and  `master` branches.

- `master` represents the contracts live on `mainnet` and all testnets.
- `alpha` is for the newest version of contracts, and is reserved for deploys to `kovan`
- `beta` is for promoted alpha contracts, and is reserved for deploys to `rinkeby`
- `release-candidate` is for promoted beta contracts, and is reserved for deploys to `ropsten`

When a new version of the contracts makes its way through all testnets, it eventually becomes promoted in `master`, with [semver](https://semver.org/) reflecting contract changes in the `major` or `minor` portion of the version (depending on backwards compatibility).