// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { Periphery } from "../Periphery.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { Assets } from "./test-helpers/Assets.sol";
import { MockAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";

// External references
import { FixedMath } from "../external/FixedMath.sol";
import { BalancerVault } from "../external/balancer/Vault.sol";
import { BalancerPool } from "../external/balancer/Pool.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

interface SpaceFactoryLike {
    function create(address adapter, uint48 maturity) external returns (address);

    function pools(address adapter, uint256 maturity) external view returns (address);
}

contract PeripheryE2E is TestHelper {
    using FixedMath for uint256;

    BalancerVault internal vault;
    BalancerPool internal space;
    address internal zero;
    address internal claim;
    uint48 internal maturity;

    function setUp() public override {
        super.setUp();
        _compileSpace();

        string[] memory inputs = new string[](4);
        inputs[0] = "jq";
        inputs[1] = "-j";
        inputs[2] = ".bin";

        inputs[3] = "../space/out/Authorizer.sol/Authorizer.json";
        bytes memory authBin = hevm.ffi(inputs);
        inputs[3] = "../space/out/Vault.sol/Vault.json";
        bytes memory vaultBin = hevm.ffi(inputs);
        inputs[3] = "../space/out/SpaceFactory.sol/SpaceFactory.json";
        bytes memory spaceFactoryBin = hevm.ffi(inputs);

        address _authorizer;
        bytes memory authBytecode = abi.encodePacked(authBin, abi.encode(address(this)));
        assembly {
            _authorizer := create(0, add(authBytecode, 0x20), mload(authBytecode))
        }

        address _vault;
        bytes memory vaultBytecode = abi.encodePacked(vaultBin, abi.encode(_authorizer, address(0), 0, 0));
        assembly {
            _vault := create(0, add(vaultBytecode, 0x20), mload(vaultBytecode))
        }

        address _spaceFactory;
        bytes memory spaceFactoryBytecode = abi.encodePacked(
            spaceFactoryBin,
            abi.encode(
                _vault,
                address(divider),
                FixedMath.WAD.fdiv(FixedMath.WAD * 31622400, FixedMath.WAD), // 1 / 1 year in seconds,
                (FixedMath.WAD * 950).fdiv(FixedMath.WAD * 1000, FixedMath.WAD), // 0.95 for selling Target
                (FixedMath.WAD * 1000).fdiv(FixedMath.WAD * 950, FixedMath.WAD) // 1 / 0.95 for selling Zeros
            )
        );
        assembly {
            _spaceFactory := create(0, add(spaceFactoryBytecode, 0x20), mload(spaceFactoryBytecode))
        }

        // Override parent's periphery with one that uses a real Balancer vault
        periphery = new Periphery(address(divider), address(poolManager), address(_spaceFactory), address(_vault));

        // Set the periphery up with the right permissions and onboard an adapter
        poolManager.setIsTrusted(address(periphery), true);
        divider.setPeriphery(address(periphery));
        maturity = getValidMaturity(2021, 12);
        periphery.setFactory(address(factory), true);

        // Need a new Target address so that we can use the same factory as the parent with the new periphery
        target = new MockTarget(address(underlying), "Compound Dai", "cDAI", 18);
        alice.doMint(address(target), 100e18);
        factory.addTarget(address(target), true);
        address f = periphery.onboardAdapter(address(factory), address(target));
        adapter = MockAdapter(f);

        // Set Alice up with the new periphery
        alice.setPeriphery(periphery);
        alice.doApprove(address(underlying), address(periphery));
        alice.doApprove(address(stake), address(periphery));
        alice.doApprove(address(target), address(periphery));

        (zero, claim) = alice.doSponsorSeries(address(adapter), maturity);

        vault = BalancerVault(_vault);
        space = BalancerPool(SpaceFactoryLike(_spaceFactory).pools(address(adapter), maturity));
    }

    function testAddLiquidityFirstTimeAndHoldClaims() public {
        uint256 tBal = 1e18;
        uint256 lpBalBefore = ERC20(address(space)).balanceOf(address(alice));
        uint256 tBalBefore = ERC20(adapter.getTarget()).balanceOf(address(alice));
        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));

        (uint256 targetBal, uint256 claimBal, uint256 lpShares) = alice.doAddLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            1
        );

        assertEq(targetBal, 0);
        assertTrue(claimBal > 0);
        assertEq(lpShares, ERC20(address(space)).balanceOf(address(alice)));

        assertEq(tBalBefore - tBal, ERC20(adapter.getTarget()).balanceOf(address(alice)));
        assertEq(lpBalBefore + tBal, ERC20(address(space)).balanceOf(address(alice)));
        assertEq(cBalBefore + claimBal, ERC20(claim).balanceOf(address(alice)));
    }

    function _compileSpace() public {
        string[] memory inputs = new string[](3);
        inputs[0] = "just";
        inputs[1] = "turbo-build-dir";
        inputs[2] = "../space";
        hevm.ffi(inputs);
    }
}
