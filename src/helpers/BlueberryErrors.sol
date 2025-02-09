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

    /// @notice Error thrown when the deposited collateral is below the minimum deposit
    error BELOW_MIN_COLL();

    /// @notice Error thrown when the sender is not the vault
    error INVALID_SENDER();

    /// @notice Error thrown when the array lengths do not match
    error ARRAY_LENGTH_MISMATCH();

    /// @notice Error thrown when the amount exceeds the current balance
    error AMOUNT_EXCEEDS_BALANCE();

    /// @notice Error if a user tries to execute an invalid operation
    error INVALID_OPERATION();

    /// @notice Error if an operation is attempted on the wrong user
    error INVALID_USER();
}
