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

    /// @notice Error thrown when the perp decimals are invalid
    error INVALID_PERP_DECIMALS();
}
