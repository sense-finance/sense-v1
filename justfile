## ---- Config ----

# load .env file
set dotenv-load

# pass recipe args as positional arguments to commands
set positional-arguments

## ---- Environment ----

## for mainnet tests and deployments
ALCHEMY_KEY := env_var("ALCHEMY_KEY")
MAINNET_RPC := "https://eth-mainnet.alchemyapi.io/v2/" + ALCHEMY_KEY
MNEMONIC    := env_var("MNEMONIC")

## for dapp and hevm
DAPP_SOLC_VERSION   := "0.8.6"
DAPP_BUILD_OPTIMIZE := "1"
DAPP_COVERAGE       := "1"
# when developing we only want to fuzz briefly
DAPP_TEST_FUZZ_RUNS := "100"
# user with DAI
DAPP_TEST_ADDRESS := "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"
# user with cDAI
DAPP_REMAPPINGS   := remappings-from-pkg-deps
# DAPP_TEST_ADDRESS := "0xb1e9d641249a2033c37cf1c241a01e717c2f6c76"

# export just vars as env vars
set export

## ---- Recipes ----

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

# build using dapp
build: && _timer
	cd {{ invocation_directory() }}; dapp build

# debug and open TTY debugger using dapp
debug:
	cd {{ invocation_directory() }}; dapp debug


# turbo-build: && timer
# 	cd {{ invocation_directory() }}; dapptools-rs --bin dapp \
# 		build --lib-paths {{ lib-paths-from-pkg-deps }}

# default test scripts
test: test-local

# turbo-test: turbo-test-local

# run local dapp tests (all files with the extension .t.sol)
test-local *commands="": && _timer
	cd {{ invocation_directory() }}; dapp test -m ".t.sol" {{ commands }}

# run mainnet fork dapp tests (all files with the extension .tm.sol)
test-mainnet *commands="": && _timer
	cd {{ invocation_directory() }}; dapp test --rpc-url {{ MAINNET_RPC }} -m ".tm.sol" {{ commands }}

# run turbo dapp tests
# turbo-test-local *commands="": && timer
# 	cd {{ invocation_directory() }}; dapptools-rs --bin dapp test \
# 		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 5 {{ commands }}
# turbo-test-mainnet *commands="": && timer
# 	cd {{ invocation_directory() }}; dapptools-rs --bin dapp test \
# 		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 5 \
# 		--fork-url {{ MAINNET_RPC }} {{ commands }}


# default gas snapshot script
gas-snapshot: gas-snapshot-local

# get gas snapshot from local tests and save it to a file
gas-snapshot-local:
	cd {{ invocation_directory() }}; \
	dapp test --fuzz-runs 0 | grep 'gas:' | cut -d " " -f 2-4 >> \
	{{ justfile_directory() }}/.gas-snapshot-$( \
		cat {{ invocation_directory() }}/package.json | jq .name | tr -d '"' | cut -d"/" -f2- \
	)

# get gas snapshot from mainnet tests and save it to a file
gas-snapshot-mainnet:
	cd {{ invocation_directory() }}; \
	dapp test --rpc-url {{ MAINNET_RPC }} --fuzz-runs 0 | grep 'gas:' | cut -d " " -f 2-4 >> \
	{{ justfile_directory() }}/.gas-snapshot-$( \
		cat {{ invocation_directory() }}/package.json | jq .name | tr -d '"' | cut -d"/" -f2- \
	)


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
	tr -d '[],"' | xargs | tr ' ' '\n' | sort | uniq | tr '\n' ' '
  ```