## ---- Config ----

# load .env file
set dotenv-load

# pass recipe args as positional arguments to commands
set positional-arguments

## ---- Environment ----

## for mainnet tests and deployments
ALCHEMY_KEY := env_var_or_default("ALCHEMY_KEY", "_gg7wSSi0KMBsdKnGVfHDueq6xMB9EkC")
MAINNET_RPC := "https://eth-mainnet.alchemyapi.io/v2/" + ALCHEMY_KEY
MNEMONIC    := env_var_or_default("MNEMONIC", "")
ETHERSCAN_API_KEY := env_var_or_default("ETHERSCAN_API_KEY", "")

DAPP_SOLC_VERSION   := "0.8.11"
DAPP_BUILD_OPTIMIZE := "1"

## forge testing configuration
DAPP_COVERAGE       := "1"
# when developing we only want to fuzz briefly
DAPP_TEST_FUZZ_RUNS := "100"
# user with DAI
DAPP_REMAPPINGS   := remappings-from-pkg-deps

# default mock target type is ERC20
FORGE_MOCK_NON_ERC20_TARGET := env_var_or_default("FORGE_MOCK_NON_ERC20_TARGET", "false")
# default mock underlying type is ERC20
FORGE_MOCK_NON_ERC20_UNDERLYING := env_var_or_default("FORGE_MOCK_NON_ERC20_UNDERLYING", "false")
# default mock stake type is ERC20
FORGE_MOCK_NON_ERC20_STAKE := env_var_or_default("FORGE_MOCK_NON_ERC20_STAKE", "false")

# default mock target type is non 4626  
FORGE_MOCK_4626_TARGET := env_var_or_default("FORGE_MOCK_4626_TARGET", "false")

# set mock target, underlying and stake to 18 decimals by default
FORGE_MOCK_TARGET_DECIMALS := env_var_or_default("FORGE_MOCK_TARGET_DECIMALS", "18")
FORGE_MOCK_UNDERLYING_DECIMALS := env_var_or_default("FORGE_MOCK_UNDERLYING_DECIMALS", "18")
FORGE_MOCK_STAKE_DECIMALS := env_var_or_default("FORGE_MOCK_STAKE_DECIMALS", "18")

# export just vars as env vars
set export

## ---- Installation ----

_default:
  just --list

## ---- Testing ----

turbo-test-match *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test --no-match-path "*.tm*" --match-test {{ exp }}

turbo-test-match-contract *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test --match-contract {{ exp }}

# run tests with 18 decimals
turbo-test-local *cmds="": && _timer
	@cd {{ invocation_directory() }}; forge test --no-match-path "*.tm*" {{ cmds }}

# run tests with 18 decimals and non-ERC20 target
turbo-test-local-non-erc20-target *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_NON_ERC20_TARGET="true"; \
		forge test --no-match-path "*.tm*" {{ cmds }}

# run tests with 18 decimals and non-ERC20 underlying
turbo-test-local-non-erc20-underlying *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_NON_ERC20_UNDERLYING="true"; \
		forge test --no-match-path "*.tm*" {{ cmds }}

# run tests with 18 decimals and non-ERC20 stake
turbo-test-local-non-erc20-stake *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_NON_ERC20_STAKE="true"; \
		forge test --no-match-path "*.tm*" {{ cmds }}

# run tests with 6 target & underlying decimals
turbo-test-local-6-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_TARGET_DECIMALS="6"; \
		export FORGE_MOCK_UNDERLYING_DECIMALS="6"; \
		forge test --no-match-path "*.tm*" {{ cmds }}

# run tests with 8 decimals for target & 6 decimals for underlying
turbo-test-local-greater-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_TARGET_DECIMALS="8"; \
		export FORGE_MOCK_UNDERLYING_DECIMALS="8"; \
		forge test --no-match-path "*.tm*" {{ cmds }}

# run tests with 6 decimals for target & 8 decimals for underlying
turbo-test-local-lower-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_TARGET_DECIMALS="6"; \
		export FORGE_MOCK_UNDERLYING_DECIMALS="8"; \
		forge test --no-match-path "*.tm*" {{ cmds }}

# run ERC4626 tests with 18 decimals target
turbo-test-local-4626 *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_4626_TARGET="true"; \
		forge test --match-path "**/*.t.sol" --no-match-path "**/Adapter.t.sol" {{ cmds }}

# run ERC4626 tests with 8 decimals target
turbo-test-local-4626-8-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_4626_TARGET="true"; \
		export FORGE_MOCK_UNDERLYING_DECIMALS="8"; \
		export FORGE_MOCK_TARGET_DECIMALS="8"; \
		forge test --match-path "**/*.t.sol" --no-match-path "**/Adapter.t.sol" {{ cmds }}

turbo-test-local-4626-match *exp="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_4626_TARGET="true"; \
		forge test --match-path "**/*.t.sol" --no-match-path "**/Adapter.t.sol" --match-test {{ exp }}

turbo-test-mainnet: && _timer
	@cd {{ invocation_directory() }}; forge test --match-path "*.tm*" --fork-url {{ MAINNET_RPC }}

turbo-test-mainnet-match *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test --match-path "*.tm*" --fork-url {{ MAINNET_RPC }} --match-test {{ exp }}

turbo-test-mainnet-match-contract *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test --fork-url {{ MAINNET_RPC }} --match-contract {{ exp }}

# run for all possible combinations between ERC20 and non-ERC20 target, underlying and stake and 6, 8 and 18 decimals
# also run, for ERC4626 target, all possible combinations between 6, 8 and 18 target (and underlying) decimals
turbo-test-local-all *cmds="": && _timer
	for c in --target\ {true,false}\ --underlying\ {true,false}\ --stake\ {true,false}\ --tDecimals\ {6,8,18}\ --uDecimals\ {6,8,18}\ --sDecimals\ {6,8,18} ; do \
		IFS=' ' \
		read -ra combination <<< "$c"; \
		echo "Target is ${combination[7]} decimals and is ERC20: ${combination[1]}"; \
		echo "Underlying is ${combination[9]} decimals and is ERC20: ${combination[3]}"; \
		echo "Stake is ${combination[11]} decimals and is ERC20: ${combination[5]}"; \
		echo "\n"; \
		cd {{ invocation_directory() }}; \
			export FORGE_MOCK_NON_ERC20_TARGET=${combination[1]}; \
			export FORGE_MOCK_NON_ERC20_UNDERLYING=${combination[3]}; \
			export FORGE_MOCK_NON_ERC20_STAKE=${combination[5]}; \
			export FORGE_MOCK_TARGET_DECIMALS=${combination[7]}; \
			export FORGE_MOCK_UNDERLYING_DECIMALS=${combination[9]}; \
			export FORGE_MOCK_STAKE_DECIMALS=${combination[11]}; \
			forge test --no-match-path "*.tm*" {{ cmds }}; \
	done

	for c in --tDecimals\ {6,8,18}\ ; do \
		IFS=' ' \
		read -ra combination <<< "$c"; \
		echo "Target is ${combination[1]} decimals and is ERC4626"; \
		echo "Underlying is ${combination[1]} decimals (same as target) and is ERC20"; \
		echo "\n"; \
		cd {{ invocation_directory() }}; \
			export FORGE_MOCK_4626_TARGET="true"; \
			export FORGE_MOCK_TARGET_DECIMALS=${combination[1]}; \
			export FORGE_MOCK_UNDERLYING_DECIMALS=${combination[1]}; \
			forge test --no-match-path "*.tm*" {{ cmds }}; \
	done

## ---- Gas Metering ----

gas-snapshot: && _timer
	@cd {{ invocation_directory() }}; forge snapshot --no-match-path "*.tm*"

gas-snapshot-diff: && _timer
	@cd {{ invocation_directory() }}; forge snapshot --no-match-path "*.tm*" --diff

## ---- Appendix ----

start_time := `date +%s`
_timer:
    @echo "Task executed in $(($(date +%s) - {{ start_time }})) seconds"

remappings-from-pkg-deps := ```
    cat pkg/*/package.json  |
    jq 'select(.dependencies != null) | .dependencies | to_entries | map([.key + "/", "../../node_modules/" + .key + "/"] | join("="))' |
    tr -d '[],"' | xargs | tr ' ' '\n' | sort | uniq
```

lib-paths-from-pkg-deps := ```
    cat pkg/*/package.json |
    jq 'select(.dependencies != null) | .dependencies | to_entries | map("../../node_modules/" + .key + "/")' |
    tr -d '[],"' | xargs | tr ' ' '\n' | sort | uniq | awk '{print "--lib-paths " $0}' | tr '\n' ' '
  ```