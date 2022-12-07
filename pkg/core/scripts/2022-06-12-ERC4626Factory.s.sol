// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

import { AddressBook } from "./AddressBook.sol";
import { AddressGuru } from "./AddressGuru.sol";
import { Divider } from "../../src/Divider.sol";
import { Periphery } from "../../src/Periphery.sol";
import { ERC4626Factory } from "../../src/adapters/abstract/factories/ERC4626Factory.sol";
import { ERC4626Adapter } from "../../src/adapters/abstract/erc4626/ERC4626Adapter.sol";
import { BaseFactory } from "../../src/adapters/abstract/factories/BaseFactory.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { DateTime } from "@auto-roller/src/external/DateTime.sol";

contract ERC4626FactoryScript is Script {
    using stdJson for string;
    using stdStorage for StdStorage;

    function run() external {
        uint256 chainId = block.chainid;
        console.log("Chain ID:", chainId);

        AddressGuru addressGuru = new AddressGuru();
        // Broadcast following txs from deployer
        vm.startBroadcast();

        console.log("\nDeploying from:", msg.sender);

        address senseMultisig = chainId == AddressBook.MAINNET || chainId == AddressBook.FORK ? AddressBook.SENSE_MULTISIG : msg.sender;

        console.log("-------------------------------------------------------");
        console.log("Deploy factory");
        console.log("-------------------------------------------------------");

        // TODO: read factoryParms from input.json file (can't do this right now because of a foundry bug when parsing JSON)
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: addressGuru.weth(),
            oracle: addressGuru.oracle(),
            ifee: 1e15, // 0.1%
            stakeSize: 25e16, // 0.25 WETH
            minm: 2629800, // 1 month
            maxm: 315576000, // 10 years
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
        if (chainId == AddressBook.FORK || chainId == AddressBook.GOERLI) {
            
            if (chainId == AddressBook.FORK) {
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

            if (chainId == AddressBook.FORK) {
                // Broadcast following txs from deployer
                vm.startBroadcast(msg.sender);

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
                    ERC4626Adapter adptr = ERC4626Adapter(adapter);
                    console.log("  -> scale: %s", adptr.scale());

                    (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
                    console.log("  -> adapter guard: %s", guard);

                    console.log("- Approve Periphery to pull stake...");
                    ERC20 stake = ERC20(factoryParams.stake);
                    stake.approve(address(periphery), type(uint256).max);

                    console.log("- Mint stake tokens...");
                    setTokenBalance(msg.sender, factoryParams.stake, factoryParams.stakeSize);

                    // get next month maturity
                    (uint256 year, uint256 month, ) = DateTime.timestampToDate(DateTime.addMonths(block.timestamp, 2));
                    uint256 maturity = DateTime.timestampFromDateTime(year, month, 1 /* top of the month */, 0, 0, 0);

                    // deploy Series
                    console.log("\n- Sponsor Series for %s @ %s with maturity %s", adptr.name(), address(t), maturity);
                    periphery.sponsorSeries(adapter, maturity, false);
                    console.log("\n-------------------------------------------------------");
                }
            }
        }

        if (msg.sender != senseMultisig) {
            // Unset deployer and set multisig as trusted address
            console.log("\n- Set multisig as trusted address of Factory");
            factory.setIsTrusted(senseMultisig, true);

            console.log("\n- Unset deployer as trusted address of Factory");
            factory.setIsTrusted(msg.sender, false);
        }

        if (chainId == AddressBook.MAINNET) {
            console.log("-------------------------------------------------------");
            console.log("ACTIONS TO BE DONE ON DEFENDER: ");
            console.log("1. Set factory on Periphery");
            console.log("2. Set factory as trusted on Divider");
            console.log("3. Deploy adapters on Periphery (if needed)");
            console.log("4. For each adapter, sponsor Series on Periphery");
            console.log("5. For each series, run capital seeder");
        }

        vm.stopBroadcast();
    }

    function setTokenBalance(address who, address token, uint256 amt) internal {
        stdstore
            .target(token)
            .sig(ERC20(token).balanceOf.selector)
            .with_key(who)
            .checked_write(amt);
    }
}