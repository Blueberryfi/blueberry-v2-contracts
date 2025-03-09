// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable, IERC20} from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {FixedPointMathLib as FpMath} from "@solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {VaultEscrow} from "@blueberry-v2/vaults/hyperliquid/VaultEscrow.sol";
import {IHyperEvmVault} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperEvmVault.sol";

/**
 * @title HyperEvmVault
 * @author Blueberry
 * @notice An ERC4626 compatible vault that will be deployed on Hyperliquid EVM and will be used to tokenize
 *         any vault on Hyperliquid L1.
 */
contract HyperEvmVault is IHyperEvmVault, ERC4626Upgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for ERC20Upgradeable;
    using FpMath for uint256;

    /*//////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:hyperevm.vault.v1.storage
    struct V1Storage {
        /// @notice The last L1 block number that has been processed by the vault
        uint64 lastL1Block;
        /// @notice The amount of deposits that have been made in the current L1 block
        uint64 currentBlockDeposits;
        /// @notice The last time the fees were collected
        uint64 lastFeeCollectionTimestamp;
        /// @notice The management fee in basis points
        uint64 managementFeeBps;
        /// @notice The minimum amount of assets that can be deposited into the vault
        uint64 minDepositAmount;
        /// @notice An array of addresses of escrow contracts for the vault
        address[] escrows;
        /// @notice A mapping of user addresses to their redeem requests
        mapping(address => RedeemRequest) redeemRequests;
        /// @notice The total amount of underlying assets that are in redemption requests
        uint64 totalRedeemRequests;
    }

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @notice The L1 address of the vault being deposited into
    address public immutable L1_VAULT;

    /// @notice The address of the L1 block number precompile, used for querying the L1 block number.
    address public constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

    /// @notice The denominator for the performance fee
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice The number of seconds in a year
    uint256 public constant ONE_YEAR = 360 days;

    /// @notice The location for the vault storage
    bytes32 public constant V1_VAULT_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("hyperevm.vault.storage"))) - 1)) & ~bytes32(uint256(0xff));

    /*//////////////////////////////////////////////////////////////
                        Constructor & Initializer
    //////////////////////////////////////////////////////////////*/

    constructor(address l1Vault_) {
        require(l1Vault_ != address(0), Errors.ADDRESS_ZERO());
        L1_VAULT = l1Vault_;
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address asset_,
        uint64 assetIndex_,
        uint8 assetPerpDecimals_,
        uint64 minDeposit_,
        uint256 escrowCount_,
        address owner_
    ) public initializer {
        require(owner_ != address(0), Errors.ADDRESS_ZERO());
        require(escrowCount_ > 0, Errors.AMOUNT_ZERO());

        V1Storage storage $ = _getV1Storage();

        $.minDepositAmount = minDeposit_;
        _deployEscrows($, escrowCount_, asset_, assetIndex_, assetPerpDecimals_);

        // Initialize all parent contracts
        __ERC4626_init(ERC20Upgradeable(asset_));
        __ERC20_init(name_, symbol_);
        __Ownable2Step_init();
        _transferOwnership(owner_);
        __ReentrancyGuard_init();
    }

    /*//////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Overrides the ERC4626 deposit function to add custom fee logic + high water mark tracking
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        V1Storage storage $ = _getV1Storage();
        require(assets >= $.minDepositAmount, Errors.MIN_DEPOSIT_AMOUNT());

        if (totalSupply() == 0) {
            // If the vault is empty then we need to initialize last fee collection timestamp
            shares = assets;
            $.lastFeeCollectionTimestamp = uint64(block.timestamp);
        } else {
            uint256 tvl_ = _totalEscrowValue($);
            _takeFee($, tvl_);
            shares = assets.mulDivDown(totalSupply(), tvl_);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        _updateBlockDeposits($, uint64(assets));
        _routeDeposit($, assets);
    }

    /// @notice Overrides the ERC4626 mint function to add custom fee logic + high water mark tracking
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        V1Storage storage $ = _getV1Storage();

        if (totalSupply() == 0) {
            // If the vault is empty then we need to initialize high water mark & last fee collection timestamp
            assets = shares;
            $.lastFeeCollectionTimestamp = uint64(block.timestamp);
        } else {
            uint256 tvl_ = _totalEscrowValue($);
            _takeFee($, tvl_);
            assets = shares.mulDivDown(tvl_, totalSupply()); // We do not cache total supply due to its potential to change during the fee take
        }

        require(assets >= $.minDepositAmount, Errors.MIN_DEPOSIT_AMOUNT());

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        _updateBlockDeposits($, uint64(assets));
        _routeDeposit($, assets);
    }

    /// @inheritdoc IHyperEvmVault
    function requestRedeem(uint256 shares_) external nonReentrant {
        V1Storage storage $ = _getV1Storage();
        uint256 balance = this.balanceOf(msg.sender);
        // Determine if the user withdrawal request is valid
        require(shares_ <= balance, Errors.INSUFFICIENT_BALANCE());

        RedeemRequest storage request = $.redeemRequests[msg.sender];
        request.shares += shares_;
        require(request.shares <= balance, Errors.INSUFFICIENT_BALANCE());

        // User will redeem assets at the current share price
        uint256 tvl_ = _totalEscrowValue($);
        _takeFee($, tvl_);
        uint256 assetsToRedeem = shares_.mulDivDown(tvl_, totalSupply());

        request.assets += uint64(assetsToRedeem);
        $.totalRedeemRequests += uint64(assetsToRedeem);
        emit RedeemRequested(msg.sender, shares_, assetsToRedeem);

        VaultEscrow escrowToRedeem = VaultEscrow($.escrows[redeemEscrowIndex()]);
        escrowToRedeem.withdraw(uint64(assetsToRedeem));
    }

    /// @inheritdoc IHyperEvmVault
    function tvl() public view returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        return _totalEscrowValue($);
    }

    /// @inheritdoc IHyperEvmVault
    function maxWithdrawableAssets() public view returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        VaultEscrow escrowToRedeem = VaultEscrow($.escrows[redeemEscrowIndex()]);
        return escrowToRedeem.vaultEquity();
    }

    /*//////////////////////////////////////////////////////////////
                                Overrides
    //////////////////////////////////////////////////////////////*/

    /// @notice Overrides the ERC4626 totalAssets function to return the TVL of the vault
    function totalAssets() public view override returns (uint256) {
        return tvl();
    }

    /// @notice Overrides the ERC4626 previewDeposit function to return the amount of shares a user can deposit
    function previewDeposit(uint256 assets_) public view override returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        uint256 tvl_ = _totalEscrowValue($);
        uint256 feeShares = _previewFeeShares($, tvl_);
        uint256 adjustedSupply = totalSupply() + feeShares;
        return assets_.mulDivDown(adjustedSupply, tvl_);
    }

    /// @notice Overrides the ERC4626 previewMint function to return the amount of assets a user has to deposit for a given amount of shares
    function previewMint(uint256 shares_) public view override returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        uint256 tvl_ = _totalEscrowValue($);
        uint256 feeShares = _previewFeeShares($, tvl_);
        uint256 adjustedSupply = totalSupply() + feeShares;
        return shares_.mulDivDown(tvl_, adjustedSupply);
    }

    /// @notice Overrides the ERC4626 previewWithdraw function to return the amount of shares a user can withdraw for a given amount of assets
    function previewWithdraw(uint256 assets_) public view override returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        RedeemRequest memory request = $.redeemRequests[msg.sender];
        return assets_.mulDivUp(request.shares, request.assets);
    }

    /// @notice Overrides the ERC4626 previewRedeem function to return the amount of assets a user can redeem for a given amount of shares
    function previewRedeem(uint256 shares_) public view override returns (uint256) {
        V1Storage storage $ = _getV1Storage();
        RedeemRequest memory request = $.redeemRequests[msg.sender];
        return shares_.mulDivDown(request.assets, request.shares);
    }

    /// @notice Overrides the ERC4626 _withdraw function to update the redeem requests & retrieve assets from the
    ///         escrow contracts
    function _withdraw(address caller, address receiver, address owner, uint256 assets_, uint256 shares_)
        internal
        override
    {
        _beforeWithdraw(assets_, shares_);
        super._withdraw(caller, receiver, owner, assets_, shares_);
    }

    /// @notice Updates the redeem requests & retrieves assets from the escrow contracts
    function _beforeWithdraw(uint256 assets_, uint256 shares_) internal {
        V1Storage storage $ = _getV1Storage();
        RedeemRequest memory request = $.redeemRequests[msg.sender];
        require(request.assets >= assets_, Errors.WITHDRAW_TOO_LARGE());
        require(request.shares >= shares_, Errors.WITHDRAW_TOO_LARGE());

        request.assets -= uint64(assets_);
        request.shares -= shares_;
        $.totalRedeemRequests -= uint64(assets_);

        _fetchAssets(assets_);
    }

    /// @notice Overrides the ERC20 transfer function to enforce our transfer restrictions on pending redemptions
    function transfer(address to_, uint256 amount_) public override(ERC20Upgradeable, IERC20) returns (bool) {
        _beforeTransfer(msg.sender, to_, amount_);
        return super.transfer(to_, amount_);
    }

    /// @notice Overrides the ERC20 transferFrom function to enforce our transfer restrictions on pending redemptions
    function transferFrom(address from_, address to_, uint256 amount_)
        public
        override(ERC20Upgradeable, IERC20)
        returns (bool)
    {
        _beforeTransfer(from_, to_, amount_);
        return super.transferFrom(from_, to_, amount_);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal helper function for calculating the total amount of assets locked by the vault
     *         between all escrow contract + assets that still could be in flight from the previous L1 block
     * @param $ The storage pointer to the v1 vault storage
     * @return assets_ The total amount of assets locked by the vault
     */
    function _totalEscrowValue(V1Storage storage $) internal view returns (uint256 assets_) {
        uint256 escrowLength = $.escrows.length;
        for (uint256 i = 0; i < escrowLength; ++i) {
            VaultEscrow escrow = VaultEscrow($.escrows[i]);
            assets_ += escrow.tvl();
        }

        if ($.lastL1Block == l1Block()) {
            assets_ += $.currentBlockDeposits;
        }

        return assets_;
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

        // We subtract the pending redemption requests from the total asset value to avoid taking more fees than needed from
        //    users who do not have any pending redemption requests
        uint256 eligibleForFeeTake = grossAssets - $.totalRedeemRequests;
        // Calculate the pro-rated management fee based on time elapsed
        feeAmount_ = eligibleForFeeTake * $.managementFeeBps * timeElapsed / BPS_DENOMINATOR / ONE_YEAR;

        return feeAmount_;
    }

    /**
     * @notice Internal helper function to calculate the amount of shares that will be minted for the fee collector
     * @param $ The storage pointer to the v1 vault storage
     * @param tvl_ The total value of the vault
     * @return feeShares_ The amount of shares that will be minted for the fee collector
     */
    function _previewFeeShares(V1Storage storage $, uint256 tvl_) internal view returns (uint256) {
        uint256 expectedFee = _calculateFee($, tvl_);
        return _convertToShares(expectedFee, Math.Rounding.Floor);
    }

    /**
     * @notice Takes the management fee from the vault
     * @dev There is a 0.05% annual management fee on the vault's total assets.
     * @param grossAssets The total value of the vault
     * @return The amount of fees to take in underlying assets
     */
    function _takeFee(V1Storage storage $, uint256 grossAssets) private returns (uint256) {
        uint256 feeTake_ = _calculateFee($, grossAssets);

        // Only update state if there's a fee to take
        if (feeTake_ > 0) {
            $.lastFeeCollectionTimestamp = uint64(block.timestamp);
            uint256 sharesToMint = feeTake_.mulDivDown(totalSupply(), grossAssets);
            _mint(owner(), sharesToMint);
        }
        return feeTake_;
    }

    /**
     * @notice Updates the amount of assets that have been sent to the L1 vault during the current L1 block
     * @param $ The storage pointer to the v1 vault storage
     * @param assets_ The amount of assets to update the block deposits with
     */
    function _updateBlockDeposits(V1Storage storage $, uint64 assets_) internal {
        uint64 l1Block_ = l1Block();

        if ($.lastL1Block != l1Block_ || $.lastL1Block == 0) {
            $.lastL1Block = l1Block_;
            $.currentBlockDeposits = assets_;
        } else {
            $.currentBlockDeposits += assets_;
        }
    }

    /**
     * @notice Routes the deposit to the correct escrow contract to be processed on L1
     * @param $ The storage pointer to the v1 vault storage
     * @param assets_ The amount of assets to route to the escrow contract
     */
    function _routeDeposit(V1Storage storage $, uint256 assets_) internal {
        VaultEscrow escrowToDeposit = VaultEscrow($.escrows[depositEscrowIndex()]);
        ERC20Upgradeable(asset()).safeTransferFrom(msg.sender, address(escrowToDeposit), assets_);
        escrowToDeposit.deposit(uint64(assets_));
    }

    /**
     * @notice Deploys escrow contracts for the vault
     * @param escrowCount_ The number of escrow contracts to deploy
     */
    function _deployEscrows(
        V1Storage storage $,
        uint256 escrowCount_,
        address asset_,
        uint64 assetindex_,
        uint8 assetPerpDecimals_
    ) internal {
        for (uint256 i = 0; i < escrowCount_; ++i) {
            VaultEscrow escrow = new VaultEscrow(address(this), L1_VAULT, asset_, assetindex_, assetPerpDecimals_);
            $.escrows.push(address(escrow));
            emit EscrowDeployed(address(escrow));
        }
    }

    /**
     * @notice Checks if the user has a pending redemption request & reverts the transfer if the users tries to
     *         send more shares than they have in their balance - pending redemption requests.
     * @dev This is used in order to prevent a decrease in capital efficiency that would occur if a user requested a redemption
     *      and then transferred their shares to another address before the redemption was processed.
     * @param from_ The address of the user to check
     * @param amount_ The amount of shares to check
     */
    function _beforeTransfer(address from_, address, /*to_*/ uint256 amount_) internal {
        V1Storage storage $ = _getV1Storage();
        uint256 balance = this.balanceOf(from_);
        RedeemRequest memory request = $.redeemRequests[from_];

        // Take a management fee on the total assets
        _takeFee($, _totalEscrowValue($));
        if (request.shares > 0) {
            require(balance - amount_ >= request.shares, Errors.TRANSFER_BLOCKED());
        }
    }

    /**
     * @notice Iterates over the escrows until the user has enough assets to redeem
     * @param assets_ The amount of assets to fetch
     */
    function _fetchAssets(uint256 assets_) internal {
        V1Storage storage $ = _getV1Storage();
        uint256 startIndex = redeemEscrowIndex();
        uint256 len = $.escrows.length;

        address[] memory cachedEscrows = $.escrows;

        for (uint256 i = 0; i < len; ++i) {
            // Get the current escrow index with a circular index
            uint256 index = (startIndex + i) % len;

            VaultEscrow escrow = VaultEscrow(cachedEscrows[index]);

            uint256 escrowBalance = ERC20Upgradeable(asset()).balanceOf(address(escrow));
            uint256 transferAmount = Math.min(assets_, escrowBalance);

            if (transferAmount > 0) {
                ERC20Upgradeable(asset()).transferFrom(address(escrow), address(this), transferAmount);
                assets_ -= transferAmount;
            }

            if (assets_ == 0) {
                break;
            }
        }

        require(assets_ == 0, Errors.FETCH_ASSETS_FAILED());
    }

    function _convertToShares(uint256 assets, Math.Rounding /*rounding*/ ) internal view override returns (uint256) {
        return assets.mulDivDown(totalSupply(), tvl());
    }

    function _convertToAssets(uint256 shares, Math.Rounding /*rounding*/ ) internal view override returns (uint256) {
        return shares.mulDivDown(tvl(), totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    function setManagementFeeBps(uint64 newManagementFeeBps_) external onlyOwner {
        require(newManagementFeeBps_ <= BPS_DENOMINATOR, Errors.FEE_TOO_HIGH());
        _getV1Storage().managementFeeBps = newManagementFeeBps_;
    }

    function setMinDepositAmount(uint64 newMinDepositAmount_) external onlyOwner {
        _getV1Storage().minDepositAmount = newMinDepositAmount_;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHyperEvmVault
    function l1Block() public view returns (uint64) {
        (bool success, bytes memory data) = L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS.staticcall(abi.encode());
        require(success, Errors.STATICCALL_FAILED());
        return abi.decode(data, (uint64));
    }

    /// @inheritdoc IHyperEvmVault
    function depositEscrowIndex() public view returns (uint256) {
        uint256 len = _getV1Storage().escrows.length;
        if (len == 1) {
            return 0;
        }

        return (block.timestamp / 1 days) % len;
    }

    /// @inheritdoc IHyperEvmVault
    function redeemEscrowIndex() public view returns (uint256) {
        uint256 len = _getV1Storage().escrows.length;
        if (len == 1) {
            return 0;
        }

        uint256 depositIndex = depositEscrowIndex();
        return (depositIndex + 1) % len;
    }

    function minDepositAmount() public view returns (uint256) {
        return _getV1Storage().minDepositAmount;
    }

    function escrows(uint256 index) public view returns (address) {
        return _getV1Storage().escrows[index];
    }

    function escrowsLength() public view returns (uint256) {
        return _getV1Storage().escrows.length;
    }

    function redeemRequests(address user) public view returns (RedeemRequest memory) {
        return _getV1Storage().redeemRequests[user];
    }

    function lastL1Block() public view returns (uint64) {
        return _getV1Storage().lastL1Block;
    }

    function currentBlockDeposits() public view returns (uint64) {
        return _getV1Storage().currentBlockDeposits;
    }

    function lastFeeCollectionTimestamp() public view returns (uint64) {
        return _getV1Storage().lastFeeCollectionTimestamp;
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
