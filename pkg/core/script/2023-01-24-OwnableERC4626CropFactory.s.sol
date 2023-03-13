// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import "forge-std/StdCheats.sol";

import { AddressGuru, Constants } from "@sense-finance/v1-utils/addresses/AddressGuru.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { AddressBookGoerli } from "@sense-finance/v1-utils/addresses/AddressBookGoerli.sol";
import { Divider } from "@sense-finance/v1-core/Divider.sol";
import { Periphery } from "@sense-finance/v1-core/Periphery.sol";
import { OwnableERC4626CropFactory } from "@sense-finance/v1-core/adapters/abstract/factories/OwnableERC4626CropFactory.sol";
import { OwnableERC4626CropAdapter } from "@sense-finance/v1-core/adapters/abstract/erc4626/OwnableERC4626CropAdapter.sol";
import { BaseFactory } from "@sense-finance/v1-core/adapters/abstract/factories/BaseFactory.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { DateTime } from "@auto-roller/src/external/DateTime.sol";
import { AutoRoller, OwnedAdapterLike } from "@auto-roller/src/AutoRoller.sol";
import { AutoRollerFactory } from "@auto-roller/src/AutoRollerFactory.sol";
import { PingPongClaimer } from "@sense-finance/v1-core/adapters/implementations/claimers/PingPongClaimer.sol";
import { RewardsDistributor } from "@morpho/contracts/common/rewards-distribution/RewardsDistributor.sol";
import { Utils } from "../utils/Utils.sol";

contract OwnableERC4626CropFactoryScript is Script, StdCheats {
    uint256 public chainId;
    uint256 public mainnetFork;
    string public MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    address public deployer;
    

    function run() external {
        chainId = block.chainid;
        console.log("Chain ID:", chainId);

        if (chainId == Constants.FORK) {
            mainnetFork = vm.createFork(MAINNET_RPC_URL);
            vm.selectFork(mainnetFork);
        }

        AddressGuru addressGuru = new AddressGuru();
        Utils utils = new Utils();

        // Get deployer from mnemonic
        string memory deployerMnemonic = vm.envString("MNEMONIC");
        uint256 deployerPrivateKey = vm.deriveKey(deployerMnemonic, 0);
        deployer = vm.rememberKey(deployerPrivateKey);
        console.log("Deploying from:", deployer);
        
        address senseMultisig = chainId == Constants.GOERLI ? deployer : addressGuru.multisig();
        console.log("Sense multisig is:", senseMultisig);

        console.log("-------------------------------------------------------");
        console.log("Deploy Ownable ERC4626 Crop Factory");
        console.log("-------------------------------------------------------");

        // TODO: read factoryParms from input.json file (can't do this right now because of a foundry bug when parsing JSON)
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            oracle: addressGuru.oracle(),
            stake: addressGuru.weth(),
            stakeSize: 0.25e18, // 0.25 WETH
            minm: 2629800, // 1 month
            maxm: 315576000, // 10 years
            ifee: utils.percentageToDecimal(0.05e18), // 0.05%
            mode: 0, // 0 = monthly
            tilt: 0,
            guard: 100000e18 // $100'000
        });

        address rlvFactory = chainId == Constants.FORK || chainId == Constants.MAINNET ? 0x3B0f35bDD6Da9e3b8513c58Af8Fdf231f60232E5 : 0x755E3FB62b8224AfCdF3cAb9816b1D76F0C81838; // TODO: replace for central address repo
        address divider = addressGuru.divider();
        vm.broadcast(deployer);
        OwnableERC4626CropFactory factory = new OwnableERC4626CropFactory(
            divider,
            senseMultisig,
            senseMultisig,
            factoryParams,
            rlvFactory
        );
        console.log("- Ownable ERC4626 Crop Factory deployed @ %s", address(factory));
        console.log("- Factory ifee: %s (%s %)", factoryParams.ifee, utils.decimalToPercentage(factoryParams.ifee));

        // Mainnet would require multisig to make these calls
        if (chainId == Constants.FORK) {
            console.log("- Fund multisig to be able to make calls from that address");
            vm.deal(senseMultisig, 1 ether);
        }

        Periphery periphery = Periphery(payable(addressGuru.periphery()));

        if (chainId != Constants.MAINNET) {
            // Broadcast following txs from multisig
            vm.startBroadcast(senseMultisig);

            console.log("- Add support to Periphery");
            periphery.setFactory(address(factory), true);

            console.log("- Set factory as trusted address of Divider so it can call setGuard() \n");
            Divider(divider).setIsTrusted(address(factory), true);

            vm.stopBroadcast();
        }
        
        console.log("- Deploy sanFRAX_EUR_Wrapper rewards claimer");
        vm.broadcast(deployer);
        PingPongClaimer claimer = new PingPongClaimer();

        // deploy the rewards distributor
        address reward = chainId == Constants.FORK || chainId == Constants.MAINNET ? AddressBook.ANGLE : AddressBookGoerli.DAI;
        RewardsDistributor distributor = _deployRewardsDistributor(reward);

        if (chainId != Constants.MAINNET) {
            // TODO: read targets from input.json file (can't do this right now because of a foundry bug when parsing JSON)
            address sanFRAX_EUR_Wrapper = AddressBookGoerli.cUSDC;

            // deploy ownable adapter
            OwnableERC4626CropAdapter adapter = _deployAdapter(periphery, factory, ERC20(sanFRAX_EUR_Wrapper), reward);

            // set claimer
            console.log("- Set claimer to adapter");
            vm.broadcast(senseMultisig); // broadcast following tx from multisig
            adapter.setClaimer(address(claimer));

            // create RLV
            AutoRoller rlv = _createRLV(adapter, AutoRollerFactory(rlvFactory), address(distributor));
            // roll first series
            _roll(rlv);
        }

        if (deployer != senseMultisig) {
            vm.startBroadcast(deployer);

            // Unset deployer and set multisig as trusted address
            console.log("- Set multisig as trusted address of Factory");
            factory.setIsTrusted(senseMultisig, true);

            console.log("- Unset deployer as trusted address of Factory");
            factory.setIsTrusted(deployer, false);

            console.log("- Unset deployer as trusted address of Factory");
            distributor.transferOwnership(senseMultisig);

            vm.stopBroadcast();
        }

        if (chainId == Constants.MAINNET) {
            console.log("-------------------------------------------------------");
            console.log("ACTIONS TO BE DONE ON DEFENDER: ");
            console.log("1. Set factory on Periphery (multisig)");
            console.log("2. Set factory as trusted on Divider (multisig)");
            console.log("3. Deploy ownable adapter on Periphery using factory (relayer)");
            console.log("4. Go back to script, and deploy the claimer");
            console.log("5. Set claimer to adapter (multisig)");
            console.log("6. Create RLV using AutoRollerFactory and the rewards distributor address (relayer)");
            console.log("7. Roll first series (relayer)");
        }
    }

    function _deployAdapter(Periphery periphery, OwnableERC4626CropFactory factory, ERC20 target, address reward) internal returns (OwnableERC4626CropAdapter adapter) {
        vm.startBroadcast(deployer);
        
        string memory name = target.name();
        console.log("-------------------------------------------------------\n");
        console.log("Deploy Ownable Adapter for %s", name);
        console.log("-------------------------------------------------------\n");

        console.log("- Add target %s to the whitelist", name);
        factory.supportTarget(address(target), true);

        console.log("- Deploy adapter with target %s @ %s via factory", name, address(target));
        adapter = OwnableERC4626CropAdapter(periphery.deployAdapter(address(factory), address(target), abi.encode(reward)));
        console.log("- Adapter %s deployed %s", name, address(adapter));

        console.log("- Can call scale value");
        console.log("  -> scale: %s", OwnableERC4626CropAdapter(address(adapter)).scale());

        (, , uint256 guard, ) = Divider(periphery.divider()).adapterMeta(address(adapter));
        console.log("  -> adapter guard: %s", guard);

        vm.stopBroadcast();
    }

    function _createRLV(OwnableERC4626CropAdapter adapter, AutoRollerFactory rlvFactory, address distributor) internal returns (AutoRoller rlv) {
        // create RLV for ownable adapter
        console.log("- Create RLV for %s", OwnableERC4626CropAdapter(adapter).name());
        
        rlv = rlvFactory.create(OwnedAdapterLike(address(adapter)), distributor, 3); // target duration
        console.log("- RLV %s deployed @ %s", rlv.name(), address(rlv));
    }

    function _roll(AutoRoller rlv) internal {
        OwnableERC4626CropAdapter adapter = OwnableERC4626CropAdapter(address(rlv.adapter()));
        (address t, address s, uint256 sSize) = adapter.getStakeAndTarget();
        
        // approve RLV to pull target
        ERC20 target = ERC20(t);
        uint256 tDecimals = target.decimals();
        target.approve(address(rlv), 2 * 10**tDecimals);

        // approve RLV to pull stake
        ERC20 stake = ERC20(s);
        stake.approve(address(rlv), sSize);
        
        // load wallet
        deal(s, address(this), sSize);
        deal(t, address(this), 10**tDecimals);

        // roll 1st series
        rlv.roll();
        console.log("- First series sucessfully rolled!");

        // check we can deposit
        rlv.deposit(5 * 1**tDecimals, address(this)); // deposit 1 target
        console.log("- 1 target sucessfully deposited!");
    }

    function _deployRewardsDistributor(address _reward) internal returns (RewardsDistributor distributor) {
        vm.broadcast(deployer);
        distributor = new RewardsDistributor(_reward);
        console.log("- Rewards distributor deployed @ %s", address(distributor));
    }

}