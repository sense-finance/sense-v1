// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.4;

library Errors {

    // Auth
    error CombineRestricted();
    error IssuanceRestricted();
    error NotAuthorized();
    error OnlyClaim();
    error OnlyDivider();
    error OnlyPeriphery();
    error OnlyPermissionless();
    error RedeemZeroRestricted();
    error Untrusted();

    // Adapters
    error FlashCallbackFailed();
    error InvalidMaturityOffsets();
    error SenderNotEligible();
    error TargetMismatch();
    error TargetNotSupported();

    // Divider
    error AlreadySettled();
    error CollectNotSettled();
    error GuardCapReached();
    error IssuanceFeeCapExceeded();
    error IssueOnSettle();
    error NotSettled();

    // Input & validations
    error AlreadyInitialized();
    error DuplicateSeries();
    error ExistingValue();
    error InvalidAdapter();
    error InvalidMaturity();
    error InvalidParam();
    error OutOfWindowBoundaries();
    error SeriesDoesNotExist();
    error SwapTooSmall();
    error TargetParamsNotSet();
    error PoolParamsNotSet();
    error ZeroParamsNotSet();

    // Periphery
    error FactoryNotSupported();
    error FlashBorrowFailed();
    error FlashUntrustedBorrower();
    error FlashUntrustedLoanInitiator();
    error UnexpectedSwapAmount();

    // Fuse
    error AdapterNotSet();
    error FailedBecomeAdmin();
    error FailedAddMarket();
    error FailedAddZeroMarket();
    error FailedAddLpMarket();
    error OracleNotReady();
    error PoolAlreadyDeployed();
    error PoolNotDeployed();
    error PoolNotSet();
    error SeriesNotQueued();
    error TargetExists();
    error TargetNotInFuse();

    // Tokens
    error MintFailed();
    error RedeemFailed();
    error TransferFailed();
}
