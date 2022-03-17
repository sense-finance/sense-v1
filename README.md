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
| WstETHAdapter  | [0xF3B7Ecc8238f5d6EC6c8d31D667dDd1C2A708a8C](https://etherscan.io/address/0xF3B7Ecc8238f5d6EC6c8d31D667dDd1C2A708a8C#code)      |
| cUSDC-CAdapter  | [0xf61c68a42FE0D7aA22182953B0f4aD5960f1e439](https://etherscan.io/address/0xf61c68a42FE0D7aA22182953B0f4aD5960f1e439#code)     

### Goerli v1.1.0

| Contract   | Address                                                                                                                                        |
| ------- | ------------------------------------------------------------------------------------------------------------------------- |
| Divider | [0xc8b594Bf6cC2a41e3afC3807e667B055CfBF8304](https://etherscan.io/address/0xc8b594Bf6cC2a41e3afC3807e667B055CfBF8304#code)                     |
| Periphery  | [0x992c0A5Ad53b9f0553299EEFD79B7EBBEF22D324](https://etherscan.io/address/0x992c0A5Ad53b9f0553299EEFD79B7EBBEF22D324#code)      |
| PoolManager | [0xDd2c59C90c7b4E03584F684A47aa7BAD03Eb91E3](https://etherscan.io/address/0xDd2c59C90c7b4E03584F684A47aa7BAD03Eb91E3#code)                     |
| BalancerVault  | [0xB9EA2205A94E001C22421389b4165BC6e74bbd24](https://etherscan.io/address/0xB9EA2205A94E001C22421389b4165BC6e74bbd24#code)      


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

## Conventions

### Branching

Right now, we are using `dev` and  `main` branches.

- `main` represents the contracts live on `mainnet` and all testnets
- `dev` is for the newest version of contracts, and is reserved for deployments to `goerli`

When a new version of the contracts makes its way through the testnet, it eventually becomes promoted in `main`, with [semver](https://semver.org/) reflecting contract changes in the `major` or `minor` portion of the version (depending on backwards compatibility).
