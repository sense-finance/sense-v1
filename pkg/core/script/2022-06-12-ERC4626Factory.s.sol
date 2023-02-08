// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import "forge-std/StdCheats.sol";

import { AddressGuru, Constants } from "@sense-finance/v1-utils/addresses/AddressGuru.sol";
import { Divider } from "@sense-finance/v1-core/Divider.sol";
import { Periphery } from "@sense-finance/v1-core/Periphery.sol";
import { ERC4626Factory } from "@sense-finance/v1-core/adapters/abstract/factories/ERC4626Factory.sol";
import { ERC4626Factory } from "@sense-finance/v1-core/adapters/abstract/factories/ERC4626Factory.sol";
import { ERC4626Adapter } from "@sense-finance/v1-core/adapters/abstract/erc4626/ERC4626Adapter.sol";
import { BaseFactory } from "@sense-finance/v1-core/adapters/abstract/factories/BaseFactory.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { DateTime } from "@auto-roller/src/external/DateTime.sol";

contract ERC4626FactoryScript is Script, StdCheats {
    uint256 public mainnetFork;
    string public MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function run() external {
        uint256 chainId = block.chainid;
        console.log("Chain ID:", chainId);

        if (chainId == Constants.FORK) {
            mainnetFork = vm.createFork(MAINNET_RPC_URL);
            vm.selectFork(mainnetFork);
        }

        AddressGuru addressGuru = new AddressGuru();

        // Get deployer from mnemonic
        string memory deployerMnemonic = vm.envString("MNEMONIC");
        uint256 deployerPrivateKey = vm.deriveKey(deployerMnemonic, 0);
        address deployer = vm.rememberKey(deployerPrivateKey);
        console.log("Deploying from:", deployer);
        
        address senseMultisig = chainId == Constants.GOERLI ? deployer : addressGuru.multisig();
        console.log("Sense multisig is:", senseMultisig);

        console.log("-------------------------------------------------------");
        console.log("Deploy factory");
        console.log("-------------------------------------------------------");

        // Broadcast following txs from deployer
        vm.startBroadcast(deployer);

        // TODO: read factoryParms from input.json file (can't do this right now because of a foundry bug when parsing JSON)
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            oracle: addressGuru.oracle(),
            stake: addressGuru.weth(),
            stakeSize: 0.25e18, // 0.25 WETH
            minm: 2629800, // 1 month
            maxm: 315576000, // 10 years
            ifee: 1e15, // 0.001%
            mode: 0, // 0 = monthly
            tilt: 0,
            guard: 100000e18 // $100'000
        });

        ERC4626Factory factory = new ERC4626Factory(
            addressGuru.divider(),
            senseMultisig,
            senseMultisig,
            factoryParams
        );
        console.log("- Factory deployed @ %s", address(factory));
        vm.stopBroadcast();

        // Mainnet would require multisig to make these calls
        if (chainId == Constants.FORK || chainId == Constants.GOERLI) {
            
            if (chainId == Constants.FORK) {
                console.log("- Fund multisig to be able to make calls from that address");
                vm.deal(senseMultisig, 1 ether);
            }

            Periphery periphery = Periphery(addressGuru.periphery());
            Divider divider = Divider(addressGuru.divider());

            // Broadcast following txs from multisig
            vm.startBroadcast(senseMultisig);

            console.log("- Add support to Periphery");
            periphery.setFactory(address(factory), true);

            console.log("- Set factory as trusted address of Divider so it can call setGuard() \n");
            divider.setIsTrusted(address(factory), true);

            vm.stopBroadcast();

            if (chainId == Constants.FORK) {
                // Broadcast following txs from deployer
                vm.startBroadcast(deployer);

                console.log("-------------------------------------------------------");
                console.log("Deploy adapters for factory");
                console.log("-------------------------------------------------------");

                // TODO: read targets from input.json file (can't do this right now because of a foundry bug when parsing JSON)
                address[1] memory targets = [addressGuru.BB_wstETH4626()];

                for(uint i = 0; i < targets.length; i++){
                    ERC20 t = ERC20(targets[i]);
                    string memory name = t.name();

                    console.log("%s", name);
                    console.log("-------------------------------------------------------\n");

                    console.log("- Add target %s to the whitelist", name);
                    factory.supportTarget(address(t), true);

                    console.log("- Deploy adapter with target %s @ %s via factory", name, address(t));
                    address adapter = periphery.deployAdapter(address(factory), address(t), "");
                    console.log("- %s adapter address: %s", name, adapter);

                    console.log("- Can call scale value");
                    console.log("  -> scale: %s", ERC4626Adapter(adapter).scale());

                    {
                        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
                        console.log("  -> adapter guard: %s", guard);
                    }

                    console.log("- Approve Periphery to pull stake...");
                    ERC20(factoryParams.stake).approve(address(periphery), type(uint256).max);

                    console.log("- Mint stake tokens...");
                    deal(factoryParams.stake, deployer, factoryParams.stakeSize);

                    // get next month maturity
                    (uint256 year, uint256 month, ) = DateTime.timestampToDate(DateTime.addMonths(block.timestamp, 2));
                    uint256 maturity = DateTime.timestampFromDateTime(year, month, 1 /* top of the month */, 0, 0, 0);

                    // deploy Series
                    console.log("\n- Sponsor Series for %s @ %s with maturity %s", ERC4626Adapter(adapter).name(), address(t), maturity);
                    periphery.sponsorSeries(adapter, maturity, false);
                    console.log(" Series successfully sponsored!");

                    console.log("\n-------------------------------------------------------");
                }
            }
        }

        if (deployer != senseMultisig) {
            vm.startBroadcast(deployer);

            // Unset deployer and set multisig as trusted address
            console.log("- Set multisig as trusted address of Factory");
            factory.setIsTrusted(senseMultisig, true);

            console.log("- Unset deployer as trusted address of Factory");
            factory.setIsTrusted(deployer, false);

            vm.stopBroadcast();
        }

        if (chainId == Constants.MAINNET) {
            console.log("-------------------------------------------------------");
            console.log("ACTIONS TO BE DONE ON DEFENDER: ");
            console.log("1. Set factory on Periphery");
            console.log("2. Set factory as trusted on Divider");
            console.log("3. Deploy adapters on Periphery (if needed)");
            console.log("4. For each adapter, sponsor Series on Periphery");
            console.log("5. For each series, run capital seeder");
        }
    }

}