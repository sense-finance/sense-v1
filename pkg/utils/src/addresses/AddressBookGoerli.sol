// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/// @notice Goerli AddressBook
library AddressBookGoerli {
    // underlyings
    address public constant DAI = 0x436f3D3f1e0B7a2335594b57670c7A05Bc5F0dc6;
    address public constant USDC = 0xc4723445bD201f685A8128DC2D602DD86B696E22;
    address public constant USDT = 0xB209E94E9216331af1158E8588dD69e0a88eA2Da;

    // targets
    address public constant cDAI = 0x8D170266d009d720F3286D8FBe8BAc40217f4aE9;
    address public constant cUSDC = 0x5A13CC452Bb4225fe1c1005f965C27be05aeF7C5;
    address public constant cUSDT = 0xF3A0C5F5Ae311e824DeFDcf9DaDFBd6a7a404DB8;
    address public constant BB_wstETH4626 = 0xF3A0C5F5Ae311e824DeFDcf9DaDFBd6a7a404DB8; // cUSDT address

    // eth
    address public constant WETH = 0xC027849ac78202A17A872021Bd0271DA5df04168;

    // deployed sense contract
    address public constant PERIPHERY = 0x4bCBA1316C95B812cC014CA18C08971Ce1C10861;
    address public constant DIVIDER = 0x09B10E45A912BcD4E80a8A3119f0cfCcad1e1f12;
    address public constant SPACE_FACTORY = 0x1621cb1a1A4BA17aF0aD62c6142A7389C81e831D;
    address public constant POOL_MANAGER = 0xaBFA7080ABe1012f6A8f74E2CDDd9033c34d1A44;
    address public constant BALANCER_VAULT = 0x1aB16CB0cb0e5520e0C081530C679B2e846e4D37;
    address public constant SENSE_MASTER_ORACLE = 0xB3e70779c1d1f2637483A02f1446b211fe4183Fa;

    // sense
    address public constant SENSE_MULTISIG = 0xF13519734649F7464E5BE4aa91987A35594b2B16;
}
