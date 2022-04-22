// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BaseAdapter } from "../../adapters/BaseAdapter.sol";
import { Divider } from "../../Divider.sol";
import { TestHelper } from "../test-helpers/TestHelper.sol";

contract FakeAdapter is BaseAdapter {
    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams
    ) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {}

    function scale() external virtual override returns (uint256 _value) {
        return 100e18;
    }

    function scaleStored() external view virtual override returns (uint256) {
        return 100e18;
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function unwrapTarget(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        return 1e18;
    }

    function doSetAdapter(Divider d, address _adapter) public {
        d.setAdapter(_adapter, true);
    }
}

contract Adapters is TestHelper {
    using FixedMath for uint256;

    function testScale() public {
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
    }

    function testScaleMultipleTimes() public {
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
    }

    function testCantAddCustomAdapterToDivider() public {
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: ORACLE,
            stake: address(stake),
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            level: DEFAULT_LEVEL,
            ts: DEFAULT_TS,
            g1: DEFAULT_G1,
            g2: DEFAULT_G2,
            oracleEnabled: true
        });
        FakeAdapter fakeAdapter = new FakeAdapter(
            address(divider),
            address(target),
            target.underlying(),
            ISSUANCE_FEE,
            adapterParams
        );

        hevm.expectRevert("UNTRUSTED");
        fakeAdapter.doSetAdapter(divider, address(fakeAdapter));
    }

    // wrap/unwrap tests
    function testWrapUnderlying() public {
        uint256 uBal = 100 * (10**underlying.decimals());
        uint256 tBal = 100 * (10**target.decimals());
        underlying.mint(address(alice), uBal);
        adapter.setScale(1e18);
        adapter.scale();

        alice.doApprove(address(underlying), address(adapter));
        uint256 tBalReceived = alice.doAdapterWrapUnderlying(address(adapter), uBal);
        assertEq(tBal, tBalReceived);
    }

    function testUnwrapTarget() public {
        uint256 tBal = 100 * (10**target.decimals());
        uint256 uBal = 100 * (10**underlying.decimals());
        target.mint(address(alice), tBal);
        adapter.setScale(1e18);
        adapter.scale();

        alice.doApprove(address(target), address(adapter));
        uint256 uBalReceived = alice.doAdapterUnwrapTarget(address(adapter), tBal);
        assertEq(uBal, uBalReceived);
    }

    function testCantSetSpaceParamsIfNotTrusted() public {
        hevm.expectRevert("UNTRUSTED");
        hevm.prank(0x1234567890123456789012345678901234567890);
        factory.setSpaceParams(address(adapter), 1, 2, 3, false);
    }

    function testSetSpaceParams() public {
        uint256 newTs = FixedMath.WAD.fdiv(FixedMath.WAD * 100);
        uint256 newG1 = (FixedMath.WAD * 900).fdiv(FixedMath.WAD * 1000);
        uint256 newG2 = (FixedMath.WAD * 1000).fdiv(FixedMath.WAD * 900);

        // Can update space params
        factory.setSpaceParams(address(adapter), newTs, newG1, newG2, false);

        // Check adapters has new updated space params
        (, , , , , , , , uint256 ts, uint256 g1, uint256 g2, bool oracleEnabled) = adapter.adapterParams();
        assertEq(ts, newTs);
        assertEq(g1, newG1);
        assertEq(g2, newG2);
        assertTrue(!oracleEnabled);

        // // If params are updated, the new ones are used in the next deployment
        // SpaceLike space = SpaceLike(spaceFactory.create(address(cUsdcAdapter), maturity));
        // assertEq(space.ts(), newTs);
        // assertEq(space.g1(), newG1);
        // assertEq(space.g2(), newG2);

        // Fee params are validated
        newG1 = (FixedMath.WAD * 1000).fdiv(FixedMath.WAD * 900);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidG1.selector));
        factory.setSpaceParams(address(adapter), ts, newG1, g2, true);

        newG1 = (FixedMath.WAD * 900).fdiv(FixedMath.WAD * 1000);
        newG2 = (FixedMath.WAD * 900).fdiv(FixedMath.WAD * 1000);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidG2.selector));
        factory.setSpaceParams(address(adapter), ts, newG1, newG2, true);
    }
}
