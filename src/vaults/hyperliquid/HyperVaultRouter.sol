// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FixedPointMathLib as FpMath} from "@solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {MintableToken} from "@blueberry-v2/utils/MintableToken.sol";
import {HyperliquidEscrow} from "@blueberry-v2/vaults/hyperliquid/HyperliquidEscrow.sol";
import {IHyperVaultRouter} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperVaultRouter.sol";
import {IHyperliquidEscrow} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperliquidEscrow.sol";

/**
 * @title HyperVaultRouter
 * @author Blueberry
 * @notice A vault router contract that coordinates deposits of assets into escrow contracts and handles minting and burning of share tokens
 */
contract HyperVaultRouter is IHyperVaultRouter, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;
    using FpMath for uint256;

    /*//////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:hypervault.router.v1.storage
    struct V1Storage {
        /// @notice The last time the fees were accrued
        uint64 lastFeeCollectionTimestamp;
        /// @notice The management fee in basis points
        uint64 managementFeeBps;
        /// @notice The minimum value in USD that can be deposited into the vault scaled to 1e18
        uint64 minDepositValue;
        /// @notice The asset that will be used to withdraw from the vault
        address withdrawAsset;
        /// @notice An array of addresses of escrow contracts for the vault
        address[] escrows;
        /// @notice Mapping of asset addresses to their indexes
        mapping(address => uint64) assetIndexes;
        /// @notice Mapping of asset indexes to their details
        mapping(uint64 => AssetDetails) assetDetails;
        // @notice Mapping of supported assets
        EnumerableSet.UintSet supportedAssets;
        /// @notice The address of the fee recipient
        address feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /*==== Hyperliquid Precompiles ====*/

    /// @notice Precompile for querying spot market information
    address constant SPOT_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080b;

    /// @notice Precompile for querying token information
    address constant TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;

    /*==== USDC Spot Index Constant ====*/

    /// @notice The spot index for USDC
    uint64 public constant USDC_SPOT_INDEX = 0;

    /*==== General Constants & Immutables ====*/

    /// @notice The address of the share token for the vault
    address public immutable SHARE_TOKEN;

    /// @notice The max numerator for fees
    uint256 public constant MAX_FEE_NUMERATOR = 1500;

    /// @notice The denominator for the performance fee
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice The number of seconds in a year
    uint256 public constant ONE_YEAR = 360 days;

    /*==== Storage Locations ====*/

    /// @notice The location for the vault storage
    bytes32 public constant V1_HYPERVAULT_ROUTER_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("hypervault.router.v1.storage"))) - 1)) & ~bytes32(uint256(0xff));

    /*//////////////////////////////////////////////////////////////
                        Constructor & Initializer
    //////////////////////////////////////////////////////////////*/

    constructor(address shareToken_) {
        require(shareToken_ != address(0), Errors.ADDRESS_ZERO());
        SHARE_TOKEN = shareToken_;

        _disableInitializers();
    }

    function initialize(address[] memory escrows_, uint64 minDeposit_, address owner_) public initializer {
        require(owner_ != address(0), Errors.ADDRESS_ZERO());
        // Keep escrow length small to avoid gas issues
        require(escrows_.length <= 5, Errors.INVALID_ESCROW_COUNT());

        V1Storage storage $ = _getV1Storage();

        $.minDepositValue = minDeposit_;
        $.feeRecipient = owner_; // Initial fee recipient is the owner
        $.escrows = escrows_;
        $.managementFeeBps = 150; // Initial management fee is 1.5%

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

        // Get the escrow to deposit into
        // This will also be used to calculate the USD value of the asset as all escrows have built in spot oracles
        HyperliquidEscrow escrow = HyperliquidEscrow($.escrows[depositEscrowIndex()]);

        uint64 assetIndex_ = $.assetIndexes[asset];
        require(_isAssetSupported($, assetIndex_), Errors.COLLATERAL_NOT_SUPPORTED());
        AssetDetails memory details = $.assetDetails[assetIndex_];

        // Get the USD value of the asset to properly calculate shares to mint
        uint256 scaler = 10 ** (18 - details.evmDecimals);
        uint256 usdValue = escrow.getRate(details.spotMarket).mulWadDown(amount * scaler);
        require(usdValue >= $.minDepositValue, Errors.MIN_DEPOSIT_AMOUNT());

        if (_shareSupply() == 0) {
            shares = usdValue;
            $.lastFeeCollectionTimestamp = uint64(block.timestamp);
        } else {
            uint256 tvl_ = tvl();
            _takeFee($, tvl_);
            shares = usdValue.mulDivDown(_shareSupply(), tvl_);
        }

        emit Deposit(msg.sender, asset, amount, shares);

        // Transfer the asset to the escrow contract and mint shares to user
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
        uint64 assetIndex_ = $.assetIndexes[$.withdrawAsset];
        AssetDetails memory details = $.assetDetails[assetIndex_];

        // Convert the USD amount to withdraw to the withdraw asset amount
        HyperliquidEscrow escrow = HyperliquidEscrow($.escrows[depositEscrowIndex()]);
        amount = escrow.getRate(details.spotMarket).mulWadDown(usdAmount);
        uint256 scaler = 10 ** (18 - details.evmDecimals);
        amount = amount / scaler;
        require(amount > 0, Errors.AMOUNT_ZERO());

        emit Redeem(msg.sender, shares, amount);

        // Burn the shares from the user and transfer the withdraw asset to the user
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
    function setMinDepositValue(uint64 newMinDepositValue_) external onlyOwner {
        _getV1Storage().minDepositValue = newMinDepositValue_;
    }

    /// @notice Sets the fee recipient for the vault
    function setFeeRecipient(address newFeeRecipient_) external onlyOwner {
        require(newFeeRecipient_ != address(0), Errors.INVALID_FEE_RECIPIENT());
        _getV1Storage().feeRecipient = newFeeRecipient_;
    }

    /// @notice Adds a new supported asset to all the escrows
    function addAsset(address assetAddr, uint32 assetIndex_, uint32 spotMarket) external onlyOwner {
        V1Storage storage $ = _getV1Storage();

        TokenInfo memory info = _getTokenInfo(assetIndex_);
        require(info.evmContract == assetAddr, Errors.INVALID_EVM_ADDRESS());
        require(_validateSpotMarket(assetIndex_, spotMarket), Errors.INVALID_SPOT_MARKET());

        // Calculate the evm Decimals using the evmExtraWeiDecimals returned from the tokenInfo
        uint8 evmDecimals =
            info.evmExtraWeiDecimals > 0 ? uint8(int8(info.weiDecimals) + info.evmExtraWeiDecimals) : info.weiDecimals;

        AssetDetails memory details = AssetDetails({
            evmContract: info.evmContract,
            szDecimals: info.szDecimals,
            weiDecimals: info.weiDecimals,
            evmDecimals: evmDecimals,
            spotMarket: spotMarket
        });

        // Add the asset to storage
        $.assetIndexes[assetAddr] = assetIndex_;
        $.assetDetails[assetIndex_] = details;
        $.supportedAssets.add(assetIndex_);

        // Iterate through all the escrows to add supported assets
        uint256 len = $.escrows.length;
        for (uint256 i = 0; i < len; ++i) {
            HyperliquidEscrow($.escrows[i]).addAsset(assetIndex_, details);
        }

        emit AssetAdded(assetIndex_, details);
    }

    /// @notice Removes a supported asset from all the escrows
    function removeAsset(address asset) external onlyOwner {
        V1Storage storage $ = _getV1Storage();
        uint64 assetIndex_ = $.assetIndexes[asset];

        // If the asset is the withdraw asset, set it to 0. This will prevent future withdraws until
        //     a new withdraw asset is set
        if (asset == $.withdrawAsset) {
            $.withdrawAsset = address(0);
        }
        delete $.assetIndexes[asset];
        delete $.assetDetails[assetIndex_];
        $.supportedAssets.remove(assetIndex_);

        uint256 len = $.escrows.length;
        for (uint256 i = 0; i < len; ++i) {
            HyperliquidEscrow($.escrows[i]).removeAsset(assetIndex_);
        }

        emit AssetRemoved(assetIndex_);
    }

    /// @notice Sets the withdraw asset for the vault
    function setWithdrawAsset(address asset) external onlyOwner {
        V1Storage storage $ = _getV1Storage();
        uint64 assetIndex_ = $.assetIndexes[asset];
        require(_isAssetSupported($, assetIndex_), Errors.COLLATERAL_NOT_SUPPORTED());

        $.withdrawAsset = asset;
        emit WithdrawAssetUpdated(assetIndex_);
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

    /**
     * @notice Returns the total supply of the share tokens
     * @return The total supply of the share tokens
     */
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

    /**
     * @notice Returns whether an asset is supported by the vault
     * @param $ The storage pointer to the v1 vault storage
     * @param assetIndex_ The asset index to check
     * @return Whether the asset is supported
     */
    function _isAssetSupported(V1Storage storage $, uint64 assetIndex_) internal view returns (bool) {
        return $.supportedAssets.contains(assetIndex_);
    }

    /**
     * @notice Retrieves the token info for a specific asset via Hyperliquid Precompiles
     * @param assetIndex_ The asset index to get info for
     * @return The token info for the asset
     */
    function _getTokenInfo(uint32 assetIndex_) internal view returns (TokenInfo memory) {
        (bool success, bytes memory result) = TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(assetIndex_));
        require(success, Errors.PRECOMPILE_CALL_FAILED());
        return abi.decode(result, (TokenInfo));
    }

    /**
     * @notice Validates the spot market for a specific asset by querying the Hyperliquid Precompile
     * @param assetIndex_ The asset index to validate
     * @param spotMarket The spot market index to validate
     * @return True if the spot market is valid, false otherwise
     */
    function _validateSpotMarket(uint64 assetIndex_, uint32 spotMarket) internal view returns (bool) {
        (bool success, bytes memory result) = SPOT_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(spotMarket));
        require(success, Errors.PRECOMPILE_CALL_FAILED());
        SpotInfo memory spotInfo = abi.decode(result, (SpotInfo));

        for (uint256 i = 0; i < 2; i++) {
            if (spotInfo.tokens[i] == USDC_SPOT_INDEX || spotInfo.tokens[i] == assetIndex_) {
                return true;
            }
        }
        return false;
    }

    /*//////////////////////////////////////////////////////////////
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

    /// @inheritdoc IHyperVaultRouter
    function assetIndex(address asset) external view override returns (uint64) {
        V1Storage storage $ = _getV1Storage();
        return $.assetIndexes[asset];
    }

    /// @notice IHyperVaultRouter
    function withdrawAsset() external view override returns (address) {
        V1Storage storage $ = _getV1Storage();
        return $.withdrawAsset;
    }

    /// @notice IHyperVaultRouter
    function isAssetSupported(uint64 assetIndex_) external view override returns (bool) {
        V1Storage storage $ = _getV1Storage();
        return _isAssetSupported($, assetIndex_);
    }

    /// @notice IHyperVaultRouter
    function assetDetails(uint64 assetIndex_) external view override returns (AssetDetails memory) {
        V1Storage storage $ = _getV1Storage();
        return $.assetDetails[assetIndex_];
    }

    /// @notice IHyperVaultRouter
    function lastFeeCollectionTimestamp() external view override returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        return $.lastFeeCollectionTimestamp;
    }

    /// @notice IHyperVaultRouter
    function managementFee() external view override returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        return $.managementFeeBps;
    }

    /// @notice IHyperVaultRouter
    function minDeposit() external view override returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        return $.minDepositValue;
    }

    /// @notice IHyperVaultRouter
    function feeRecipient() external view override returns (address) {
        V1Storage storage $ = _getV1Storage();
        return $.feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                            Pure Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the order storage
    function _getV1Storage() private pure returns (V1Storage storage $) {
        bytes32 slot = V1_HYPERVAULT_ROUTER_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }
}
