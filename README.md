# Sense v1 • [![ci](https://github.com/sense-finance/sense-v1/actions/workflows/ci.yml/badge.svg)](https://github.com/sense-finance/space-v1/actions/workflows/ci.yml) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)


The Sense Protocol is a decentralized fixed-income protocol on Ethereum, allowing users to manage risk through fixed rates and future yield trading on existing yield bearing-assets.

Extensive documentation and use cases are available within this README and in the Sense docs [here](https://docs.sense.finance/).

One way to interact with Sense is through our official [app](https://app.sense.finance/eth-mainnet/rates)

Active development occurs in this repository, which means some contracts in it might not be production-ready. Proceed with caution.

### Community   

[![Discord](https://badgen.net/badge/icon/discord?icon=discord&label)](https://discord.com/invite/krVGnQgSzG)
[![Twitter Follow](https://img.shields.io/twitter/follow/senseprotocol.svg?label=senseprotocol&style=social)](https://twitter.com/senseprotocol)


## Deployments

### Mainnet v1.1.0

| Contract   | Address                                                                                                                                        |
| ------- | ------------------------------------------------------------------------------------------------------------------------- |
| Divider | [0x6961e8650A1548825f3e17335b7Db2158955C22f](https://etherscan.io/address/0x6961e8650A1548825f3e17335b7Db2158955C22f#code)                     |
| Periphery  | [0xe983Ec9a2314a46F2713A838349bB05f3e629FE5](https://etherscan.io/address/0xe983Ec9a2314a46F2713A838349bB05f3e629FE5#code)      |
| PoolManager | [0xEBf829fB23bb3caf7eEeD89515264C18e2CE1dFb](https://etherscan.io/address/0xEBf829fB23bb3caf7eEeD89515264C18e2CE1dFb#code)                     |
| WstETHAdapter  | [0x174E9763742a9Cd53E86F1dFeE73CfF74eC1E7F1](https://etherscan.io/address/0x174E9763742a9Cd53E86F1dFeE73CfF74eC1E7F1)      |
| cUSDC-CAdapter  | [0x1896F91d86520273A52F9e2e5AC6f105bc222294](https://etherscan.io/address/0x1896F91d86520273A52F9e2e5AC6f105bc222294)
| EmergencyStop  | [0x1CaAc05E37dfD5CB1A3B682Cdc6E6bF7a6e7Db9f](https://etherscan.io/address/0x1CaAc05E37dfD5CB1A3B682Cdc6E6bF7a6e7Db9f)  


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

Sense contracts have gone through different independent security audits performed by [Fixed Point Solutions (Kurt Barry)](https://github.com/fixed-point-solutions), [Spearbit](https://spearbit.com), [ABDK](https://www.abdk.consulting/) and [Peckshield](https://peckshield.com). Reports are located in the [`audits`](./audits) directory.

### Bug Bounties

Sense has an active bug bounty on ImmuneFi, with up to $50,000 for reporting a bug. All of Sense's deployed contracts & Sense Portal are in scope for the bug bounty.

## Conventions

### Branching

Right now, we are using `dev` and  `main` branches.

- `main` represents the contracts live on `mainnet` and all testnets
- `dev` is for the newest version of contracts, and is reserved for deployments to `goerli`

When a new version of the contracts makes its way through the testnet, it eventually becomes promoted in `main`, with [semver](https://semver.org/) reflecting contract changes in the `major` or `minor` portion of the version (depending on backwards compatibility).
