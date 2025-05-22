// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperliquidCommon} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperliquidCommon.sol";

/**
 * @title IHyperVaultRouter
 * @author Blueberry
 */
interface IHyperVaultRouter is IHyperliquidCommon {
    /*//////////////////////////////////////////////////////////////
                                Events  
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits to the vault
    event Deposit(address indexed from, address indexed asset, uint256 amount, uint256 shares);

    /// @notice Emitted when a user redeems from the vault
    event Redeem(address indexed from, uint256 shares, uint256 amount);

    /// @notice New Supported Asset Added
    event AssetAdded(uint64 assetIndex, AssetDetails details);

    /// @notice Emitted when a supported asset is removed
    event AssetRemoved(uint64 assetIndex);

    /// @notice Emitted when the withdraw asset is updated
    event WithdrawAssetUpdated(uint64 assetIndex);

    /*//////////////////////////////////////////////////////////////
                            External Functions  
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deposit an asset into the escrows and mint shares of the tokenized vault
     * @param asset The address of the asset to deposit
     * @param amount The amount of asset to deposit
     * @param minOut The minimum amount of shares to mint
     * @return shares The amount of shares minted to the user
     */
    function deposit(address asset, uint256 amount, uint256 minOut) external returns (uint256 shares);

    /**
     * @notice Redeems shares for the withdraw asset
     * @param shares The amount of shares to redeem
     * @param minOut The minimum amount of withdraw asset to receive
     * @return amount The amount of withdraw asset received
     */
    function redeem(uint256 shares, uint256 minOut) external returns (uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            View Functions  
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The address of the share token for the tokenized vault
     * @return The share token address
     */
    function SHARE_TOKEN() external view returns (address);

    /**
     * @notice Returns the total value locked for all escrows in the vault
     * @return tvl_ The total value locked
     */
    function tvl() external view returns (uint256 tvl_);

    /// @notice Returns the address of the escrow at the specified index
    function escrows(uint256 index) external view returns (address);

    /// @notice Returns the spot index of the asset
    function assetIndex(address asset) external view returns (uint64);

    /// @notice Returns the last fee collection timestamp
    function lastFeeCollectionTimestamp() external view returns (uint256);

    /// @notice The management fee in basis points
    function managementFee() external view returns (uint256);

    /// @notice The minimum value in USD that can be deposited into the vault scaled to 1e18
    function minDeposit() external view returns (uint256);

    /// @notice The asset that will be used to withdraw from the vault
    function withdrawAsset() external view returns (address);

    /// @notice The address that will receive the management fee
    function feeRecipient() external view returns (address);

    /**
     * @notice Determines which escrow will receive deposits
     * @dev The deposit escrow will be updated every 2 days.
     *      Should be noted that withdraws will occur from all escrows
     * @return The index of the escrow that will receive deposits
     */
    function depositEscrowIndex() external view returns (uint256);

    /// @notice Returns the max number of withdrawable assets able to be withdrawn
    function maxWithdrawable() external view returns (uint256);

    /// @notice Returns the max number of shares able to be redeemed
    function maxRedeemable() external view returns (uint256);

    /// @notice Returns the amount of shares that will be minted for a given amount of asset
    function previewDeposit(address asset, uint256 amount) external view returns (uint256 shares);

    /// @notice Returns the amount of withdraw asset that will be received for a given amount of shares
    function previewRedeem(uint256 shares) external view returns (uint256 amount);
}
