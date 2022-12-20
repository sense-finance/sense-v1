# Sense v1 • [![ci](https://github.com/sense-finance/sense-v1/actions/workflows/ci.yml/badge.svg)](https://github.com/sense-finance/space-v1/actions/workflows/ci.yml) [![codecov](https://codecov.io/gh/sense-finance/sense-v1/branch/dev/graph/badge.svg?token=6MXQJ0MOLI)](https://codecov.io/gh/sense-finance/sense-v1) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)


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


### v1.4.0
Contract | Address
--------- | -------------
[Divider](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/Divider.sol) | [0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0](https://etherscan.io/address/0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0#code)
[Periphery](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/Periphery.sol) | [0xaa17633AA5A3Cb56698838561161bdb16Cebb8E3](https://etherscan.io/address/0xaa17633AA5A3Cb56698838561161bdb16Cebb8E3#code)
[PoolManager](https://github.com/sense-finance/sense-v1/blob/dev/pkg/fuse/src/PoolManager.sol) | [0x9BFcA4882c1D8CDE3b4f787d3d74eb0E1bb0ec1B](https://etherscan.io/address/0x9BFcA4882c1D8CDE3b4f787d3d74eb0E1bb0ec1B#code)
[TokenHandler](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/Divider.sol) | [0x4933494b4070c01bfFBd3c53C1E44A3d9d95DD8e](https://etherscan.io/address/0x4933494b4070c01bfFBd3c53C1E44A3d9d95DD8e)
[EmergencyStop](https://github.com/sense-finance/sense-v1/blob/dev/pkg/utils/src/EmergencyStop.sol) | [0xdC2eDFf06AF7944F4eFd22A105ac693d848Ee52f](https://etherscan.io/address/0xdC2eDFf06AF7944F4eFd22A105ac693d848Ee52f)
[WstETHAdapter](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/adapters/implementations/lido/WstETHAdapter.sol) | [0x36c744Dd2916E9E04173Bee9d93D554f955a999d](https://etherscan.io/address/0x36c744Dd2916E9E04173Bee9d93D554f955a999d)
[CFactory](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/adapters/implementations/compound/CFactory.sol) | [0xeC0E2e78BbEcFA2313150Edb273a429C9D4B25Da](https://etherscan.io/address/0xec0e2e78bbecfa2313150edb273a429c9d4b25da#code)
[cUSDC-CAdapter](https://github.com/sense-finance/sense-v1/blob/dev/pkg/core/src/adapters/implementations/compound/CAdapter.sol) | [0xEc30fEaC79898aC5FFe055bD128BBbA9584080eC](https://etherscan.io/address/0xEc30fEaC79898aC5FFe055bD128BBbA9584080eC)
sP-wstETH:01-05-2022:5 | [0x923d411E62Cd3727e0B7dec458Ba89B0191A7067](https://etherscan.io/address/0x923d411E62Cd3727e0B7dec458Ba89B0191A7067)
sY-wstETH:01-05-2022:5 | [0x3A3359af098bb20a4EB1809a298Ca7B1d5B6Be94](https://etherscan.io/address/0x3A3359af098bb20a4EB1809a298Ca7B1d5B6Be94)
sP-wstETH:01-07-2022:5 | [0xc1Fd90b0C31CF4BF16C04Ed8c6A05105EFc7c989](https://etherscan.io/address/0xc1Fd90b0C31CF4BF16C04Ed8c6A05105EFc7c989)
sY-wstETH:01-07-2022:5 | [0x7ecE94fD7F997800F7bfE2D53B9D0AABcE05d10b](https://etherscan.io/address/0x7ecE94fD7F997800F7bfE2D53B9D0AABcE05d10b)
sP-cUSDC:01-05-2022:6 | [0xa93fBC8114f6AD04B59426A2aFc1dB9eDB841f7a](https://etherscan.io/address/0xa93fBC8114f6AD04B59426A2aFc1dB9eDB841f7a)
sY-cUSDC:01-05-2022:6 | [0xA5240A4a27817135E2aB30c8f1996a2d460C9Db4](https://etherscan.io/address/0xA5240A4a27817135E2aB30c8f1996a2d460C9Db4)
sP-cUSDC:01-07-2022:6 | [0xb636ADB2031DCbf6e2A04498e8Af494A819d4CB9](https://etherscan.io/address/0xb636ADB2031DCbf6e2A04498e8Af494A819d4CB9)
sY-cUSDC:01-07-2022:6 | [0x4ACA82E5686226A679875AACde7ECdf5fC5477ec](https://etherscan.io/address/0x4ACA82E5686226A679875AACde7ECdf5fC5477ec)
[SpaceFactory](https://github.com/sense-finance/space-v1/blob/main/src/SpaceFactory.sol) | [0x9e629751b3FE0b030C219e567156adCB70ad5541](https://etherscan.io/address/0x9e629751b3FE0b030C219e567156adCB70ad5541)
[Space LP Share-wstETH:01-05-2022:5](https://github.com/sense-finance/space-v1/blob/main/src/Space.sol) * | [0xbB6C7b5E0804d07aE31A43E6E83Ea66fb128a3BB](https://etherscan.io/address/0xbB6C7b5E0804d07aE31A43E6E83Ea66fb128a3BB)
[Space LP Share-wstETH:01-07-2022:5](https://github.com/sense-finance/space-v1/blob/main/src/Space.sol) * | [0x34d179259336812A1C7d320A0972e949dA5fa26d](https://etherscan.io/address/0x34d179259336812A1C7d320A0972e949dA5fa26d)
[Space LP Share-cUSDC:01-05-2022:6](https://github.com/sense-finance/space-v1/blob/main/src/Space.sol) * | [0x64db005d040EE62E8fa202291C73E8a6151A0399](https://etherscan.io/address/0x64db005d040EE62E8fa202291C73E8a6151A0399)
[Space LP Share-cUSDC:01-07-2022:6](https://github.com/sense-finance/space-v1/blob/main/src/Space.sol) * | [0x76E5F9860Bd5b8666DE322496f114B8a89183A2E](https://etherscan.io/address/0x76E5F9860Bd5b8666DE322496f114B8a89183A2E)

\* We are aware that the Name and Symbol does not include the Space LP Share. This will be fixed in the next version of Space.

### Goerli v1.4.0

| Contract   | Address                                                                                                                                        |
| ------- | ------------------------------------------------------------------------------------------------------------------------- |
| Divider | [0x09B10E45A912BcD4E80a8A3119f0cfCcad1e1f12](https://goerli.etherscan.io/address/0x09B10E45A912BcD4E80a8A3119f0cfCcad1e1f12#code)                     |
| Periphery  | [0x4bCBA1316C95B812cC014CA18C08971Ce1C10861](https://goerli.etherscan.io/address/0x4bCBA1316C95B812cC014CA18C08971Ce1C10861#code)      |
| BalancerVault  | [0x1aB16CB0cb0e5520e0C081530C679B2e846e4D37](https://goerli.etherscan.io/address/0x1aB16CB0cb0e5520e0C081530C679B2e846e4D37#code)      

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
yarn install # or npm install

# Run basic tests suite against a local chain. This is all tests ending in .t.sol
# All tests run with underlying, target and stake aas ERC20 compliant tokens wth 18 decimals
yarn test

# Run mainnet tests (against a mainnet fork). This is all tests endng in .tm.sol
# All tests run with underlying, target and stake aas ERC20 compliant tokens wth 18 decimals
# (unless they use existing tokens)
yarn test:mainnet

# Run full local test suite (against a local chain) which includes combinations for:
# 1. ERC4626, ERC20 and non-ERC20 for target, underlying and stake
# 2. 6, 8 and 18 decimals for target, underlying and stake
yarn test:fuzz
```

### Format

```bash
# Run linter
yarn lint

# Run formatter
yarn fix
```

### Environment

1. Create a local `.env` file in the root directory of this project
2. Set `ALCHEMY_KEY` to a valid Alchemy API key
3. Set `MNEMONIC` to a valid seed phrase for deployments
4. Set `ETHERSCAN_API_KEY` to a valid Etherscan API key (used for verification)

### Deployment & upgrades

This repo uses [hardhat deploy](https://github.com/wighawag/hardhat-deploy) for replicable deployments. To create a new deployment:

```bash
# Navigate to the `deployments` package
cd pkg/deployments

# Deploy the protocol with mocks on a forked network
yarn deploy:hardhat-fork:sim

# Deploy the protocol with production config on a forked network
yarn deploy:hardhat-fork:sim

# Deploy the protocol with mocks on a live network
yarn hardhat deploy --network <network> --tags scenario:simulated

# Deploy the protocol with production config on a live network
yarn hardhat deploy --network <network> --tags scenario:prod
```

New contracts or contract modifications/upgrades are deployed and configured using a Hardhat [tasks](https://hardhat.org/guides/create-task.html). Tasks live in the `[tasks](https://github.com/sense-finance/sense-v1/tree/dev/pkg/deployments/tasks)` directory of the `deployment` package of the sense-v1 repository.

Aside from deployment, tasks are also responsible for ensuring:

* other contracts are aware of the new contract,
* the newly deployed contract is aware of existing contracts, and
* permissions are set appropriately.
    
    IMPORTANT:
    After configuring every new contract, these permissions must be set:
    ```solidity
    // Set the multisig as trusted
    newContract.setIsTrusted(multisig, true)
    
    // Set the deployer as non-trusted
    newContract.setIsTrusted(deployer, false)
    ```
* contracts are verified on Etherscan

To create a new task:

1. Create the task folder and its related files:

    ```bash
    # Navigate to the `deployments/tasks` folder
    cd pkg/deployments/tasks

    # Create a new folder with a name following the YYYYMMYY-TASK_NAME pattern
    mkdir YYYYMMYY-TASK_NAME
    ```

    Each task folder must contain 2 files:
    - `index.js`: where the hardhat task logic lives (what should the task do)
    - `input.js` which contains all the input addresses that the task needs in order to be executed

    Optionally (though most likely), the task will need to instantiate some contracts, requiring the ABIs of them. Create a `pkg/deployments/tasks/YYYYMMYY-TASK_NAME/abi` folder to store these ABIs.

2. Add the task into `pkg/deployments/tasks/index.js`.

3. Run the new task:

    ```bash
    # Navigate to the `deployments/tasks` folder
    cd pkg/deployments/tasks

    # Execute hardhat task
    yarn hardhat 20220517-long-wsteth-adapter --network mainnet
    ```

    *It is important that you first test that your task does what's intended by running it on a fork from mainnet and, optionally, on Goerli. Just use `--network hardhat` or `--network goerli` when executing the command.*

4. Add *output* files into task folder:

    After succesfully executing the task, Hardhat would have saved the resulting deployments (contract addresses along their abi, bytecode, metadata...) on `pkg/deployments/deployments`. **Move that folder inside `pkg/deployments/tasks/YYYYMMYY-TASK_NAME` and rename it to `output`**.

5. Commit and push code to Github.

*NOTE: check existing tasks as a guide on how to create and execute a new one.*

## Security

Sense-v1 has been audited by four, independent smart contract auditors, ranked by recency:

1. 2022-02/03 Space AMM - [Fixed Point Solutions (Kurt Barry)](https://github.com/sense-finance/sense-v1/blob/dev/audits/fps/2022-03-15-twap.pdf)
2. 2022-03 Sense - [ABDK](https://github.com/sense-finance/sense-v1/tree/dev/audits/abdk)
3. 2022-01 Sense & Space AMM - [Spearbit](https://github.com/sense-finance/sense-v1/blob/dev/audits/spearbit/2022-01-21.pdf)
4. 2021-11/12 Sense - [Fixed Point Solutions (Kurt Barry)](https://github.com/sense-finance/sense-v1/blob/dev/audits/fps/2022-03-15.pdf)
5. 2021-11 Sense - [ABDK](https://github.com/sense-finance/sense-v1/tree/dev/audits/abdk)
6. 2022-11 Sense - [Peckshield](https://github.com/sense-finance/sense-v1/blob/dev/audits/peckshield/2021-11-07.pdf)

### Bug Bounties

Sense has an [active bug bounty on ImmuneFi](https://immunefi.com/bounty/sense/), with up to $50,000 for reporting a bug in deployed contracts & the Sense Portal.

## Conventions

### Branching

Right now, we are using `dev` and  `main` branches.

- `main` represents the contracts live on `mainnet` and all testnets
- `dev` is for the newest version of contracts, and is reserved for deployments to `goerli`

When a new version of the contracts makes its way through the testnet, it eventually becomes promoted in `main`, with [semver](https://semver.org/) reflecting contract changes in the `major` or `minor` portion of the version (depending on backwards compatibility).
