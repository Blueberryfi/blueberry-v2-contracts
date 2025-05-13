// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {FixedPointMathLib as FpMath} from "@solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {L1EscrowActions} from "@blueberry-v2/vaults/hyperliquid/L1EscrowActions.sol";
import {IHyperliquidEscrow} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperliquidEscrow.sol";

/**
 * @title HyperliquidEscrow
 * @author Blueberry
 * @notice Holds assets for the Hyperliquid vault and provides functions for admins to actively allocate assets to
 *         different markets.
 * @dev The top level of this contract contains all logic required for calculating the TVL of the escrow accounts on both evm & core.
 *      L1EscrowActions contains the logic for liquidity management and sending asssets to & from the L1.
 *      EscrowAssetStorage contains the logic for managing the assets supported by the escrow.
 */
contract HyperliquidEscrow is IHyperliquidEscrow, L1EscrowActions {
    using EnumerableSet for EnumerableSet.UintSet;
    using FpMath for uint64;
    using FpMath for uint256;

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /*==== Precompile Addresses ====*/

    /// @notice Precompile for accessing spot balance information
    address constant SPOT_BALANCE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000801;

    /// @notice The address of the vault equity precompile, used for querying native L1 vault information & state.
    address public constant VAULT_EQUITY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;

    /// @notice Precompile for querying withdrawable/free USDC funds from perps
    address constant WITHDRAWABLE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000803;

    /// @notice Precompile for querying asset spot prices
    address constant SPOT_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;

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
                        Constructor & Initializer
    //////////////////////////////////////////////////////////////*/

    constructor(address vault, address router) L1EscrowActions(vault, router) {
        require(vault != address(0) && router != address(0), Errors.ADDRESS_ZERO());
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
        tvl_ = vaultEquity(); // scaled to 1e18
        tvl_ += usdSpotBalance(); // scaled to 1e18
        tvl_ += usdPerpsBalance(); // scaled to 1e18

        V1AssetStorage storage $ = _getV1AssetStorage();

        // Iterate through all supported assets calculate their contract and spot value
        //     and add them to the tvl
        for (uint256 i = 0; i < $.supportedAssets.length(); i++) {
            uint64 assetIndex = uint64($.supportedAssets.at(i));
            AssetDetails memory details = $.assetDetails[assetIndex];
            address assetAddr = details.evmContract;

            uint256 evmScaling = 10 ** (18 - details.evmDecimals);

            if (assetIndex == USDC_SPOT_INDEX) {
                // If the asset is USDC we only need to get the contract balance since we already queried the spot balance
                tvl_ += IERC20(assetAddr).balanceOf(address(this)) * evmScaling;
            } else {
                uint256 rate = getRate(details.spotMarket);
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
    function getRate(uint32 spotMarket) public view override returns (uint256) {
        (bool success, bytes memory result) = SPOT_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(spotMarket));
        require(success, Errors.PRECOMPILE_CALL_FAILED());
        uint256 scaledRate = uint256(abi.decode(result, (uint64))) * USDC_SPOT_SCALING;
        return scaledRate;
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
        uint256 equityInSpot = _scaleToSpotDecimals(userVaultEquity.equity);

        return (uint64(equityInSpot), userVaultEquity.lockedUntilTimestamp);
    }

    /**
     * @notice Retrieves the spot balance for a specific asset scaled to 18 decimals.
     * @param token The token index
     * @return The spot balance for the specified asset
     */
    function _spotAssetBalance(uint64 token) internal view override returns (uint256) {
        V1AssetStorage storage $ = _getV1AssetStorage();
        (bool success, bytes memory result) =
            SPOT_BALANCE_PRECOMPILE_ADDRESS.staticcall(abi.encode(address(this), token));
        require(success, Errors.PRECOMPILE_CALL_FAILED());
        SpotBalance memory balance = abi.decode(result, (SpotBalance));

        if (token == USDC_SPOT_INDEX) {
            return balance.total * USDC_SPOT_SCALING;
        }

        uint256 scaler = 10 ** (18 - $.assetDetails[token].weiDecimals);
        return balance.total * scaler;
    }

    /**
     * @notice Scales an amount from perp decimals to spot/evm decimals.
     * @param amount_ The amount to scale.
     * @return The amount scaled to spot/evm decimals.
     */
    function _scaleToSpotDecimals(uint64 amount_) internal pure returns (uint64) {
        return uint64(amount_ * (10 ** (USDC_SPOT_DECIMALS - USDC_PERP_DECIMALS)));
    }
}
