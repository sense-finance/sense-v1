# Sense v1 • [![ci](https://github.com/sense-finance/sense-v1/actions/workflows/ci.yml/badge.svg)](https://github.com/sense-finance/space-v1/actions/workflows/ci.yml) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)


The Sense Protocol is a decentralized fixed-income protocol on Ethereum, allowing users to manage risk through fixed rates and future yield trading on existing yield bearing-assets.

Extensive documentation and use cases are available within this README and in the Sense docs [here](https://docs.sense.finance/).

One way to interact with Sense is through our official [app](https://app.sense.finance/eth-mainnet/rates)

Active development occurs in this repository, which means some contracts in it might not be production-ready. Proceed with caution.

### Community   

[![Discord](https://badgen.net/badge/icon/discord?icon=discord&label)](https://discord.com/invite/krVGnQgSzG)
[![Twitter Follow](https://img.shields.io/twitter/follow/senseprotocol.svg?label=senseprotocol&style=social)](https://twitter.com/senseprotocol)


## Deployments

### Mainnet v1.2.0

| Contract   | Address                                                                                                                                        |
| ------- | ------------------------------------------------------------------------------------------------------------------------- |
| Divider | [0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0](https://etherscan.io/address/0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0#code)                     |
| Periphery  | [0xf22AC51fb2711B307be463db3d830a5B680E3dD1](https://etherscan.io/address/0xf22AC51fb2711B307be463db3d830a5B680E3dD1#code)      |
| PoolManager | [0x7a1d595690aaF08d9157988820c14348F6930de9](https://etherscan.io/address/0x7a1d595690aaF08d9157988820c14348F6930de9#code)                     |
| WstETHAdapter  | [0x9F1e828EbCa376FDb613Aa513308769C83C451Bc](https://etherscan.io/address/0x9F1e828EbCa376FDb613Aa513308769C83C451Bc)      |
| cUSDC-CAdapter  | [0x7923C555Df05C284916D20Dd6A73e721cd010053](https://etherscan.io/address/0x7923C555Df05C284916D20Dd6A73e721cd010053)
| EmergencyStop  | [0xdC2eDFf06AF7944F4eFd22A105ac693d848Ee52f](https://etherscan.io/address/0xdC2eDFf06AF7944F4eFd22A105ac693d848Ee52f)  


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

Sense has an active bug bounty on ImmuneFi, with up to $50,000 for reporting a bug. All of Sense's deployed contracts & Sense Portal are in scope for the bug bounty.

## Conventions

### Branching

Right now, we are using `dev` and  `main` branches.

- `main` represents the contracts live on `mainnet` and all testnets
- `dev` is for the newest version of contracts, and is reserved for deployments to `goerli`

When a new version of the contracts makes its way through the testnet, it eventually becomes promoted in `main`, with [semver](https://semver.org/) reflecting contract changes in the `major` or `minor` portion of the version (depending on backwards compatibility).
