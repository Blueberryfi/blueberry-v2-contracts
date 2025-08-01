// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IHyperliquidCommon} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperliquidCommon.sol";

/**
 * @title IHyperliquidEscrow
 */
interface IHyperliquidEscrow is IHyperliquidCommon {
    /*//////////////////////////////////////////////////////////////
                                 Structs
    //////////////////////////////////////////////////////////////*/
    /// @notice Hyperliquid precompile struct: Spot balance information
    struct SpotBalance {
        uint64 total;
        uint64 hold;
        uint64 entryNtl;
    }

    /**
     * @notice Hyperliquid precompile struct: Withdrawable information
     * @dev used to get the amount of free USDC within the perps account
     */
    struct Withdrawable {
        uint64 withdrawable;
    }

    /// @notice Hyperliquid precompile struct: Vault equity information
    struct UserVaultEquity {
        uint64 equity;
        uint64 lockedUntilTimestamp;
    }

    /**
     * @notice Returns the total value locked (TVL) in the escrow in terms of USD
     * @dev The TVL is scaled to 18 decimals.
     *      Formulated as:
     *          - Equity in Vault
     *          - USDC Perps Balance
     *          - USDC Spot Balance
     *          - All Supported Asset Spot Balance (skip USDC)
     *          - All Supported Asset Contract Balance
     * @return tvl_ The total value locked in the escrow with 18 decimals
     */
    function tvl() external view returns (uint256 tvl_);

    /**
     * @notice Returns the USDC spot balance
     * @return The USDC spot balance scaled to 18 decimals
     */
    function usdSpotBalance() external view returns (uint256);

    /**
     * @notice Returns the spot balance for a specific asset in terms of USD
     * @dev The balance is scaled to 18 decimals.
     * @param token The token index
     * @return The spot balance for the specified asset
     */
    function spotAssetBalance(uint64 token) external view returns (uint256);

    /**
     * @notice Returns the vault equity
     * @return The vault equity in USD with 18 decimals
     */
    function vaultEquity() external view returns (uint256);

    /**
     * @notice Returns the USD perps balance
     * @return The USD perps balance with 18 decimals
     */
    function usdPerpsBalance() external view returns (uint256);

    /**
     * @notice Returns the exchange rate of a token in USD
     * @param spotMarket The Spot Market index of a token
     * @param szDecimals The number of decimals that spot prices are returned with
     * @return The exchange rate in USD with 18 decimals
     */
    function getRate(uint32 spotMarket, uint8 szDecimals) external view returns (uint256);
}
