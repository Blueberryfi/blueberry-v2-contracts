
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IVaultEscrow
 * @author Blueberry
 * @notice Interface for the VaultEscrow contract
 * @dev The purpose of the VaultEscrow is to allow for increased redeemable liquidity in the
 *      event that there are deposits locks enforced on the L1 vault. (Example: HLP 4-day lock)
 */
interface IVaultEscrow {
    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the vault that corresponds to this escrow account
    function vault() external view returns (address);
}