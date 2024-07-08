// SPDX-License-Identifier: BUSL-1.1
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity ^0.8.26;

library BBErrors {
    /*///////////////////////////////////////////////////////////////
                          Money-Market Errors
    //////////////////////////////////////////////////////////////*/

    /// @notice Error when a user tries to interact with a market that doesnt exist.
    error INVALID_MARKET();

    /// @notice Error when a caller tries to call a functions that only the money market, BlueberryGarden, can call.
    error CALLER_NOT_GARDEN();

    /// @notice Error when trying to add a market that already exists.
    error MARKET_ALREADY_EXISTS();

    /*///////////////////////////////////////////////////////////////
                    ERC4626 MULTI-TOKEN ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error when an account tries to withdraw more than their balance.
    error INSUFFICIENT_BALANCE();

    /// @notice Error when an account spends more than their allowance.
    error INSUFFICIENT_ALLOWANCE();

    /*///////////////////////////////////////////////////////////////
                            GENERAL ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error when the caller is not authorized to call a function.
    error UNAUTHORIZED();

    /// @notice Error when the recipient address is address zero.
    error ADDRESS_ZERO();
}
