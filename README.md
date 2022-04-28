# Sense v1 • [![ci](https://github.com/sense-finance/sense-v1/actions/workflows/ci.yml/badge.svg)](https://github.com/sense-finance/space-v1/actions/workflows/ci.yml) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)


The Sense Protocol is a decentralized fixed-income protocol on Ethereum, allowing users to manage risk through fixed rates and future yield trading on existing yield bearing-assets.

Extensive documentation and use cases are available within this README and in the Sense docs [here](https://docs.sense.finance/).

One way to interact with Sense is through our official [app](https://app.sense.finance/eth-mainnet/rates)

Active development occurs in this repository, which means some contracts in it might not be production-ready. Proceed with caution.

### Community   

[![Discord](https://badgen.net/badge/icon/discord?icon=discord&label)](https://discord.com/invite/krVGnQgSzG)
[![Twitter Follow](https://img.shields.io/twitter/follow/senseprotocol.svg?label=senseprotocol&style=social)](https://twitter.com/senseprotocol)


## Deployments

### Underlying & Targets
Token | Address
--------- | -------------
WETH | [0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2](https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2)
USDC | [0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48](https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48)
wstETH | [0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0](https://etherscan.io/address/0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0)
cUSDC | [0x39aa39c021dfbae8fac545936693ac917d5e7563](https://etherscan.io/token/0x39aa39c021dfbae8fac545936693ac917d5e7563)


### v1.2.1
Contract | Address
--------- | -------------
[Divider](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/Divider.sol) | [0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0](https://etherscan.io/address/0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0#code)
[Periphery](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/Periphery.sol) | [0xd90eb87edbf1e124b275234fe172374547b4eb80](https://etherscan.io/address/0xd90eb87edbf1e124b275234fe172374547b4eb80#code)
[PoolManager](https://github.com/sense-finance/sense-v1/blob/dev/pkg/fuse/src/PoolManager.sol) | [0xf01eb98de53ed964ac3f786b80ed8ce33f05f417](https://etherscan.io/address/0xf01eb98de53ed964ac3f786b80ed8ce33f05f417#code)
[TokenHandler](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/Divider.sol) | [0x4933494b4070c01bfFBd3c53C1E44A3d9d95DD8e](https://etherscan.io/address/0x4933494b4070c01bfFBd3c53C1E44A3d9d95DD8e)
[EmergencyStop](https://github.com/sense-finance/sense-v1/blob/dev/pkg/utils/src/EmergencyStop.sol) | [0xdC2eDFf06AF7944F4eFd22A105ac693d848Ee52f](https://etherscan.io/address/0xdC2eDFf06AF7944F4eFd22A105ac693d848Ee52f)
[WstETHAdapter](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/adapters/lido/WstETHAdapter.sol) | [0x36c744Dd2916E9E04173Bee9d93D554f955a999d](https://etherscan.io/address/0x36c744Dd2916E9E04173Bee9d93D554f955a999d)
[CFactory](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/adapters/compound/CFactory.sol) | [0x6B48a75Db6619C95431599059BA0740BBd2A46d9](https://etherscan.io/address/0x6b48a75db6619c95431599059ba0740bbd2a46d9)
[cUSDC-CAdapter](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/adapters/compound/CAdapter.sol) | [0x7923C555Df05C284916D20Dd6A73e721cd010053](https://etherscan.io/address/0x7923C555Df05C284916D20Dd6A73e721cd010053)
sP-wstETH:01-05-2022:5 | [0x923d411E62Cd3727e0B7dec458Ba89B0191A7067](https://etherscan.io/address/0x923d411E62Cd3727e0B7dec458Ba89B0191A7067)
sY-wstETH:01-05-2022:5 | [0x3A3359af098bb20a4EB1809a298Ca7B1d5B6Be94](https://etherscan.io/address/0x3A3359af098bb20a4EB1809a298Ca7B1d5B6Be94)
sP-wstETH:01-07-2022:5 | [0xc1Fd90b0C31CF4BF16C04Ed8c6A05105EFc7c989](https://etherscan.io/address/0xc1Fd90b0C31CF4BF16C04Ed8c6A05105EFc7c989)
sY-wstETH:01-07-2022:5 | [0x7ecE94fD7F997800F7bfE2D53B9D0AABcE05d10b](https://etherscan.io/address/0x7ecE94fD7F997800F7bfE2D53B9D0AABcE05d10b)
sP-cUSDC:01-05-2022:3 | [0xf6fCcB2C42c3084e0926D034c504309498f1d5aC](https://etherscan.io/address/0xf6fCcB2C42c3084e0926D034c504309498f1d5aC)
sY-cUSDC:01-05-2022:3 | [0xd74f67771Aaa23EFE05fBb96DC29B5bA164E4355](https://etherscan.io/address/0xd74f67771Aaa23EFE05fBb96DC29B5bA164E4355)
sP-cUSDC:01-07-2022:3 | [0x003d32a8C728Ed4d452fD06C07491d87a723a9C9](https://etherscan.io/address/0x003d32a8C728Ed4d452fD06C07491d87a723a9C9)
sY-cUSDC:01-07-2022:3 | [0x48c4891294Be2333A7F9B68FfeE6320317ea2c36](https://etherscan.io/address/0x48c4891294Be2333A7F9B68FfeE6320317ea2c36)
[SpaceFactory](https://github.com/sense-finance/space-v1/blob/main/src/SpaceFactory.sol) | [0x984682770f1EED90C00cd57B06b151EC12e7c51C](https://etherscan.io/address/0x984682770f1EED90C00cd57B06b151EC12e7c51C)
[Space LP Share-wstETH:01-05-2022:5](https://github.com/sense-finance/space-v1/blob/main/src/Space.sol) * | [0xbB6C7b5E0804d07aE31A43E6E83Ea66fb128a3BB](https://etherscan.io/address/0xbB6C7b5E0804d07aE31A43E6E83Ea66fb128a3BB)
[Space LP Share-wstETH:01-07-2022:5](https://github.com/sense-finance/space-v1/blob/main/src/Space.sol) * | [0x34d179259336812A1C7d320A0972e949dA5fa26d](https://etherscan.io/address/0x34d179259336812A1C7d320A0972e949dA5fa26d)
[Space LP Share-cUSDC:01-05-2022:3](https://github.com/sense-finance/space-v1/blob/main/src/Space.sol) * | [0xD40954A9Ff856f9A2C6eFa88aD45623157A7dfF0](https://etherscan.io/address/0xD40954A9Ff856f9A2C6eFa88aD45623157A7dfF0)
[Space LP Share-cUSDC:01-07-2022:3](https://github.com/sense-finance/space-v1/blob/main/src/Space.sol) * | [0x000b87c8A4c6CBCEf7a2577e8aa0Dc134C67c3D8](https://etherscan.io/address/0x000b87c8A4c6CBCEf7a2577e8aa0Dc134C67c3D8)

\* We are aware that the Name and Symbol does not include the Space LP Share. This will be fixed in the next version of Space.

### Goerli v1.2.0

| Contract   | Address                                                                                                                                        |
| ------- | ------------------------------------------------------------------------------------------------------------------------- |
| Divider | [0x240c7D23cfFB8438ad4fdF1a4FAcF47505A4A37f](https://goerli.etherscan.io/address/0x240c7D23cfFB8438ad4fdF1a4FAcF47505A4A37f#code)                     |
| Periphery  | [0xeEb84e2381f262e88EDB193665C017DBd965Af78](https://goerli.etherscan.io/address/0xeEb84e2381f262e88EDB193665C017DBd965Af78#code)      |
| PoolManager | [0x57D69DF010C495aceb22D8433288C1C774Cbb77E](https://goerli.etherscan.io/address/0x57D69DF010C495aceb22D8433288C1C774Cbb77E#code)                     |
| BalancerVault  | [0x968b38155b99B05b93c8aAF963127Fb128f812F4](https://goerli.etherscan.io/address/0x968b38155b99B05b93c8aAF963127Fb128f812F4#code)      

## Development

This repo uses [Foundry: forge](https://github.com/gakonst/foundry) for development and testing
and git submodules for dependency management (we previously used `dapp` and `nix`, so there are vestiges from those tools around).

To install Foundry [Foundry: Forge](https://github.com/gakonst/foundry), use the instructions in the linked repo.

In addition, this repo uses [just](https://github.com/casey/just) as our command runner:

```sh
brew install just
# or
cargo install just
```

### Test

```bash
# Get contract dependencies
git submodule update --init --recursive
yarn isntall # or npm install

# Run local tests
just turbo-test-local

# Run mainnet fork tests
just turbo-test-mainnet
```

### Format

```bash
# Run linter
yarn lint

# Run formatter
yarn fix
```

### Deploy

This repo uses [hardhat deploy](https://github.com/wighawag/hardhat-deploy) for replicable deployments. To create a new deployment:

```bash
# Navigate to the `deployments` package
cd pkg/deployments

# Deploy the protcol with mocks on a forked network
yarn deploy:hardhat-fork:sim

# Deploy the protcol with production config on a forked network
yarn deploy:hardhat-fork:sim

# Deploy the protcol with mocks on a live network
yarn hardhat deploy --network <network> --tags scenario:simulated

# Deploy the protcol with production config on a live network
yarn hardhat deploy --network <network> --tags scenario:prod
```

### Environment

1. Create a local `.env` file in the root directory of this project
2. Set `ALCHEMY_KEY` to a valid Alchemy API key
3. Set `MNEMONIC` to a valid seed phrase for deployments

## Security

Sense contracts have gone through different independent security audits performed by [Spearbit](https://spearbit.com), [Fixed Point Solutions (Kurt Barry)](https://github.com/fixed-point-solutions), [ABDK](https://www.abdk.consulting/) and [Peckshield](https://peckshield.com). Reports are located in the [`audits`](./audits) directory.

### Bug Bounties

Sense will have an active bug bounty on ImmuneFi, with up to $50,000 for reporting a bug. All of Sense's deployed contracts & Sense Portal are in scope for the bug bounty. See a bug before our bug bounty is live? Reach out to josh & kenton @ sense.finance.

## Conventions

### Branching

Right now, we are using `dev` and  `main` branches.

- `main` represents the contracts live on `mainnet` and all testnets
- `dev` is for the newest version of contracts, and is reserved for deployments to `goerli`

When a new version of the contracts makes its way through the testnet, it eventually becomes promoted in `main`, with [semver](https://semver.org/) reflecting contract changes in the `major` or `minor` portion of the version (depending on backwards compatibility).
