## ---- Config ----

# load .env file
set dotenv-load

# pass recipe args as positional arguments to commands
set positional-arguments

## ---- Environment ----

HEX_18 := "0x0000000000000000000000000000000000000000000000000000000000000012"
HEX_12 := "0x000000000000000000000000000000000000000000000000000000000000000c"
HEX_8  := "0x0000000000000000000000000000000000000000000000000000000000000008"
HEX_6  := "0x0000000000000000000000000000000000000000000000000000000000000006"

## for mainnet tests and deployments
ALCHEMY_KEY := env_var_or_default("ALCHEMY_KEY", "_gg7wSSi0KMBsdKnGVfHDueq6xMB9EkC")
MAINNET_RPC := "https://eth-mainnet.alchemyapi.io/v2/" + ALCHEMY_KEY
MNEMONIC    := env_var_or_default("MNEMONIC", "")

DAPP_SOLC_VERSION   := "0.8.11"
DAPP_BUILD_OPTIMIZE := "1"

## forge testing configuration
DAPP_COVERAGE       := "1"
# when developing we only want to fuzz briefly
DAPP_TEST_FUZZ_RUNS := "100"
# user with DAI
DAPP_TEST_ADDRESS := "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"
DAPP_REMAPPINGS   := remappings-from-pkg-deps
# set mock target to 18 decimals by default
FORGE_MOCK_TARGET_DECIMALS := env_var_or_default("FORGE_MOCK_TARGET_DECIMALS", HEX_18)
FORGE_MOCK_UNDERLYING_DECIMALS := env_var_or_default("FORGE_MOCK_UNDERLYING_DECIMALS", HEX_18)

# export just vars as env vars
set export

## ---- Installation ----

_default:
  just --list

## ---- Testing ----

# run turbo dapp tests
turbo-test-local *cmds="": && _timer
	@cd {{ invocation_directory() }}; forge test --no-match-path "*.tm*" {{ cmds }}

turbo-test-match *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test --no-match-path "*.tm*" --match-test {{ exp }}

turbo-test-local-greater-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_TARGET_DECIMALS={{ HEX_8 }}; \
		export FORGE_MOCK_UNDERLYING_DECIMALS={{ HEX_6 }}; \
		forge test --no-match-path ".*tm.*" {{ cmds }}

turbo-test-local-lower-decimal-val *cmds="": && _timer
	cd {{ invocation_directory() }}; \
		export FORGE_MOCK_TARGET_DECIMALS={{ HEX_6 }}; \
		export FORGE_MOCK_UNDERLYING_DECIMALS={{ HEX_8 }}; \
		forge test --no-match-path ".*tm.*" {{ cmds }}

turbo-test-mainnet: && _timer
	@cd {{ invocation_directory() }}; forge test --match-path "*.tm*" --fork-url {{ MAINNET_RPC }}

turbo-test-mainnet-match *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test --match-path "*.tm*" --fork-url {{ MAINNET_RPC }} --match-test {{ exp }}

## ---- Gas Metering ----

# default gas snapshot script
gas-snapshot: gas-snapshot-local

# get gas snapshot from local tests and save it to file
gas-snapshot-local:
    cd {{ invocation_directory() }}; \
    just turbo-test-local | grep 'gas:' | cut -d " " -f 2-4 | sort > \
    {{ justfile_directory() }}/gas-snapshots/.$( \
        cat {{ invocation_directory() }}/package.json | jq .name | tr -d '"' | cut -d"/" -f2- \
    )

forge-gas-snapshot: && _timer
	@cd {{ invocation_directory() }}; forge snapshot --no-match-path ".*tm.*"

forge-gas-snapshot-diff: && _timer
	@cd {{ invocation_directory() }}; forge snapshot --no-match-path ".*tm.*" --diff

## ---- Appendix ----

start_time := `date +%s`
_timer:
    @echo "Task executed in $(($(date +%s) - {{ start_time }})) seconds"

# Solidity test ffi callback to get Target decimals for the base Mock Target token
_forge_mock_target_decimals:
    @printf {{ FORGE_MOCK_TARGET_DECIMALS }}

_forge_mock_underlying_decimals:
    @printf {{ FORGE_MOCK_UNDERLYING_DECIMALS }}

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