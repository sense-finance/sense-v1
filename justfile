## ---- Config ----

# load .env file
set dotenv-load

# pass recipe args as positional arguments to commands
set positional-arguments

## ---- Environment ----

IS_NOT_4626 := "0x0000000000000000000000000000000000000000000000000000000000000000" # false
IS_4626 := "0x0000000000000000000000000000000000000000000000000000000000000001" # true
HEX_18 := "0x0000000000000000000000000000000000000000000000000000000000000012"
HEX_12 := "0x000000000000000000000000000000000000000000000000000000000000000c"
HEX_8  := "0x0000000000000000000000000000000000000000000000000000000000000008"
HEX_6  := "0x0000000000000000000000000000000000000000000000000000000000000006"

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
DAPP_TEST_ADDRESS := "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"
DAPP_REMAPPINGS   := remappings-from-pkg-deps
# default mock target type is non 4626  
FORGE_MOCK_4626_TARGET := env_var_or_default("FORGE_MOCK_4626_TARGET", IS_NOT_4626)
# set mock target to 18 decimals by default
FORGE_MOCK_TARGET_DECIMALS := env_var_or_default("FORGE_MOCK_TARGET_DECIMALS", HEX_18)
FORGE_MOCK_UNDERLYING_DECIMALS := env_var_or_default("FORGE_MOCK_UNDERLYING_DECIMALS", HEX_18)

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

# run tests with 6 target & underlying decimals
turbo-test-local-6-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_TARGET_DECIMALS={{ HEX_6 }}; \
		export FORGE_MOCK_UNDERLYING_DECIMALS={{ HEX_6 }}; \
		forge test --no-match-path "*.tm*" {{ cmds }}

# run tests with 8 decimals for target & 6 decimals for underlying
turbo-test-local-greater-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_TARGET_DECIMALS={{ HEX_8 }}; \
		export FORGE_MOCK_UNDERLYING_DECIMALS={{ HEX_6 }}; \
		forge test --no-match-path "*.tm*" {{ cmds }}

# run tests with 6 decimals for target & 8 decimals for underlying
turbo-test-local-lower-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_TARGET_DECIMALS={{ HEX_6 }}; \
		export FORGE_MOCK_UNDERLYING_DECIMALS={{ HEX_8 }}; \
		forge test --no-match-path "*.tm*" {{ cmds }}

# run ERC4626 tests with 18 decimals target
turbo-test-local-4626 *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_4626_TARGET={{ IS_4626 }}; \
		forge test --match-path "**/*.t.sol" --no-match-path "**/Adapter.t.sol" {{ cmds }}

# run ERC4626 tests with 6 decimals target
turbo-test-local-4626-8-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_4626_TARGET={{ IS_4626 }}; \
		export FORGE_MOCK_UNDERLYING_DECIMALS={{ HEX_8 }}; \
		export FORGE_MOCK_TARGET_DECIMALS={{ HEX_8 }}; \
		forge test --match-path "**/*.t.sol" --no-match-path "**/Adapter.t.sol" {{ cmds }}

turbo-test-local-4626-match *exp="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_4626_TARGET={{ IS_4626 }}; \
		forge test --match-path "**/*.t.sol" --no-match-path "**/Adapter.t.sol" --match-test {{ exp }}

turbo-test-mainnet: && _timer
	@cd {{ invocation_directory() }}; forge test --match-path "*.tm*" --fork-url {{ MAINNET_RPC }}

turbo-test-mainnet-match *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test --match-path "*.tm*" --fork-url {{ MAINNET_RPC }} --match-test {{ exp }}

turbo-test-mainnet-match-contract *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test --fork-url {{ MAINNET_RPC }} --match-contract {{ exp }}
## ---- Gas Metering ----

gas-snapshot: && _timer
	@cd {{ invocation_directory() }}; forge snapshot --no-match-path "*.tm*"

gas-snapshot-diff: && _timer
	@cd {{ invocation_directory() }}; forge snapshot --no-match-path "*.tm*" --diff

## ---- Appendix ----

start_time := `date +%s`
_timer:
    @echo "Task executed in $(($(date +%s) - {{ start_time }})) seconds"

# Solidity test ffi callback to get Target type and Target decimals for the base Mock Target token
_forge_mock_4626_target:
    @printf {{ FORGE_MOCK_4626_TARGET }}

_forge_mock_target_decimals:
    @printf {{ FORGE_MOCK_TARGET_DECIMALS }}

_forge_mock_underlying_decimals:
    @printf {{ FORGE_MOCK_UNDERLYING_DECIMALS }}

_forge_rpc_url:
    @printf {{ MAINNET_RPC }}

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