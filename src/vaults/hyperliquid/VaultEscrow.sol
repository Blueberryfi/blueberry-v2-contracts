// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

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
 *      For HLP we will have 7 escrow contracts.
 */
contract VaultEscrow is IVaultEscrow, Initializable {
    using SafeERC20 for ERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:vault.escrow.v1.storage
    struct V1Storage {
        /// @notice The withdraw state of the escrow.
        L1WithdrawState l1WithdrawState;
    }

    /// @notice The location for the vault escrow storage
    bytes32 public constant V1_ESCROW_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("vault.escrow.v1.storage"))) - 1)) & ~bytes32(uint256(0xff));

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

    /// @notice The address of the L1 block number precompile, used for querying the L1 block number.
    address public constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

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
                        Constructor & Initializer
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

        _disableInitializers();
    }

    function initialize() public initializer {
        // Max approve the assets to be spent by the wrapper
        ERC20Upgradeable(_asset).forceApprove(_vaultWrapper, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultEscrow
    function deposit(uint64 amount) external onlyVaultWrapper {
        ERC20Upgradeable(_asset).safeTransfer(assetSystemAddr(), amount);

        uint256 amountPerp = _scaleToPerpDecimals(amount);

        // Transfer assets to L1 perps
        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(uint64(amountPerp), true);
        // Deposit assets in L1 vault
        L1_WRITE_PRECOMPILE.sendVaultTransfer(_vault, true, uint64(amountPerp));
    }

    /// @inheritdoc IVaultEscrow
    function withdraw(uint64 assets_) external override onlyVaultWrapper {
        (uint64 vaultEquity_, uint64 lockedUntilTimestamp_) = _vaultEquity();
        require(block.timestamp > lockedUntilTimestamp_, Errors.L1_VAULT_LOCKED());

        // Update the withdraw state for the current L1 block
        L1WithdrawState storage l1WithdrawState_ = _getV1Storage().l1WithdrawState;
        _updateL1WithdrawState(l1WithdrawState_);
        l1WithdrawState_.lastWithdraws += assets_;

        // Ensure we havent exceeded requests for the current L1 block
        require(vaultEquity_ >= l1WithdrawState_.lastWithdraws, Errors.INSUFFICIENT_VAULT_EQUITY());

        // Withdraw from L1 vault
        _withdrawFromL1Vault(assets_);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the vault equity and the locked until timestamp.
    function _vaultEquity() internal view returns (uint64, uint64) {
        (bool success, bytes memory result) =
            VAULT_EQUITY_PRECOMPILE_ADDRESS.staticcall(abi.encode(address(this), _vault));
        require(success, "VaultEquity precompile call failed");

        UserVaultEquity memory userVaultEquity = abi.decode(result, (UserVaultEquity));
        uint256 equityInSpot = _scaleToSpotDecimals(userVaultEquity.equity);

        return (uint64(equityInSpot), userVaultEquity.lockedUntilTimestamp);
    }

    /// @dev Updates the withdraw state of the current L1 block.
    function _updateL1WithdrawState(L1WithdrawState storage l1WithdrawState_) internal {
        uint64 currentL1Block = l1Block();
        if (currentL1Block > l1WithdrawState_.lastWithdrawBlock) {
            l1WithdrawState_.lastWithdrawBlock = currentL1Block;
            l1WithdrawState_.lastWithdraws = 0;
        }
    }

    function _withdrawFromL1Vault(uint64 assets_) internal {
        uint256 amountPerp = _scaleToPerpDecimals(assets_);
        // Withdraws assets from L1 vault
        L1_WRITE_PRECOMPILE.sendVaultTransfer(_vault, false, uint64(amountPerp));
        // Transfer assets to L1 spot
        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(uint64(amountPerp), false);
        // Bridges assets back to escrow's EVM account
        L1_WRITE_PRECOMPILE.sendSpot(assetSystemAddr(), _assetIndex, assets_);
    }

    /**
     * @notice Scales an amount from spot/evm decimals to perp decimals.
     * @param amount_ The amount to scale.
     * @return The amount scaled to perp decimals.
     */
    function _scaleToPerpDecimals(uint256 amount_) internal view returns (uint256) {
        return (_perpDecimals > _evmSpotDecimals)
            ? amount_ * (10 ** (_perpDecimals - _evmSpotDecimals))
            : amount_ / (10 ** (_evmSpotDecimals - _perpDecimals));
    }

    /**
     * @notice Scales an amount from perp decimals to spot/evm decimals.
     * @param amount_ The amount to scale.
     * @return The amount scaled to spot/evm decimals.
     */
    function _scaleToSpotDecimals(uint256 amount_) internal view returns (uint256) {
        return (_perpDecimals > _evmSpotDecimals)
            ? amount_ / (10 ** (_perpDecimals - _evmSpotDecimals))
            : amount_ * (10 ** (_evmSpotDecimals - _perpDecimals));
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultEscrow
    function tvl() public view returns (uint256) {
        uint256 assetBalance = ERC20Upgradeable(_asset).balanceOf(address(this));
        (uint64 vaultEquity_, ) = _vaultEquity();
        return uint256(vaultEquity_) + assetBalance;
    }

    /// @inheritdoc IVaultEscrow
    function vaultEquity() external view returns (uint256) {
        (uint64 vaultEquity_, ) = _vaultEquity();
        return uint256(vaultEquity_);
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

    /// @inheritdoc IVaultEscrow
    function assetSystemAddr() public view override returns (address) {
        uint160 base = uint160(0x2000000000000000000000000000000000000000);
        return address(base | uint160(_assetIndex));
    }

    /// @dev Returns the current L1 block number.
    function l1Block() public view returns (uint64) {
        (bool success, bytes memory data) = L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS.staticcall(abi.encode());
        require(success, Errors.STATICCALL_FAILED());
        return abi.decode(data, (uint64));
    }

    /// @dev Returns the L1WithdrawState struct.
    function l1WithdrawState() external view returns (L1WithdrawState memory) {
        return _getV1Storage().l1WithdrawState;
    }

    /*//////////////////////////////////////////////////////////////
                            Pure Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the order storage
    function _getV1Storage() private pure returns (V1Storage storage $) {
        bytes32 slot = V1_ESCROW_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }
}
