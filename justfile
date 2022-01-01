## ---- Config ----

# load .env file
set dotenv-load

# pass recipe args as positional arguments to commands
set positional-arguments

## ---- Environment ----

HEX_18 := "0x0000000000000000000000000000000000000000000000000000000000000012"
HEX_8  := "0x0000000000000000000000000000000000000000000000000000000000000008"

## for mainnet tests and deployments
ALCHEMY_KEY := env_var_or_default("ALCHEMY_KEY", "_gg7wSSi0KMBsdKnGVfHDueq6xMB9EkC")
MAINNET_RPC := "https://eth-mainnet.alchemyapi.io/v2/" + ALCHEMY_KEY
MNEMONIC    := env_var_or_default("MNEMONIC", "")

DAPP_SOLC_VERSION   := "0.8.6"
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


# export just vars as env vars
set export

## ---- Installation ----

_default:
  just --list

# install dependencies
install: npm dapp

# install npm dependencies
npm:
	yarn install

# install dapptools
dapp:
	curl -L https://nixos.org/nix/install | sh
	curl https://dapp.tools/install | sh

# install forge
forge:
	cargo install --git https://github.com/gakonst/dapptools-rs --locked


## ---- Building ----

# build using dapp
build: && _timer
	cd {{ invocation_directory() }}; dapp build

build-solc7: && _timer
	cd {{ invocation_directory() }}; dapp --use solc:0.7.5 build

turbo-build: && _timer
	@cd {{ invocation_directory() }}; forge build --lib-paths {{ lib-paths-from-pkg-deps }} \
		--root {{ invocation_directory() }}

turbo-build-dir *dir="":
	@cd {{ invocation_directory() }}; cd {{ dir }}; forge build --lib-paths {{ lib-paths-from-pkg-deps }} \
		--root {{ dir }} >> /dev/null; printf 0x00

# debug and open dapp's TTY debugger
debug:
	cd {{ invocation_directory() }}; dapp debug

## ---- Testing ----

# default test scripts
test: test-local
test-solc7: test-local-solc7

# run local dapp tests (all files with the extension .t.sol)
test-local *cmds="": && _timer
	cd {{ invocation_directory() }}; dapp test -m ".t.sol" {{ cmds }}

test-local-solc7 *cmds="": && _timer
	cd {{ invocation_directory() }}; dapp --use solc:0.7.5 test -m ".t.sol" {{ cmds }}

# run mainnet fork dapp tests (all files with the extension .tm.sol)
test-mainnet *cmds="": && _timer
	@cd {{ invocation_directory() }}; dapp test --rpc-url {{ MAINNET_RPC }} -m ".tm.sol" {{ cmds }}

# run turbo dapp tests
turbo-test-local *cmds="": && _timer
	@cd {{ invocation_directory() }}; forge test \
		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 3 --force --root {{ invocation_directory() }} \
		--ffi -m "^test(M(a[^i]|[^a])|[^M])" {{ cmds }}

turbo-test-local-no-fuzz *cmds="": && _timer
	@cd {{ invocation_directory() }}; forge test \
		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 3 --force --root {{ invocation_directory() }} \
		--ffi -m "^test((M|F)((a|u)[^iz]|[^au])|[^MF])" {{ cmds }}

turbo-test-local-8-decimal-target *cmds="": && _timer
	cd {{ invocation_directory() }}; export FORGE_MOCK_TARGET_DECIMALS={{ HEX_8 }}; forge test \
		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 3 --force --root {{ invocation_directory() }} \
		--ffi -m "^test(M(a[^i]|[^a])|[^M])" {{ cmds }}

turbo-test-mainnet: && _timer
	@cd {{ invocation_directory() }}; forge test \
		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 3 --force --root {{ invocation_directory() }} \
		--ffi --fork-url {{ MAINNET_RPC }} -m "^testMainnet"

turbo-test-match *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test \
		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 3 --force --root {{ invocation_directory() }} \
		--ffi -m {{ exp }}

turbo-test-mainnet-match *exp="": && _timer
	@cd {{ invocation_directory() }}; forge test \
		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 3 --force --root {{ invocation_directory() }} \
		--ffi --fork-url {{ MAINNET_RPC }} -m {{ exp }}

## ---- Gas Metering ----

# default gas snapshot script
gas-snapshot: gas-snapshot-local

# get gas snapshot from local tests and save it to file
gas-snapshot-local:
	cd {{ invocation_directory() }}; \
	just turbo-test-local-no-fuzz | grep 'gas:' | cut -d " " -f 2-4 | sort > \
	{{ justfile_directory() }}/gas-snapshots/.$( \
		cat {{ invocation_directory() }}/package.json | jq .name | tr -d '"' | cut -d"/" -f2- \
	)

forge-gas-snapshot: && _timer
	@cd {{ invocation_directory() }}; forge snapshot \
		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 3 --force --root {{ invocation_directory() }} \
		--ffi -m "^test((M|F)((a|u)[^iz]|[^au])|[^MF])"

forge-gas-snapshot-diff: && _timer
	@cd {{ invocation_directory() }}; forge snapshot --diff \
		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 1 --force --root {{ invocation_directory() }} \
		--ffi -m "^test((M|F)((a|u)[^iz]|[^au])|[^MF])"

## ---- Appendix ----

start_time := `date +%s`
_timer:
	@echo "Task executed in $(($(date +%s) - {{ start_time }})) seconds"

# Solidity test ffi callback to get Target decimals for the base Mock Target token
_forge_mock_target_decimals:
	@printf {{ FORGE_MOCK_TARGET_DECIMALS }}

remappings-from-pkg-deps := ```
	cat pkg/*/package.json  |
	jq 'select(.dependencies != null) | .dependencies | to_entries | map([.key + "/", "../../node_modules/" + .key + "/"] | join("="))' |
	tr -d '[],"' | xargs | tr ' ' '\n' | sort | uniq
```

lib-paths-from-pkg-deps := ```
	cat pkg/*/package.json |
	jq 'select(.dependencies != null) | .dependencies | to_entries | map("../../node_modules/" + .key + "/")' |
	tr -d '[],"' | xargs | tr ' ' '\n' | sort | uniq | tr '\n' ' '
  ```