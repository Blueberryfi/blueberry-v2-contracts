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
        uint64 lockedUntilTimestamp;
    }

    /// @notice A struct representing the state of the escrow in relation to Hyperliquid L1 for withdrawals
    struct L1WithdrawState {
        /// @notice The last L1 block number that a withdraw was requested on the escrow
        uint64 lastWithdrawBlock;
        /// @notice The total amount of assets that have been requested to be withdrawn during the last withdraw block
        uint64 lastWithdraws;
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
     * @return The amount of assets withdrawn (could be different than input due to scaling truncation)
     */
    function withdraw(uint64 assets_) external returns (uint64);

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

    /// @notice Returns the vault equity that is controlled by the escrow contract
    function vaultEquity() external view returns (uint256);

    /**
     * @notice Returns the address of the asset system
     * @dev The system address is used to bridge assets to Hyperliquid L1.
     *      The system address for an asset is derived by appending `0x20` followed by all 0s,
     *      and then the asset index encoded in big-endian format.
     */
    function assetSystemAddr() external view returns (address);

    /// @dev Returns the current L1 block number.
    function l1Block() external view returns (uint64);

    /// @dev Returns the L1WithdrawState struct.
    function l1WithdrawState() external view returns (L1WithdrawState memory);
}
