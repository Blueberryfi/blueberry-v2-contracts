// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {IL1Write} from "@blueberry-v2/vaults/hyperliquid/interfaces/IL1Write.sol";
import {IVaultEscrow} from "@blueberry-v2/vaults/hyperliquid/interfaces/IVaultEscrow.sol";

/**
 * @title VaultEscrow
 * @author Blueberry
 * @notice A contract that allows for increased redeemable liquidity in the event that there are
 *         deposits locks enforced on the L1 vault. (Example: HLP 4-day lock)
 * @dev If there are no deposit locks, there only needs to be a single escrow contract. It is recommended
 *      to have at least 1 more escrow contract than the number of deposit locks enforced on the L1 vault.
 */
contract VaultEscrow is IVaultEscrow {
    using SafeERC20 for ERC20Upgradeable;

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
        require(wrapper_ != address(0) || vault_ != address(0) || asset_ != address(0), Errors.ADDRESS_ZERO());
        require(assetPerpDecimals_ > 0, Errors.INVALID_PERP_DECIMALS());

        _vaultWrapper = wrapper_;
        _vault = vault_;
        _asset = asset_;
        _assetIndex = assetIndex_;
        _evmSpotDecimals = ERC20Upgradeable(asset_).decimals();
        _perpDecimals = assetPerpDecimals_;

        // Max approve the assets to be spent by the wrapper
        ERC20Upgradeable(asset_).forceApprove(wrapper_, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                                External Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultEscrow
    function deposit(uint64 amount) external onlyVaultWrapper {
        ERC20Upgradeable(_asset).safeTransfer(HYPERLIQUID_SPOT_BRIDGE, amount);

        uint256 amountPerp = (_perpDecimals > _evmSpotDecimals)
            ? amount * (10 ** (_perpDecimals - _evmSpotDecimals))
            : amount / (10 ** (_evmSpotDecimals - _perpDecimals));

        // Transfer assets to L1 perps
        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(uint64(amountPerp), true);
        // Deposit assets in L1 vault
        L1_WRITE_PRECOMPILE.sendVaultTransfer(_vault, true, uint64(amountPerp));
    }

    /// @inheritdoc IVaultEscrow
    function withdraw(uint64 assets_) external override onlyVaultWrapper {
        require(assets_ <= _vaultEquity(), Errors.INSUFFICIENT_VAULT_EQUITY());

        uint256 amountPerp = (_perpDecimals > _evmSpotDecimals)
            ? assets_ * (10 ** (_perpDecimals - _evmSpotDecimals))
            : assets_ / (10 ** (_evmSpotDecimals - _perpDecimals));

        // Withdraws assets from L1 vault
        L1_WRITE_PRECOMPILE.sendVaultTransfer(_vault, false, uint64(amountPerp));
        // Transfer assets to L1 spot
        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(uint64(amountPerp), false);
        // Bridges assets back to escrow's EVM account
        L1_WRITE_PRECOMPILE.sendSpot(HYPERLIQUID_SPOT_BRIDGE, _assetIndex, assets_);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    function _vaultEquity() internal view returns (uint256) {
        (bool success, bytes memory result) =
            VAULT_EQUITY_PRECOMPILE_ADDRESS.staticcall(abi.encode(address(this), _vault));
        require(success, "VaultEquity precompile call failed");

        UserVaultEquity memory userVaultEquity = abi.decode(result, (UserVaultEquity));

        uint256 equityInSpot = (_perpDecimals > _evmSpotDecimals)
            ? userVaultEquity.equity / (10 ** (_perpDecimals - _evmSpotDecimals))
            : userVaultEquity.equity * (10 ** (_evmSpotDecimals - _perpDecimals));

        return equityInSpot;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultEscrow
    function tvl() public view returns (uint256) {
        uint256 assetBalance = ERC20Upgradeable(_asset).balanceOf(address(this));
        return _vaultEquity() + assetBalance;
    }

    function vaultEquity() external view returns (uint256) {
        return _vaultEquity();
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

    /// @inheritdoc IVaultEscrow
    function assetDecimals() external view returns (uint8) {
        return _evmSpotDecimals;
    }

    /// @inheritdoc IVaultEscrow
    function assetPerpDecimals() external view returns (uint8) {
        return _perpDecimals;
    }
}
