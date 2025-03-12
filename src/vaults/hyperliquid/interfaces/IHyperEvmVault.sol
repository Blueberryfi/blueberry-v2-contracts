// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IHyperEvmVault
 * @author Blueberry
 * @notice Interface for the ERC4626 compatible HyperEvmVault contract that will be deployed on Hyperliquid EVM
 */
interface IHyperEvmVault is IERC4626 {
    /*//////////////////////////////////////////////////////////////
                                Structs
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice A struct that contains the assets and shares that a account has requested to redeem
     * @param assets The amount of assets that the account has requested to redeem
     * @param shares The amount of shares that the account has requested to redeem
     */
    struct RedeemRequest {
        uint64 assets;
        uint256 shares;
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Emitted when a new escrow is deployed
     * @param escrow The address of the new escrow contract for the vault
     */
    event EscrowDeployed(address indexed escrow);

    /**
     * @notice Emitted when a new redeem request is made
     * @param account The address of the account that made the redeem request
     * @param shares The amount of shares the account requested to redeem
     * @param assets The amount of assets the account requested to redeem
     */
    event RedeemRequested(address indexed account, uint256 shares, uint256 assets);

    /**
     * @notice Emitted when the admin withdraws the accumulated fees from the vault
     * @param amount The amount of fees withdrawn
     */
    event FeesWithdrawn(uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Requests a redemption from the vault
     * @param shares_ The amount of shares to redeem
     */
    function requestRedeem(uint256 shares_) external;

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the total value of the tokenized vault
     * @return tvl_ The total value of the tokenized vault
     */
    function tvl() external view returns (uint256 tvl_);

    /// @notice The L1 address of the vault being deposited into on Hyperliquid L1
    function L1_VAULT() external view returns (address);

    /// @notice Returns the current L1 block number through a precompile static call
    function l1Block() external view returns (uint64);

    /**
     * @notice Calculates the index of the escrow contract that will be used to process deposits
     * @return The index of the escrow contract deposits will be routed through
     */
    function depositEscrowIndex() external view returns (uint256);

    /**
     * @notice Calculates the index of the escrow contract that will be used to process redemptions
     * @return The index of the escrow contract redemptions will be routed through
     */
    function redeemEscrowIndex() external view returns (uint256);

    /**
     * @notice Calculates the max amount of assets that can be requested to be withdrawn for redemption
     * @return The max amount of assets that can be requested to be withdrawn
     */
    function maxWithdrawableAssets() external view returns (uint256);

    /// @notice Returns the minimum amount of assets that can be deposited into the vault
    function minDepositAmount() external view returns (uint256);

    /// @notice Returns the address of the escrow contract at a given index
    function escrows(uint256 index) external view returns (address);

    /// @notice Returns the number of escrow contracts deployed for the vault
    function escrowsLength() external view returns (uint256);

    /// @notice Returns the redeem request for a given user
    function redeemRequests(address user) external view returns (RedeemRequest memory);

    /// @notice Returns the last L1 block number noticed by the vault
    function lastL1Block() external view returns (uint64);

    /// @notice Returns the current amount of assets that have been deposited during the last L1 block noticed by the vault
    function currentBlockDeposits() external view returns (uint64);

    /// @notice Returns the last time fees were collected from the vault and shares were minted to the feeRecipient
    function lastFeeCollectionTimestamp() external view returns (uint64);

    /// @notice Returns the address of the fee recipient
    function feeRecipient() external view returns (address);
}
