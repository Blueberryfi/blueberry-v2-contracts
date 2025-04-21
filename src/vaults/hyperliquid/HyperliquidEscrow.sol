// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {IHyperliquidEscrow} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperliquidEscrow.sol";
import {IL1Write} from "@blueberry-v2/vaults/hyperliquid/interfaces/IL1Write.sol";
import {IVaultEscrow} from "@blueberry-v2/vaults/hyperliquid/interfaces/IVaultEscrow.sol";

/**
 * @title HyperliquidEscrow
 * @author Blueberry
 * @notice Holds assets for the Hyperliquid vault and provides functions for admins to actively allocate assets to
 *         different markets.
 */
contract HyperliquidEscrow is IHyperliquidEscrow, AccessControlUpgradeable {
    using EnumerableSet for EnumerableSet.UintSet;
    using FixedPointMathLib for uint64;
    using FixedPointMathLib for uint256;

    /// @custom:storage-location erc7201:hyperevm.vault.v1.storage
    struct V1Storage {
        /// @notice A set of supported assets (Asset Spot Indexes)
        EnumerableSet.UintSet supportedAssets;
        /// @notice A mapping of asset Indexes to their corresponding token info
        mapping(uint256 => Token) assetInfos;
    }

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @notice The L1 vault address thats being tokenized
    address public immutable L1_VAULT;

    /// @notice The router address with admin privileges
    address public immutable ROUTER;

    /*==== Precompile Addresses ====*/

    /// @notice Precompile for accessing spot balance information
    address constant SPOT_BALANCE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000801;

    /// @notice The address of the vault equity precompile, used for querying native L1 vault information & state.
    address public constant VAULT_EQUITY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;

    /// @notice Precompile for querying withdrawable/free USDC funds from perps
    address constant WITHDRAWABLE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000803;

    /// @notice Precompile for querying asset spot prices
    address constant SPOT_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;

    /// @notice The address of the L1 block number precompile, used for querying the L1 block number.
    address public constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

    /// @notice Precompile for querying token information
    address constant TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;

    /// @notice The address of the write precompile, used for sending transactions to the L1.
    IL1Write public constant L1_WRITE_PRECOMPILE = IL1Write(0x3333333333333333333333333333333333333333);

    /*==== USDC Constants ====*/
    /// @notice The spot index for USDC
    uint64 public constant USDC_SPOT_INDEX = 0;

    /// @notice Decimals for USDC in perpetual markets (6 decimals)
    uint8 public constant USDC_PERP_DECIMALS = 6;

    /// @notice Decimals for USDC in spot markets (8 decimals)
    uint8 public constant USDC_SPOT_DECIMALS = 8;

    /// @notice Scaling factor for USDC in spot markets
    uint256 public constant USDC_SPOT_SCALING = 10 ** (18 - USDC_SPOT_DECIMALS);

    /// @notice Scaling factor for USDC in perpetual markets
    uint256 public constant USDC_PERP_SCALING = 10 ** (18 - USDC_PERP_DECIMALS);

    /// @notice The location for the vault escrow storage
    bytes32 public constant V1_ESCROW_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("vault.escrow.v1.storage"))) - 1)) & ~bytes32(uint256(0xff));

    /*//////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/
    modifier onlyRouter() {
        require(msg.sender == ROUTER, Errors.INVALID_SENDER());
        _;
    }

    constructor(address vault_, address router) {
        require(vault_ != address(0) && router != address(0), Errors.ADDRESS_ZERO());

        L1_VAULT = vault_;
        ROUTER = router;
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHyperliquidEscrow
    function tvl() external view override returns (uint256 tvl_) {
        // Get the equity, spot, and perp USD balances
        tvl_ = vaultEquity();
        tvl_ += usdSpotBalance();
        tvl_ += usdPerpsBalance();

        V1Storage storage $ = _getV1Storage();

        // Iterate through all supported assets calculate their contract and spot value
        //     and add them to the tvl
        for (uint256 i = 0; i < $.supportedAssets.length(); i++) {
            uint256 assetIndex = $.supportedAssets.at(i);
            address assetAddr = $.assetInfos[assetIndex].evmContract;

            uint256 evmScaling = 10 ** (18 - $.assetInfos[assetIndex].evmDecimals);

            if (assetIndex == USDC_SPOT_INDEX) {
                // If the asset is USDC we only need to get the contract balance since we already queried the spot balance
                tvl_ += IERC20(assetAddr).balanceOf(address(this)) * evmScaling;
            } else {
                uint256 rate = getRate(uint64(assetIndex));
                uint256 balance = IERC20(assetAddr).balanceOf(address(this)) * evmScaling;
                balance += _spotAssetBalance(uint64(assetIndex));
                tvl_ += balance.mulWadDown(rate);
            }
        }
    }

    /// @inheritdoc IHyperliquidEscrow
    function usdSpotBalance() public view override returns (uint256) {
        return _spotAssetBalance(USDC_SPOT_INDEX);
    }

    /// @inheritdoc IHyperliquidEscrow
    function spotAssetBalance(uint64 token) external view override returns (uint256) {
        return _spotAssetBalance(token);
    }

    /// @inheritdoc IHyperliquidEscrow
    function usdPerpsBalance() public view override returns (uint256) {
        (bool success, bytes memory result) = WITHDRAWABLE_PRECOMPILE_ADDRESS.staticcall(abi.encode(address(this)));
        require(success, Errors.PRECOMPILE_CALL_FAILED());
        Withdrawable memory withdrawable = abi.decode(result, (Withdrawable));
        return uint256(withdrawable.withdrawable) * USDC_PERP_SCALING;
    }

    /// @inheritdoc IHyperliquidEscrow
    function vaultEquity() public view override returns (uint256) {
        (uint64 equity,) = _vaultEquity();
        uint256 scaledEquity = equity * USDC_SPOT_SCALING;
        return scaledEquity;
    }

    /// @inheritdoc IHyperliquidEscrow
    function getRate(uint64 token) public view override returns (uint256) {
        (bool success, bytes memory result) = SPOT_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(token));
        require(success, Errors.PRECOMPILE_CALL_FAILED());
        uint256 scaledRate = uint256(abi.decode(result, (uint64))) * USDC_SPOT_SCALING;
        return scaledRate;
    }

    /// @inheritdoc IHyperliquidEscrow
    function isAssetSupported(uint64 token) external view returns (bool) {
        V1Storage storage $ = _getV1Storage();
        return $.supportedAssets.contains(token);
    }

    /*//////////////////////////////////////////////////////////////
                        Vault Router Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new asset to the escrow
     * @dev Only the vault router contract can call this function
     * @param assetAddr The address of the asset to add
     * @param assetIndex The spot index of the asset to add
     */
    function addAsset(address assetAddr, uint32 assetIndex) external onlyRouter {
        V1Storage storage $ = _getV1Storage();
        require(assetAddr != address(0), Errors.ADDRESS_ZERO());
        require($.supportedAssets.length() < 5, Errors.ASSET_LIMIT_EXCEEDED());
        require(!$.supportedAssets.contains(assetIndex), Errors.ASSET_ALREADY_SUPPORTED());

        TokenInfo memory tokenInfo = _tokenInfo(assetIndex);
        require(tokenInfo.evmContract == assetAddr, Errors.INVALID_EVM_ADDRESS());

        // Calculate the evm Decimals using the evmExtraWeiDecimals returned from the tokenInfo
        uint8 evmDecimals = tokenInfo.evmExtraWeiDecimals > 0
            ? uint8(int8(tokenInfo.weiDecimals) + tokenInfo.evmExtraWeiDecimals)
            : tokenInfo.weiDecimals;

        // Create a new Token struct
        Token memory newToken = Token({
            evmContract: tokenInfo.evmContract,
            szDecimals: tokenInfo.szDecimals,
            weiDecimals: tokenInfo.weiDecimals,
            evmDecimals: evmDecimals
        });

        // Add the asset to the set of supported assets
        $.supportedAssets.add(assetIndex);
        $.assetInfos[assetIndex] = newToken;
    }

    /**
     * @notice Removes a new asset to the escrow
     * @dev Only the vault router contract can call this function
     * @dev The contract & spot balance must be zero before removing
     * @param assetIndex The spot index of the asset to remove
     */
    function removeAsset(uint64 assetIndex) external onlyRouter {
        V1Storage storage $ = _getV1Storage();
        require($.supportedAssets.length() >= 2, Errors.INVALID_OPERATION());
        require($.supportedAssets.contains(assetIndex), Errors.COLLATERAL_NOT_SUPPORTED());

        // Make sure the contract & spot balance is zero before removing
        Token memory token = $.assetInfos[assetIndex];
        require(IERC20(token.evmContract).balanceOf(address(this)) == 0, Errors.INSUFFICIENT_BALANCE());
        require(_spotAssetBalance(assetIndex) == 0, Errors.INSUFFICIENT_BALANCE());

        // Remove the asset from the set of supported assets
        $.supportedAssets.remove(assetIndex);
        delete $.assetInfos[assetIndex];
    }

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the vault equity and the locked until timestamp.
    function _vaultEquity() internal view returns (uint64, uint64) {
        (bool success, bytes memory result) =
            VAULT_EQUITY_PRECOMPILE_ADDRESS.staticcall(abi.encode(address(this), L1_VAULT));
        require(success, Errors.PRECOMPILE_CALL_FAILED());

        UserVaultEquity memory userVaultEquity = abi.decode(result, (UserVaultEquity));
        uint256 equityInSpot = _scaleToSpotDecimals(userVaultEquity.equity, USDC_SPOT_INDEX);

        return (uint64(equityInSpot), userVaultEquity.lockedUntilTimestamp);
    }

    /**
     * @notice Retrieves the spot balance for a specific asset scaled to 18 decimals.
     * @param token The token index
     * @return The spot balance for the specified asset
     */
    function _spotAssetBalance(uint64 token) internal view returns (uint256) {
        (bool success, bytes memory result) =
            SPOT_BALANCE_PRECOMPILE_ADDRESS.staticcall(abi.encode(address(this), token));
        require(success, Errors.PRECOMPILE_CALL_FAILED());
        SpotBalance memory balance = abi.decode(result, (SpotBalance));
        return balance.total * USDC_SPOT_SCALING;
    }

    /**
     * @notice Scales an amount from spot/evm decimals to perp decimals.
     * @param amount_ The amount to scale.
     * @return The amount scaled to perp decimals.
     */
    function _scaleToPerpDecimals(uint64 amount_, uint64 token) internal pure returns (uint64) {
        uint8 perpDecimals;
        uint8 spotDecimals;

        if (token == USDC_SPOT_INDEX) {
            perpDecimals = USDC_PERP_DECIMALS;
            spotDecimals = USDC_SPOT_DECIMALS;
        } else {
            // Handle other tokens here
            revert("Unsupported token");
        }

        return (perpDecimals > spotDecimals)
            ? uint64(amount_ * (10 ** (perpDecimals - spotDecimals)))
            : uint64(amount_ / (10 ** (spotDecimals - perpDecimals)));
    }

    /**
     * @notice Scales an amount from perp decimals to spot/evm decimals.
     * @param amount_ The amount to scale.
     * @return The amount scaled to spot/evm decimals.
     */
    function _scaleToSpotDecimals(uint64 amount_, uint64 token) internal pure returns (uint64) {
        uint8 perpDecimals;
        uint8 spotDecimals;

        if (token == USDC_SPOT_INDEX) {
            perpDecimals = USDC_PERP_DECIMALS;
            spotDecimals = USDC_SPOT_DECIMALS;
        } else {
            // Handle other tokens here
            revert("Unsupported token");
        }

        return (perpDecimals > spotDecimals)
            ? uint64(amount_ / (10 ** (perpDecimals - spotDecimals)))
            : uint64(amount_ * (10 ** (spotDecimals - perpDecimals)));
    }

    /**
     * @notice Retrieves the token information pertaining to both Hyperliquid Core & EVM for a specific asset.
     * @param token The token index
     */
    function _tokenInfo(uint32 token) internal view returns (TokenInfo memory) {
        (bool success, bytes memory result) = TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(token));
        require(success, Errors.PRECOMPILE_CALL_FAILED());
        return abi.decode(result, (TokenInfo));
    }

    /*//////////////////////////////////////////////////////////////
                            Pure Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHyperliquidEscrow
    function assetSystemAddr(uint64 token) external pure override returns (address) {
        uint160 base = uint160(0x2000000000000000000000000000000000000000);
        return address(base | uint160(token));
    }

    /// @notice Retrieves the order storage
    function _getV1Storage() private pure returns (V1Storage storage $) {
        bytes32 slot = V1_ESCROW_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }
}
