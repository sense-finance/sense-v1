// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity ^0.8.6;

// import "ds-test/test.sol";
// import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
// import { LogExpMath } from "./Math.sol";

// import "./Invariant.sol";


// abstract contract Hevm {
//     // Sets the block timestamp to x
//     function warp(uint x) public virtual;
//     // Sets the block number to x
//     function roll(uint x) public virtual;
//     // Sets the slot loc of contract c to val
//     function store(address c, bytes32 loc, bytes32 val) public virtual;
//     function ffi(string[] calldata) external virtual returns (bytes memory);
// }

// contract InvariantTest is DSTest {
//     using FixedPointMathLib for uint256;
//     Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

//     function setUp() public { }

//     event A(string, uint);
//     function test_basic_sanity() public {
//         // 21.10.01
//         uint256 startingTime = 1633046400;
//         hevm.warp(startingTime);

//         uint256 ts = FixedPointMathLib.WAD.fdiv(FixedPointMathLib.WAD * 315576000, FixedPointMathLib.WAD);
//         uint256 g1 = (FixedPointMathLib.WAD * 950).fdiv(FixedPointMathLib.WAD * 1000, FixedPointMathLib.WAD);
//         uint256 g2 = (FixedPointMathLib.WAD * 1000).fdiv(FixedPointMathLib.WAD * 950, FixedPointMathLib.WAD);

//         uint256 underlyingReserves = 10000000000000000000000000;
//         uint256 zeroReserves = 10100000000000000000000000;
//         uint256 tradeSize = 100000000000000000000;
//         uint256 ttm = 4000;        

//         YieldSpaceLike ysLike = new YieldSpaceLike(zeroReserves, underlyingReserves, ts, g2);

//         // 21.11.01
//         ysLike.zeroIn(tradeSize, startingTime + ttm);
//         // assertTrue(false);
//     }
// }
