// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";
import {IHyperliquidCommon} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperliquidCommon.sol";

/**
 * @title EscrowAssetStorage
 * @author Blueberry
 * @notice A storage contract for tracking the assets supported by an escrow
 */
abstract contract EscrowAssetStorage is IHyperliquidCommon {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:asset.v1.storage
    struct V1AssetStorage {
        /// @notice A set of supported asset indexes
        EnumerableSet.UintSet supportedAssets;
        /// @notice A mapping of asset Indexes to their corresponding asset details
        mapping(uint64 => AssetDetails) assetDetails;
    }

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the router contract
    address public immutable ROUTER;

    /// @notice The location for the escrow asset storage
    bytes32 public constant V1_ASSET_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("asset.v1.storage"))) - 1)) & ~bytes32(uint256(0xff));

    /*//////////////////////////////////////////////////////////////
                            Modifiers
    //////////////////////////////////////////////////////////////*/
    modifier onlyRouter() {
        require(msg.sender == ROUTER, Errors.INVALID_SENDER());
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address router) {
        ROUTER = router;
    }

    /*//////////////////////////////////////////////////////////////
                            Router Functions
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Adds a new asset to the escrow
     * @dev Only the vault router contract can call this function
     * @param assetIndex The spot index of the asset to add
     */
    function addAsset(uint32 assetIndex, AssetDetails memory details) external onlyRouter {
        V1AssetStorage storage $ = _getV1AssetStorage();
        require($.supportedAssets.length() < 5, Errors.ASSET_LIMIT_EXCEEDED());
        require(!$.supportedAssets.contains(assetIndex), Errors.ASSET_ALREADY_SUPPORTED());

        // Add the asset to the set of supported assets
        $.supportedAssets.add(assetIndex);
        $.assetDetails[assetIndex] = details;
    }

    /**
     * @notice Removes a new asset to the escrow
     * @dev Only the vault router contract can call this function
     * @dev The contract, spot & inflight balances must be zero before removing
     * @param assetIndex The spot index of the asset to remove
     */
    function removeAsset(uint64 assetIndex) external onlyRouter {
        V1AssetStorage storage $ = _getV1AssetStorage();
        require($.supportedAssets.length() >= 2, Errors.INVALID_OPERATION());
        require($.supportedAssets.contains(assetIndex), Errors.COLLATERAL_NOT_SUPPORTED());

        // Make sure the contract, spot, & inflight balances are zero before removing
        AssetDetails memory details = $.assetDetails[assetIndex];
        uint256 assetBalance = IERC20(details.evmContract).balanceOf(address(this));
        require(assetBalance == 0, Errors.INSUFFICIENT_BALANCE());
        require(_spotAssetBalance(assetIndex) == 0, Errors.INSUFFICIENT_BALANCE());
        require(_inflightBalance(assetIndex) == 0, Errors.INSUFFICIENT_BALANCE());
    
        // Remove the asset from the set of supported assets
        $.supportedAssets.remove(assetIndex);
        delete $.assetDetails[assetIndex];
    }

    /**
     * @notice Transfers funds from the escrow to the recipient
     * @param asset The address of the asset to transfer
     * @param recipient The address of the recipient
     * @param amount The amount of funds to transfer
     */
    function transferFunds(address asset, address recipient, uint256 amount) external onlyRouter {
        IERC20(asset).safeTransfer(recipient, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHyperliquidCommon
    function isAssetSupported(uint64 assetIndex) public view override returns (bool) {
        V1AssetStorage storage $ = _getV1AssetStorage();
        return $.supportedAssets.contains(assetIndex);
    }

    /// @inheritdoc IHyperliquidCommon
    function assetDetails(uint64 assetIndex) external view override returns (AssetDetails memory) {
        V1AssetStorage storage $ = _getV1AssetStorage();
        return $.assetDetails[assetIndex];
    }

    /*//////////////////////////////////////////////////////////////
                            Pure Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the storage location for the asset storage
    function _getV1AssetStorage() internal pure returns (V1AssetStorage storage $) {
        bytes32 slot = V1_ASSET_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Returns the spot asset balance
     * @param assetIndex The spot index of the asset to get the balance of
     * @return The spot asset balance
     */
    function _spotAssetBalance(uint64 assetIndex) internal view virtual returns (uint256);

    /**
     * @notice Returns the current balance of an asset that is in-flight to L1
     * @param assetIndex The asset index to check
     */
    function _inflightBalance(uint64 assetIndex) internal view virtual returns (uint256);
}
