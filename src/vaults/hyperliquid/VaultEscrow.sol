// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IVaultEscrow} from "./interfaces/IVaultEscrow.sol";
import {BlueberryErrors as Errors} from "../../helpers/BlueberryErrors.sol";
import {IL1Write} from "./interfaces/IL1Write.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

/**
 * @title VaultEscrow
 * @author Blueberry
 * @notice A contract that allows for increased redeemable liquidity in the event that there are
 *         deposits locks enforced on the L1 vault. (Example: HLP 4-day lock)
 * @dev If there are no deposit locks, there only needs to be a single escrow contract. It is recommended
 *      to have at least 1 more escrow contract than the number of deposit locks enforced on the L1 vault.
 */
contract VaultEscrow is IVaultEscrow {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the l1 vault that will be the target for deposits
    address private immutable _vault;

    /// @notice The address of the vault wrapper that corresponds to this escrow account
    address private immutable _vaultWrapper;

    /// @notice The address of the asset that corresponds to this escrow account
    address private immutable _asset;

    /// @notice The index of the asset in the hyperliquid spot
    uint64 private immutable _assetIndex;

    /// @notice The number of decimals of the asset on hyperliquid evm/spot
    uint8 private immutable _evmSpotDecimals;

    /// @notice The number of decimals of the asset on hyperliquid perps
    uint8 private immutable _perpDecimals;

    /// @notice The address of the vault equity precompile, used for querying native L1 vault information & state.
    address public constant VAULT_EQUITY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;

    /// @notice The address of the hyperliquid spot bridge, used for sending tokens to L1.
    address public constant HYPERLIQUID_SPOT_BRIDGE = 0x2222222222222222222222222222222222222222;

    /// @notice The address of the write precompile, used for sending transactions to the L1.
    IL1Write public constant L1_WRITE_PRECOMPILE = IL1Write(0x3333333333333333333333333333333333333333);

    /*//////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/
    modifier onlyVaultWrapper() {
        require(msg.sender == _vaultWrapper, Errors.INVALID_SENDER());
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address wrapper_, address vault_, address asset_, uint64 assetIndex_, uint8 assetPerpDecimals_) {
        _vaultWrapper = wrapper_;
        _vault = vault_;
        _asset = asset_;
        _assetIndex = assetIndex_;
        _evmSpotDecimals = ERC20(asset_).decimals();
        _perpDecimals = assetPerpDecimals_;

        // Max approve the assets to be spent by the wrapper
        ERC20(asset_).safeApprove(wrapper_, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                                External Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultEscrow
    function deposit(uint64 amount) external onlyVaultWrapper {
        ERC20(_asset).safeTransferFrom(msg.sender, HYPERLIQUID_SPOT_BRIDGE, amount);

        uint256 amountPerp = (_perpDecimals > _evmSpotDecimals)
            ? amount / (10 ** (_perpDecimals - _evmSpotDecimals))
            : amount * (10 ** (_evmSpotDecimals - _perpDecimals));

        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(uint64(amountPerp), true);
        L1_WRITE_PRECOMPILE.sendVaultTransfer(_vault, true, uint64(amountPerp));
    }

    /// @inheritdoc IVaultEscrow
    function withdraw(uint64 assets_) external override onlyVaultWrapper {
        uint256 amountPerp = (_perpDecimals > _evmSpotDecimals)
            ? assets_ / (10 ** (_perpDecimals - _evmSpotDecimals))
            : assets_ * (10 ** (_evmSpotDecimals - _perpDecimals));

        L1_WRITE_PRECOMPILE.sendVaultTransfer(_vault, false, uint64(amountPerp));
        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(uint64(amountPerp), false);
        L1_WRITE_PRECOMPILE.sendSpot(HYPERLIQUID_SPOT_BRIDGE, _assetIndex, assets_);
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultEscrow
    function tvl() public view returns (uint256) {
        (bool success, bytes memory result) =
            VAULT_EQUITY_PRECOMPILE_ADDRESS.staticcall(abi.encode(address(this), _vault));
        require(success, "VaultEquity precompile call failed");
        UserVaultEquity memory userVaultEquity = abi.decode(result, (UserVaultEquity));
        uint256 assetBalance = ERC20(_asset).balanceOf(address(this));
        return userVaultEquity.equity + assetBalance;
    }

    /// @inheritdoc IVaultEscrow
    function vault() external view returns (address) {
        return _vault;
    }

    /// @inheritdoc IVaultEscrow
    function vaultWrapper() external view returns (address) {
        return _vaultWrapper;
    }

    /// @inheritdoc IVaultEscrow
    function asset() external view returns (address) {
        return _asset;
    }

    /// @inheritdoc IVaultEscrow
    function assetIndex() external view returns (uint64) {
        return _assetIndex;
    }
}
