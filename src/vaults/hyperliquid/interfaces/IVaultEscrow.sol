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
                                Structs
    //////////////////////////////////////////////////////////////*/

    /// @notice A struct returned by Hyperliquid L1 vault equity precompile calls
    struct UserVaultEquity {
        uint64 equity;
    }

    /*//////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit assets into the escrow
     * @param amount The amount of assets to deposit
     */
    function deposit(uint64 amount) external;

    /**
     * @notice Withdraw assets from a vault position
     * @dev This function can only be called by the vault wrapper
     * @param assets_ The amount of assets to withdraw
     */
    function withdraw(uint64 assets_) external;

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the TVL of the vault by adding the user vault equity and underlying asset balance
    function tvl() external view returns (uint256);

    /// @notice Returns the address of the vault
    function vault() external view returns (address);

    /// @notice Returns the address of the vault wrapper
    function vaultWrapper() external view returns (address);

    /// @notice Returns the address of the asset
    function asset() external view returns (address);

    /// @notice Returns the index of the asset in the hyperliquid spot
    function assetIndex() external view returns (uint64);

    /// @notice Returns the decimals of the asset
    function assetDecimals() external view returns (uint8);

    /// @notice Returns the decimals of the asset in perps
    function assetPerpDecimals() external view returns (uint8);
}
