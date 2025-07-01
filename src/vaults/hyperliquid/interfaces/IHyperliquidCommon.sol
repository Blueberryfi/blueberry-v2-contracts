// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title IHyperliquidCommon
 * @author Blueberry
 * @notice A common interface for Hyperliquid contracts
 */
interface IHyperliquidCommon {
    /*//////////////////////////////////////////////////////////////
                                Structs
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Hyperliquid precompile struct: Spot information for a specific pair
    struct SpotInfo {
        string name;
        uint64[2] tokens;
    }

    /// @notice Necessary Hyperliquid core & evm information for a token index
    struct AssetDetails {
        address evmContract;
        uint8 szDecimals;
        uint8 weiDecimals;
        uint8 evmDecimals;
        uint32 spotMarket;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns whether an asset is supported by the escrow
     * @param assetIndex The index of the asset to check
     * @return Whether the asset is supported
     */
    function isAssetSupported(uint64 assetIndex) external view returns (bool);

    /**
     * @notice Returns the details of an asset
     * @param assetIndex The index of the asset to get details for
     * @return The details of the asset as an AssetDetails struct
     */
    function assetDetails(uint64 assetIndex) external view returns (AssetDetails memory);
}
