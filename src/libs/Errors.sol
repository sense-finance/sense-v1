// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

/// @notice Program error types
library Errors {
    string constant AlreadySettled = "Series has already been settled";
    string constant CollectNotSettled = "Cannot collect if Series is at or after maturity and it has not been settled";
    string constant DuplicateSeries = "Series has already been initialized";
    string constant ExistingValue = "New value must be different than previous";
    string constant FactoryNotSupported = "Factory is not supported";
    string constant FeedAlreadyExists = "Feed already exists";
    string constant FlashCallbackFailed = "FlashLender: Callback failed";
    string constant FlashRepayFailed = "FlashLender: Repay failed";
    string constant FlashTransferFailed = "FlashLender: Transfer failed";
    string constant FlashUntrustedBorrower = "FlashBorrower: Untrusted lender";
    string constant FlashUntrustedLoanInitiator = "FlashBorrower: Untrusted loan initiator";
    string constant GuardCapReached = "Issuance cap reached";
    string constant IssuanceFeeCapExceeded = "Issuance fee cannot exceed 10%";
    string constant IssueOnSettled = "Cannot issue if Series is settled";
    string constant InvalidFeed = "Invalid feed address or feed is not enabled";
    string constant InvalidMaturity = "Maturity date is not valid";
    string constant InvalidScaleValue = "Scale value is invalid";
    string constant NotAuthorized = "UNTRUSTED"; // We copy the error message used by solmate's `Trust` auth lib
    string constant NotEnoughClaims = "Not enough claims to collect given target balance";
    string constant SeriesDoesntExists = "Series does not exist";
    string constant NotSettled = "Series must be settled";
    string constant NotSupported = "Target is not supported";
    string constant OnlyPeriphery = "Can only be invoked by the Periphery contract";
    string constant OnlyPermissionless = "Can only be invoked if permissionless mode is enabled";
    string constant OutOfWindowBoundaries = "Can not settle Series outside the time window boundaries";
    string constant TransferFromFailed = "TRANSFER_FROM_FAILED";
    string constant ZeroBalance = "Balance must be greater than 0";
}
