// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {FixedPointMathLib as FpMath} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@solmate/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BlueberryErrors as Errors} from "../../helpers/BlueberryErrors.sol";

import {VaultEscrow} from "./VaultEscrow.sol";
import {IHyperEvmVault} from "./interfaces/IHyperEvmVault.sol";

/**
 * @title HyperEvmVault
 * @author Blueberry
 * @notice An ERC4626 compatible vault that will be deployed on Hyperliquid EVM and will be used to tokenize
 *         any vault on Hyperliquid L1.
 */
contract HyperEvmVault is IHyperEvmVault, ERC4626, Ownable2Step, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FpMath for uint256;

    /*//////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    /// @notice The last L1 block number that has been processed by the vault
    uint256 public lastL1Block;

    /// @notice The amount of deposits that have been made in the current L1 block
    uint256 public currentBlockDeposits;

    /// @notice The last time the fees were collected
    uint256 private _lastFeeCollectionTimestamp;

    /// @notice The amount of fees that have been accumulated by the vault
    uint256 private _feesAccumulated;

    /// @notice The minimum amount of assets that can be deposited into the vault
    uint256 public minDepositAmount;

    /// @notice An array of addresses of escrow contracts for the vault
    address[] public escrows;

    /// @notice A mapping of user addresses and how much they have requested to redeem
    mapping(address => RedeemRequest) public redeemRequests;

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @notice The L1 address of the vault being deposited into
    address private immutable _l1Vault;

    /// @notice The address of the L1 block number precompile, used for querying the L1 block number.
    address public constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

    /// @notice The management fee in basis points
    uint256 public constant MANAGEMENT_FEE_BPS = 150;

    /// @notice The denominator for the performance fee
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice The number of seconds in a year
    uint256 public constant ONE_YEAR = 360 days;

    /*//////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 escrowCount_,
        ERC20 asset_,
        uint64 assetIndex_,
        uint8 assetPerpDecimals_,
        address l1Vault_,
        uint256 minDeposit_,
        address owner_
    ) ERC4626(asset_, name_, symbol_) Ownable(owner_) {
        require(l1Vault_ != address(0), Errors.ADDRESS_ZERO());

        _l1Vault = l1Vault_;
        minDepositAmount = minDeposit_;

        _deployEscrows(escrowCount_, l1Vault_, asset_, assetIndex_, assetPerpDecimals_);
    }

    /*//////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Overrides the ERC4626 deposit function to add custom fee logic + high water mark tracking
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        require(assets >= minDepositAmount, Errors.MIN_DEPOSIT_AMOUNT());
        uint256 supply = totalSupply;

        if (supply == 0) {
            // If the vault is empty then we need to initialize last fee collection timestamp
            shares = assets;
            _lastFeeCollectionTimestamp = block.timestamp;
        } else {
            shares = assets.mulDivDown(supply, _netAssets());
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        _updateBlockDeposits(assets);
        _routeDeposit(assets);
    }

    /// @notice Overrides the ERC4626 mint function to add custom fee logic + high water mark tracking
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        uint256 supply = totalSupply;

        if (supply == 0) {
            // If the vault is empty then we need to initialize high water mark & last fee collection timestamp
            assets = shares;
            _lastFeeCollectionTimestamp = block.timestamp;
        } else {
            assets = shares.mulDivDown(_netAssets(), supply);
        }

        require(assets >= minDepositAmount, Errors.MIN_DEPOSIT_AMOUNT());

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        _updateBlockDeposits(assets);
        _routeDeposit(assets);
    }

    /// @inheritdoc IHyperEvmVault
    function requestRedeem(uint256 shares_) external nonReentrant {
        uint256 balance = this.balanceOf(msg.sender);
        // Determine if the user withdrawal request is valid
        require(shares_ <= balance, "Error");

        RedeemRequest storage request = redeemRequests[msg.sender];
        request.shares += shares_;
        require(request.shares <= balance, "Error"); // UPDATE ERROR CODE

        // User will redeem assets at the current share price
        uint256 assetsToRedeem = shares_.mulDivDown(_netAssets(), totalSupply);

        request.assets += uint64(assetsToRedeem);

        emit RedeemRequested(msg.sender, shares_, assetsToRedeem);

        VaultEscrow escrowToRedeem = VaultEscrow(escrows[redeemEscrowIndex()]);
        escrowToRedeem.withdraw(uint64(assetsToRedeem));
    }

    /// @inheritdoc IHyperEvmVault
    function tvl() public view returns (uint256 tvl_) {
        tvl_ = _totalEscrowValue();
        uint256 pendingFees = previewFeeTake(tvl_) + _feesAccumulated;

        if (pendingFees < tvl_) {
            tvl_ -= pendingFees;
        } else {
            tvl_ = 0;
        }
    }

    /// @inheritdoc IHyperEvmVault
    function previewFeeTake(uint256 preFeeTvl_) public view returns (uint256 feeTake_) {
        feeTake_ = _calculateFee(preFeeTvl_);
    }

    /*//////////////////////////////////////////////////////////////
                                Overrides
    //////////////////////////////////////////////////////////////*/

    /// @notice Overrides the ERC4626 totalAssets function to return the TVL of the vault
    function totalAssets() public view override returns (uint256) {
        return tvl();
    }

    /// @notice Overrides the ERC4626 previewWithdraw function to return the amount of shares a user can withdraw
    function previewWithdraw(uint256 assets_) public view override returns (uint256) {
        RedeemRequest memory request = redeemRequests[msg.sender];
        return assets_.mulDivUp(request.shares, request.assets);
    }

    /// @notice Overrides the ERC4626 previewRedeem function to return the amount of assets a user can redeem
    function previewRedeem(uint256 shares_) public view override returns (uint256) {
        RedeemRequest memory request = redeemRequests[msg.sender];
        return shares_.mulDivDown(request.assets, request.shares);
    }

    /// @notice Overrides the ERC4626 beforeWithdraw function to update the redeem requests & retrieve assets from the
    ///         escrow contracts
    function beforeWithdraw(uint256 assets_, uint256 shares_) internal override {
        RedeemRequest memory request = redeemRequests[msg.sender];
        require(request.assets >= assets_, "Error");
        require(request.shares >= shares_, "Error");

        request.assets -= uint64(assets_);
        request.shares -= shares_;

        _fetchAssets(assets_);
    }

    /// @notice Overrides the ERC20 transfer function to enforce our transfer restrictions on pending redemptions
    function transfer(address to_, uint256 amount_) public override returns (bool) {
        _beforeTransfer(msg.sender, to_, amount_);
        return super.transfer(to_, amount_);
    }

    /// @notice Overrides the ERC20 transferFrom function to enforce our transfer restrictions on pending redemptions
    function transferFrom(address from_, address to_, uint256 amount_) public override returns (bool) {
        _beforeTransfer(from_, to_, amount_);
        return super.transferFrom(from_, to_, amount_);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal helper function for calculating the total amount of assets locked by the vault
     *         between all escrow contract + assets that still could be in flight from the previous L1 block
     * @return assets_ The total amount of assets locked by the vault
     */
    function _totalEscrowValue() internal view returns (uint256 assets_) {
        uint256 escrowLength = escrows.length;
        for (uint256 i = 0; i < escrowLength; ++i) {
            VaultEscrow escrow = VaultEscrow(escrows[i]);
            assets_ += escrow.tvl();
        }

        if (lastL1Block == l1Block()) {
            assets_ += currentBlockDeposits;
        }

        return assets_;
    }

    /**
     * @notice Internal helper function for calculating the net assets of the vault after fees have been taken
     * @dev This function updates state by updating fees accumulated & last fee collection timestamp
     * @return netAssets_ The net assets of the vault after fees have been taken
     */
    function _netAssets() internal returns (uint256) {
        uint256 grossAssets = _totalEscrowValue();
        _takeFee(grossAssets);
        uint256 accumulatedFees = _feesAccumulated;
        uint256 netAssets = grossAssets > accumulatedFees ? grossAssets - accumulatedFees : 0;
        return netAssets;
    }

    /**
     * @notice Calculates the management fee based on time elapsed since last collection
     * @param grossAssets The total value of the vault
     * @return feeAmount_ The amount of fees to take
     */
    function _calculateFee(uint256 grossAssets) internal view returns (uint256 feeAmount_) {
        if (grossAssets == 0 || block.timestamp <= _lastFeeCollectionTimestamp) {
            return 0;
        }

        // Calculate time elapsed since last fee collection
        uint256 timeElapsed = block.timestamp - _lastFeeCollectionTimestamp;

        // Calculate the pro-rated management fee based on time elapsed
        // (totalAssets * MANAGEMENT_FEE_BPS * timeElapsed) / (BPS_DENOMINATOR * SECONDS_PER_YEAR)
        feeAmount_ = grossAssets.mulDivDown(MANAGEMENT_FEE_BPS, BPS_DENOMINATOR).mulDivDown(timeElapsed, ONE_YEAR);

        return feeAmount_;
    }

    /**
     * @notice Takes the management fee from the vault
     * @dev There is a 0.05% annual management fee on the vault's total assets.
     * @param grossAssets The total value of the vault
     * @return The amount of fees to take in underlying assets
     */
    function _takeFee(uint256 grossAssets) private returns (uint256) {
        uint256 feeTake_ = _calculateFee(grossAssets);

        // Only update state if there's a fee to take
        if (feeTake_ > 0) {
            _lastFeeCollectionTimestamp = block.timestamp;
            _feesAccumulated += feeTake_;
        }

        return feeTake_;
    }

    /**
     * @notice Updates the amount of assets that have been sent to the L1 vault during the current L1 block
     * @param assets_ The amount of assets to update the block deposits with
     */
    function _updateBlockDeposits(uint256 assets_) internal {
        uint256 l1Block_ = l1Block();

        if (lastL1Block != l1Block_ || lastL1Block == 0) {
            lastL1Block = l1Block_;
            currentBlockDeposits = assets_;
        } else {
            currentBlockDeposits += assets_;
        }
    }

    /**
     * @notice Routes the deposit to the correct escrow contract to be processed on L1
     * @param assets_ The amount of assets to route to the escrow contract
     */
    function _routeDeposit(uint256 assets_) internal {
        VaultEscrow escrowToDeposit = VaultEscrow(escrows[depositEscrowIndex()]);
        asset.safeTransferFrom(msg.sender, address(escrowToDeposit), assets_);
        escrowToDeposit.deposit(uint64(assets_));
    }

    /**
     * @notice Deploys escrow contracts for the vault
     * @param escrowCount_ The number of escrow contracts to deploy
     */
    function _deployEscrows(
        uint256 escrowCount_,
        address l1Vault_,
        ERC20 asset_,
        uint64 assetindex_,
        uint8 assetPerpDecimals_
    ) internal {
        for (uint256 i = 0; i < escrowCount_; ++i) {
            VaultEscrow escrow =
                new VaultEscrow(address(this), l1Vault_, address(asset_), assetindex_, assetPerpDecimals_);
            escrows.push(address(escrow));
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
        uint256 balance = this.balanceOf(from_);
        RedeemRequest memory request = redeemRequests[from_];

        // Take a management fee on the total assets
        _netAssets();
        if (request.shares > 0) {
            require(balance - amount_ >= request.shares, "Error"); // UPDATE ERROR CODE
        }
    }

    /**
     * @notice Iterates over the escrows until the user has enough assets to redeem
     * @param assets_ The amount of assets to fetch
     */
    function _fetchAssets(uint256 assets_) internal {
        uint256 startIndex = redeemEscrowIndex();
        uint256 len = escrows.length;

        address[] memory cachedEscrows = escrows;

        for (uint256 i = 0; i < len; ++i) {
            // Get the current escrow index with a circular index
            uint256 index = (startIndex + i) % len;

            VaultEscrow escrow = VaultEscrow(cachedEscrows[index]);

            uint256 escrowBalance = asset.balanceOf(address(escrow));
            uint256 transferAmount = Math.min(assets_, escrowBalance);

            if (transferAmount > 0) {
                asset.transferFrom(address(escrow), address(this), transferAmount);
                assets_ -= transferAmount;
            }

            if (assets_ == 0) {
                break;
            }
        }

        require(assets_ == 0, "Error"); //TODO: Update with custom error
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHyperEvmVault
    function l1Vault() external view returns (address) {
        return _l1Vault;
    }

    /// @inheritdoc IHyperEvmVault
    function l1Block() public view returns (uint256) {
        (bool success, bytes memory data) = L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS.staticcall(abi.encode());
        require(success, Errors.STATICCALL_FAILED());
        return abi.decode(data, (uint64));
    }

    /// @inheritdoc IHyperEvmVault
    function depositEscrowIndex() public view returns (uint256) {
        uint256 len = escrows.length;
        if (len == 1) {
            return 0;
        }

        return (block.timestamp / 1 days) % len;
    }

    /// @inheritdoc IHyperEvmVault
    function redeemEscrowIndex() public view returns (uint256) {
        uint256 len = escrows.length;
        if (len == 1) {
            return 0;
        }

        uint256 depositIndex = depositEscrowIndex();
        return (depositIndex + 1) % len;
    }

    function feesAccumulated() public view returns (uint256) {
        return _feesAccumulated;
    }
}
