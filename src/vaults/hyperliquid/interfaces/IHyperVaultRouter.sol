// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IHyperVaultRouter
 * @author Blueberry
 */
interface IHyperVaultRouter {
    /*//////////////////////////////////////////////////////////////
                                Events  
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when a user deposits to the vault
    event Deposit(address indexed from, address indexed asset, uint256 amount, uint256 shares);

    /// @notice Emitted when a user redeems from the vault
    event Redeem(address indexed from, uint256 shares, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                Functions  
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deposit an asset into the escrows and mint shares of the tokenized vault
     * @param asset The address of the asset to deposit
     * @param amount The amount of asset to deposit
     * @return shares The amount of shares minted to the user
     */
    function deposit(address asset, uint256 amount) external returns (uint256 shares);

    /**
     * @notice Redeems shares for the withdraw asset
     * @param shares The amount of shares to redeem
     * @return amount The amount of withdraw asset received
     */
    function redeem(uint256 shares) external returns (uint256 amount);

    /**
     * @notice Returns the total value locked for all escrows in the vault
     * @return tvl_ The total value locked
     */
    function tvl() external view returns (uint256 tvl_);

    /**
     * @notice Determines which escrow will receive deposits
     * @dev The deposit escrow will be updated every 2 days.
     *      Should be noted that withdraws will occur from all escrows
     * @return The index of the escrow that will receive deposits
     */
    function depositEscrowIndex() external view returns (uint256);

    /**
     * @notice The L1 address of the vault being deposited into
     * @return The L1 vault address
     */
    function L1_VAULT() external view returns (address);

    /**
     * @notice The address of the share token for the tokenized vault
     * @return The share token address
     */
    function SHARE_TOKEN() external view returns (address);

    /// @notice Returns the address of the escrow at the specified index
    function escrows(uint256 index) external view returns (address);

    /// @notice Returns the max number of withdrawable assets able to be withdrawn
    function maxWithdrawable() external view returns (uint256);

    /// @notice Returns the max number of shares able to be redeemed
    function maxRedeemable() external view returns (uint256);
}
