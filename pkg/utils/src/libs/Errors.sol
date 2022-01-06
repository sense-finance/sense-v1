// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

/// @notice Program error types
library Errors {
    string constant AlreadySettled = "Series has already been settled";
    string constant CollectNotSettled = "Cannot collect if Series is at or after maturity and it has not been settled";
    string constant Create2Failed = "ERC1167: create2 failed";
    string constant DuplicateSeries = "Series has already been initialized";
    string constant ExistingValue = "New value must be different than previous";
    string constant FactoryNotSupported = "Factory is not supported";
    string constant FailedBecomeAdmin = "Failed to become admin";
    string constant FailedAddMarket = "Failed to add market";
    string constant FailedAddZeroMarket = "Failed to add Zero market";
    string constant FailedAddLPMarket = "Failed to add LP market";
    string constant FlashCallbackFailed = "FlashLender: Callback failed";
    string constant FlashRepayFailed = "FlashLender: Repay failed";
    string constant FlashTransferFailed = "FlashLender: Transfer failed";
    string constant FlashUntrustedBorrower = "FlashBorrower: Untrusted lender";
    string constant FlashUntrustedLoanInitiator = "FlashBorrower: Untrusted loan initiator";
    string constant UnexpectedSwapAmount = "Unexpected swap amount";
    string constant SwapTooSmall = "Requested Stop amount is to low";
    string constant GuardCapReached = "Issuance cap reached";
    string constant IssuanceFeeCapExceeded = "Issuance fee cannot exceed 10%";
    string constant IssueOnSettled = "Cannot issue if Series is settled";
    string constant InvalidAdapter = "Invalid adapter address or adapter is not enabled";
    string constant InvalidMaturity = "Maturity date is not valid";
    string constant InvalidMaturityOffsets = "Invalid maturity offsets";
    string constant InvalidScaleValue = "Scale value is invalid";
    string constant NotAuthorized = "UNTRUSTED"; // We copy the error message used by solmate's `Trust` auth lib
    string constant NotEnoughClaims = "Not enough claims to collect given target balance";
    string constant SeriesDoesntExists = "Series does not exist";
    string constant SeriesNotQueued = "Series must be queued";
    string constant NotSettled = "Series must be settled";
    string constant NotSupported = "Target is not supported";
    string constant OnlyClaim = "Can only be invoked by the Claim contract";
    string constant OnlyDivider = "Can only be invoked by the Divider contract";
    string constant OnlyPeriphery = "Can only be invoked by the Periphery contract";
    string constant OnlyPermissionless = "Can only be invoked if permissionless mode is enabled";
    string constant OutOfWindowBoundaries = "Can not settle Series outside the time window boundaries";
    string constant Paused = "Pausable: paused";
    string constant PoolAlreadyDeployed = "Pool already deployed";
    string constant PoolNotDeployed = "Pool not yet deployed";
    string constant SenderNotEligible = "Sender is not eligible";
    string constant TargetExists = "Target already added";
    string constant TargetNotInFuse = "Target for this Series not yet added to Fuse";
    string constant TargetMismatch = "Source Target must be the same a destination Target";
    string constant TargetParamNotSet = "Target asset params not set";
    string constant TransferFromFailed = "TRANSFER_FROM_FAILED";
    string constant ZeroBalance = "Balance must be greater than 0";
    string constant CombineRestricted = "Combine restricted to Adapter";
    string constant IssuanceRestricted = "Issuance restricted to Adapter";
    string constant RedeemZeroRestricted = "Redeem Zero restricted to Adapter";
}
