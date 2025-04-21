// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {FixedPointMathLib as FpMath} from "@solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {MintableToken} from "@blueberry-v2/utils/MintableToken.sol";
import {HyperliquidEscrow} from "@blueberry-v2/vaults/hyperliquid/HyperliquidEscrow.sol";
import {IHyperVaultRouter} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperVaultRouter.sol";

/**
 * @title HyperVaultRouter
 * @author Blueberry
 * @notice A vault router contract that coordinates deposits of assets into escrow contracts
 */
contract HyperVaultRouter is IHyperVaultRouter, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using FpMath for uint256;

    /*//////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:hyperevm.vault.v1.storage
    struct V1Storage {
        /// @notice The last time the fees were accrued
        uint64 lastFeeCollectionTimestamp;
        /// @notice The management fee in basis points
        uint64 managementFeeBps;
        /// @notice The minimum amount of assets that can be deposited into the vault.
        uint64 minDepositAmount;
        /// @notice The asset that will be used to withdraw from the vault
        address withdrawAsset;
        /// @notice An array of addresses of escrow contracts for the vault
        address[] escrows;
        /// @notice Mapping of asset addresses to their indexes
        mapping(address => uint64) assetIndexes;
        /// @notice The address of the fee recipient
        address feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @notice The L1 address of the vault being deposited into
    address public immutable L1_VAULT;

    /// @notice The address of the share token for the vault
    address public immutable SHARE_TOKEN;

    /// @notice The address of the L1 block number precompile, used for querying the L1 block number.
    address public constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

    /// @notice The max numerator for fees
    uint256 public constant MAX_FEE_NUMERATOR = 1500;

    /// @notice The denominator for the performance fee
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice The number of seconds in a year
    uint256 public constant ONE_YEAR = 360 days;

    /// @notice The location for the vault storage
    bytes32 public constant V1_VAULT_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("hyperevm.vault.v1.storage"))) - 1)) & ~bytes32(uint256(0xff));

    /*//////////////////////////////////////////////////////////////
                        Constructor & Initializer
    //////////////////////////////////////////////////////////////*/

    constructor(address l1Vault_, address shareToken_) {
        require(l1Vault_ != address(0), Errors.ADDRESS_ZERO());
        require(shareToken_ != address(0), Errors.ADDRESS_ZERO());
        L1_VAULT = l1Vault_;
        SHARE_TOKEN = shareToken_;

        _disableInitializers();
    }

    function initialize(address[] memory escrows_, uint64 minDeposit_, address owner_) public initializer {
        require(owner_ != address(0), Errors.ADDRESS_ZERO());
        // Keep escrow length small to avoid gas issues
        require(escrows_.length <= 5, Errors.INVALID_ESCROW_COUNT());

        V1Storage storage $ = _getV1Storage();

        $.minDepositAmount = minDeposit_;
        $.feeRecipient = owner_; // Initial fee recipient is the owner

        // Initialize all parent contracts
        __Ownable2Step_init();
        __ReentrancyGuard_init();

        _transferOwnership(owner_);
    }

    /*///////////////////////////////////////////////////////////////
                            External Functions
    /////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHyperVaultRouter
    function deposit(address asset, uint256 amount) external override nonReentrant returns (uint256 shares) {
        V1Storage storage $ = _getV1Storage();
        require(amount >= $.minDepositAmount, Errors.MIN_DEPOSIT_AMOUNT());
        require(_isAssetSupported($, asset), Errors.COLLATERAL_NOT_SUPPORTED());

        uint64 assetIndex = $.assetIndexes[asset];
        HyperliquidEscrow escrow = HyperliquidEscrow($.escrows[depositEscrowIndex()]);

        // Get the USD value of the asset to properly calculate shares to mint
        // TODO: Scale the USD value to 18 decimals
        uint256 usdValue = escrow.getRate(assetIndex).mulWadDown(amount);

        if (_shareSupply() == 0) {
            shares = usdValue;
            $.lastFeeCollectionTimestamp = uint64(block.timestamp);
        } else {
            uint256 tvl_ = tvl();
            _takeFee($, tvl_);
            shares = usdValue.mulDivDown(_shareSupply(), tvl_);
        }

        emit Deposit(msg.sender, asset, amount, shares);

        // Transfer the asset to the contract and mint shares to user
        IERC20(asset).safeTransferFrom(msg.sender, address(escrow), amount);
        MintableToken(SHARE_TOKEN).mint(msg.sender, shares);
    }

    /// @inheritdoc IHyperVaultRouter
    function redeem(uint256 shares) external override nonReentrant returns (uint256 amount) {
        V1Storage storage $ = _getV1Storage();
        require(shares > 0, Errors.ZERO_SHARES());
        require($.withdrawAsset != address(0), Errors.ADDRESS_ZERO());

        uint256 tvl_ = tvl();
        _takeFee($, tvl_);
        uint256 usdAmount = shares.mulDivDown(tvl_, _shareSupply());

        // Get amount of withdraw asset from escrow
        HyperliquidEscrow escrow = HyperliquidEscrow($.escrows[depositEscrowIndex()]);
        uint64 assetIndex = $.assetIndexes[$.withdrawAsset];

        // Convert the USD amount to withdraw to the withdraw asset amount
        amount = escrow.getRate(assetIndex).mulWadDown(usdAmount);
        require(amount > 0, Errors.AMOUNT_ZERO());

        emit Redeem(msg.sender, shares, amount);

        // Burn the shares from the user
        MintableToken(SHARE_TOKEN).burnFrom(msg.sender, shares);

        _transferAssetsToUser($, amount);
    }

    /// @inheritdoc IHyperVaultRouter
    function tvl() public view override returns (uint256 tvl_) {
        V1Storage storage $ = _getV1Storage();

        uint256 len = $.escrows.length;
        for (uint256 i = 0; i < len; i++) {
            tvl_ += HyperliquidEscrow($.escrows[i]).tvl();
        }
    }

    /// @inheritdoc IHyperVaultRouter
    function depositEscrowIndex() public view override returns (uint256) {
        uint256 len = _getV1Storage().escrows.length;
        if (len == 1) {
            return 0;
        }

        return (block.timestamp / 2 days) % len;
    }

    /*//////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the management fee in basis points
    function setManagementFeeBps(uint64 newManagementFeeBps_) external onlyOwner {
        require(newManagementFeeBps_ < MAX_FEE_NUMERATOR, Errors.FEE_TOO_HIGH());

        V1Storage storage $ = _getV1Storage();
        if ($.lastFeeCollectionTimestamp != 0) {
            _takeFee($, tvl());
        }
        _getV1Storage().managementFeeBps = newManagementFeeBps_;
    }

    /// @notice Sets the minimum deposit amount for the vault
    function setMinDepositAmount(uint64 newMinDepositAmount_) external onlyOwner {
        _getV1Storage().minDepositAmount = newMinDepositAmount_;
    }

    /// @notice Sets the fee recipient for the vault
    function setFeeRecipient(address newFeeRecipient_) external onlyOwner {
        require(newFeeRecipient_ != address(0), Errors.INVALID_FEE_RECIPIENT());
        _getV1Storage().feeRecipient = newFeeRecipient_;
    }

    /// @notice Adds a new supported asset to all the escrows
    function addAsset(address assetAddr, uint32 assetIndex) external onlyOwner {
        V1Storage storage $ = _getV1Storage();

        uint256 len = $.escrows.length;
        for (uint256 i = 0; i < len; ++i) {
            HyperliquidEscrow($.escrows[i]).addAsset(assetAddr, assetIndex);
        }
    }

    /// @notice Sets the withdraw asset for the vault
    function setWithdrawAsset(address asset) external onlyOwner {
        V1Storage storage $ = _getV1Storage();
        require(_isAssetSupported($, asset), Errors.COLLATERAL_NOT_SUPPORTED());
        $.withdrawAsset = asset;
    }

    /// @notice Removes a supported asset from all the escrows
    function removeAsset(address asset) external onlyOwner {
        V1Storage storage $ = _getV1Storage();
        uint64 assetIndex = $.assetIndexes[asset];

        // If the asset is the withdraw asset, set it to 0. This will prevent future withdraws until
        //     a new withdraw asset is set
        if (asset == $.withdrawAsset) {
            $.withdrawAsset = address(0);
        }
        delete $.assetIndexes[asset];

        uint256 len = $.escrows.length;
        for (uint256 i = 0; i < len; ++i) {
            HyperliquidEscrow($.escrows[i]).removeAsset(assetIndex);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfers the withdraw asset from the escrows to the user
     * @param $ The storage pointer to the v1 vault storage
     * @param amount The amount of withdraw asset to transfer
     */
    function _transferAssetsToUser(V1Storage storage $, uint256 amount) private {
        uint256 remaining = amount;
        uint256 len = $.escrows.length;

        // Iterate through the escrows and withdraw until the desired amount is reached
        for (uint256 i = 0; i < len; ++i) {
            address currentEscrow = $.escrows[i];
            uint256 escrowBalance = IERC20($.withdrawAsset).balanceOf(currentEscrow);
            uint256 transferAmount = Math.min(amount, escrowBalance);

            if (transferAmount > 0) {
                // Transfer the withdraw asset from the escrow to the user
                IERC20($.withdrawAsset).safeTransferFrom(currentEscrow, msg.sender, transferAmount);
                remaining -= transferAmount;
            }
            if (remaining == 0) break;
        }

        // If there is still an amount left, revert
        require(remaining == 0, Errors.FETCH_ASSETS_FAILED());
    }

    /**
     * @notice Takes the management fee from the vault
     * @dev There is a 0.015% annual management fee on the vault's total assets.
     * @param grossAssets The total value of the vault
     */
    function _takeFee(V1Storage storage $, uint256 grossAssets) private {
        uint256 sharesToMint = _previewFeeShares($, grossAssets);

        // Even if 0 fees are collected we should still mark as the last collection time to avoid future overcharging
        $.lastFeeCollectionTimestamp = uint64(block.timestamp);

        if (sharesToMint > 0) {
            MintableToken(SHARE_TOKEN).mint($.feeRecipient, sharesToMint);
        }
    }

    function _shareSupply() internal view returns (uint256) {
        return IERC20(SHARE_TOKEN).totalSupply();
    }

    /**
     * @notice Internal helper function to calculate the amount of shares that will be minted for the fee collector
     * @param $ The storage pointer to the v1 vault storage
     * @param tvl_ The total value of the vault
     * @return feeShares_ The amount of shares that will be minted for the fee collector
     */
    function _previewFeeShares(V1Storage storage $, uint256 tvl_) internal view returns (uint256) {
        uint256 expectedFee = _calculateFee($, tvl_);
        return expectedFee.mulDivUp(_shareSupply(), tvl_ - expectedFee);
    }

    /**
     * @notice Calculates the management fee based on time elapsed since last collection
     * @param $ The storage pointer to the v1 vault storage
     * @param grossAssets The total value of the vault
     * @return feeAmount_ The amount of fees to take
     */
    function _calculateFee(V1Storage storage $, uint256 grossAssets) internal view returns (uint256 feeAmount_) {
        if (grossAssets == 0 || block.timestamp <= $.lastFeeCollectionTimestamp) {
            return 0;
        }

        // Calculate time elapsed since last fee collection
        uint256 timeElapsed = block.timestamp - $.lastFeeCollectionTimestamp;

        // Calculate the pro-rated management fee based on time elapsed
        feeAmount_ = (grossAssets * $.managementFeeBps * timeElapsed) / BPS_DENOMINATOR / ONE_YEAR;

        return feeAmount_;
    }

    function _isAssetSupported(V1Storage storage $, address asset) internal view returns (bool) {
        HyperliquidEscrow escrow = HyperliquidEscrow($.escrows[depositEscrowIndex()]);
        return escrow.isAssetSupported($.assetIndexes[asset]);
    }

    /*//////////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc IHyperVaultRouter
    function escrows(uint256 index) external view override returns (address) {
        V1Storage storage $ = _getV1Storage();
        return $.escrows[index];
    }

    /// @notice IHyperVaultRouter
    function maxWithdrawable() public view override returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        uint256 totalBalance = 0;

        uint256 len = $.escrows.length;
        for (uint256 i = 0; i < len; ++i) {
            totalBalance += IERC20($.withdrawAsset).balanceOf($.escrows[i]);
        }
        return totalBalance;
    }

    /// @notice IHyperVaultRouter
    function maxRedeemable() external view override returns (uint256) {
        uint256 maxWithdraw = maxWithdrawable();
        return maxWithdraw.mulDivDown(_shareSupply(), tvl());
    }

    /*//////////////////////////////////////////////////////////////
                            Pure Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the order storage
    function _getV1Storage() private pure returns (V1Storage storage $) {
        bytes32 slot = V1_VAULT_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }
}
