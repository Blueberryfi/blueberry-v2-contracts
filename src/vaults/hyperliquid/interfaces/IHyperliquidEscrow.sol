// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title IHyperliquidEscrow
 */
interface IHyperliquidEscrow {
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

    /// @notice Hyperliquid precompile struct: Token information
    struct TokenInfo {
        string name;
        uint64[] spots;
        uint64 deployerTradingFeeShare;
        address deployer;
        address evmContract;
        uint8 szDecimals;
        uint8 weiDecimals;
        int8 evmExtraWeiDecimals;
    }

    /// @notice Necessary Hyperliquid core & evm information for a token index
    struct Token {
        address evmContract;
        uint8 szDecimals;
        uint8 weiDecimals;
        uint8 evmDecimals;
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
     * @param token The token index
     * @return The exchange rate in USD with 18 decimals
     */
    function getRate(uint64 token) external view returns (uint256);

    /**
     * @notice Returns the system address for an asset
     * @param token The token index
     * @return The system address for the asset
     */
    function assetSystemAddr(uint64 token) external pure returns (address);

    /// @notice Returns whether the asset is supported or not by the escrow
    function isAssetSupported(uint64 token) external view returns (bool);

    /**
     * @notice The L1 address of the vault
     * @return The L1 vault address
     */
    function L1_VAULT() external view returns (address);

    /**
     * @notice The address of the manager
     * @return The manager address
     */
    function ROUTER() external view returns (address);

    /**
     * @notice USDC perp decimals constant
     * @return The USDC perp decimals
     */
    function USDC_PERP_DECIMALS() external pure returns (uint8);

    /**
     * @notice USDC spot decimals constant
     * @return The USDC spot decimals
     */
    function USDC_SPOT_DECIMALS() external pure returns (uint8);

    /**
     * @notice USDC spot index constant
     * @return The USDC spot index
     */
    function USDC_SPOT_INDEX() external pure returns (uint64);
}
