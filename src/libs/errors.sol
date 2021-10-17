// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

/// @notice Program error types
library Errors {
    string constant AlreadySettled = "Series has already been settled";
    string constant CollectNotSettled = "Cannot collect if Series is at or after maturity and it has not been settled";
    string constant DuplicateSeries = "Series with given maturity already exists";
    string constant ExistingValue = "New value must be different than previous";
    string constant FeedAlreadyExists = "Feed already exists";
    string constant GuardCapReached = "Issuance cap reached";
    string constant IssueOnSettled = "Cannot issue if Series is settled";
    string constant InvalidFeed = "Invalid feed address or feed is not enabled";
    string constant InvalidMaturity = "Maturity date is not valid";
    string constant InvalidScaleValue = "Scale value is invalid";
    string constant NotAuthorized = "UNTRUSTED"; // We copy the error message used by solmate's `Trust` auth lib
    string constant NotEnoughClaims = "Not enough claims to collect given target balance";
    string constant SeriesDoesntExists = "Series does not exist";
    string constant NotSettled = "Series must be settled";
    string constant NotSupported = "Target is not supported";
    string constant OutOfWindowBoundaries = "Can not settle Series outside the time window boundaries";
    string constant TransferFromFailed = "TRANSFER_FROM_FAILED";
    string constant ZeroBalance = "Balance must be greater than 0";
}
