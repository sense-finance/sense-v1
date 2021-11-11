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

## dependencies
install: npm svm solc
npm:
	yarn install

# install solc version manager
svm:
	cargo install svm-rs
solc:
	svm use {{ DAPP_SOLC_VERSION }}

## build & debug
build: && timer
	cd {{ invocation_directory() }}; dapp build
debug: && timer
	cd {{ invocation_directory() }}; dapp debug
# turbo-build: && timer
# 	cd {{ invocation_directory() }}; dapptools-rs --bin dapp \
# 		build --lib-paths {{ lib-paths-from-pkg-deps }}

# default test scripts
test: test-local
turbo-test: turbo-test-local

# run dapp tests
test-local *commands="": && timer
	cd {{ invocation_directory() }}; dapp test -m ".t.sol" {{ commands }}
test-mainnet *commands="": && timer
	cd {{ invocation_directory() }}; dapp test --rpc-url {{ MAINNET_RPC }} -m ".tm.sol" {{ commands }}

# run turbo dapp tests
# turbo-test-local *commands="": && timer
# 	cd {{ invocation_directory() }}; dapptools-rs --bin dapp test \
# 		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 5 {{ commands }}
# turbo-test-mainnet *commands="": && timer
# 	cd {{ invocation_directory() }}; dapptools-rs --bin dapp test \
# 		--lib-paths {{ lib-paths-from-pkg-deps }} --verbosity 5 \
# 		--fork-url {{ MAINNET_RPC }} {{ commands }}

## ---- Appendix ----

start_time := `date +%s`
timer:
	@echo "Task executed in $(($(date +%s) - {{ start_time }})) seconds"

remappings-from-pkg-deps := ```
	for dir in ./pkg/*; do
		cat "$dir"/package.json  | 
		jq 'select(.dependencies != null) | .dependencies | to_entries | map([.key + "/", "../../node_modules/" + .key + "/"] | join("="))' | \
		tr -d '[],"' | xargs | tr ' ' '\n' >> tmp
	done
	remappings=$(cat tmp | sort | uniq)
	rm tmp
	echo "$remappings"
```

lib-paths-from-pkg-deps := ```
	for dir in ./pkg/*; do
		cat "$dir"/package.json | \
		jq 'select(.dependencies != null) | .dependencies | to_entries | map("../../node_modules/" + .key + "/")' | \
		tr -d '[],"' | xargs >> tmp
	done
	lib_paths=$(cat tmp | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
	rm tmp
	echo "$lib_paths"
  ```