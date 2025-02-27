// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IHyperEvmVault
 * @author Blueberry
 * @notice Interface for the ERC4626 compatible HyperEvmVault contract that will be deployed on Hyperliquid EVM
 */
interface IHyperEvmVault {
    /*//////////////////////////////////////////////////////////////
                                Structs
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice A struct that contains the assets and shares that a user has requested to redeem
     * @param assets The amount of assets that the user has requested to redeem
     * @param shares The amount of shares that the user has requested to redeem
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

    /**
     * @notice Calculates the amount of fees to take from the vault
     * @dev This function is almost idential to the feeTake function, but does not update state.
     * @param preFeeTvl_ The total value of the vault before fees are taken
     * @return feeTake_ The amount of fees to take in underlying assets
     */
    function previewFeeTake(uint256 preFeeTvl_) external view returns (uint256 feeTake_);

    /// @notice The L1 address of the vault being deposited into on Hyperliquid L1
    function l1Vault() external view returns (address);

    /// @notice Returns the current L1 block number through a precompile static call
    function l1Block() external view returns (uint256);

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
}
