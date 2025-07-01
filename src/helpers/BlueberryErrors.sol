// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

library BlueberryErrors {
    /// @notice Error thrown when the admin tries to set a fee that is too high
    error FEE_TOO_HIGH();

    /// @notice Error thrown when an input address is zero
    error ADDRESS_ZERO();

    /// @notice Error thrown when an input amount is zero
    error AMOUNT_ZERO();

    /// @notice Error thrown when the user does not have enough balance
    error USER_BALANCE_SMOL();

    /// @notice Error thrown when the vault does not have enough balance to redeem
    error VAULT_BALANCE_SMOL();

    /// @notice Error thrown when the collateral is not supported
    error COLLATERAL_NOT_SUPPORTED();

    /// @notice Error thrown when the sender is not the vault
    error INVALID_SENDER();

    /// @notice Error thrown when the staticcall fails
    error STATICCALL_FAILED();

    /// @notice Error thrown when the minimum deposit amount is not met
    error MIN_DEPOSIT_AMOUNT();

    /// @notice Error thrown when not enough assets are fetched from the escrows
    error FETCH_ASSETS_FAILED();

    /// @notice Error thrown when the redeem request is not found
    error REDEEM_REQUEST_NOT_FOUND();

    /// @notice Error thrown when the transfer is blocked due to a pending redeem request
    error TRANSFER_BLOCKED();

    /// @notice Error thrown when a users balance is insufficient for burning a receipt token.
    error INSUFFICIENT_BALANCE();

    /// @notice Error thrown when a users withdraw request is too large
    error WITHDRAW_TOO_LARGE();

    /// @notice Error thrown when a users withdraw is too small
    error WITHDRAW_TOO_SMALL();

    /// @notice Error thrown when the perp decimals are invalid
    error INVALID_PERP_DECIMALS();

    /// @notice Error thrown when the vault equity is insufficient to withdraw
    error INSUFFICIENT_VAULT_EQUITY();

    /// @notice Error thrown when the fee recipient is invalid
    error INVALID_FEE_RECIPIENT();

    /// @notice Error thrown when the vault on Hyperliquid L1 is locked and cannot be used for withdrawals
    error L1_VAULT_LOCKED();

    /// @notice Error thrown when 0 shares are minted from a vault deposit
    error ZERO_SHARES();

    /// @notice Error thrown when there is an invalid amount of escrows deployed
    error INVALID_ESCROW_COUNT();

    /// @notice Error thrown when the escrow is invalid and the assets do not match
    error INVALID_ESCROW();

    /// @notice Error thrown when someone other than the owner tries to call redeem or withdraw
    error OnlyOwnerCanWithdraw();

    /// @notice Error thrown when a precompile call fails
    error PRECOMPILE_CALL_FAILED();

    /// @notice Error thrown the router tries to add an asset that is already supported
    error ASSET_ALREADY_SUPPORTED();

    /// @notice Error thrown when the router tries to remove an asset after the max number of assets is reached
    error ASSET_LIMIT_EXCEEDED();

    /// @notice Error thrown when the router tries to add an asset but there is a mismatch in the assets evm address
    error INVALID_EVM_ADDRESS();

    error INVALID_OPERATION();

    error INVALID_SPOT_MARKET();

    /// @notice Error thrown when too frequent admin actions are performed
    error TOO_FREQUENT_ACTIONS();

    /// @notice Error thrown when the length of the assets and amounts arrays do not match
    error MISMATCHED_LENGTH();

    /// @notice Error thrown when slippage is too high and the minimum amount is not met
    error SLIPPAGE_TOO_HIGH();

    /// @notice Error thrown when the TIF (Time in Force) is invalid
    error INVALID_TIF();
}
