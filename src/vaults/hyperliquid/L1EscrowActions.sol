// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {EscrowAssetStorage} from "@blueberry-v2/vaults/hyperliquid/EscrowAssetStorage.sol";
import {IL1Write} from "@blueberry-v2/vaults/hyperliquid/interfaces/IL1Write.sol";

/**
 * @title L1EscrowActions
 * @author Blueberry
 * @notice This contract contains the admin logic for
 */
abstract contract L1EscrowActions is EscrowAssetStorage, AccessControlUpgradeable {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                Structs
    //////////////////////////////////////////////////////////////*/
    /// @notice Struct that contains details on the last time an asset was bridged to L1
    struct InflightBridge {
        /// @notice The evm block number that the asset was sent to L1
        uint64 blockNumber;
        /// @notice The amount of the asset that is in-flight to L1
        uint256 amount;
    }

    /*//////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/
    /// @custom:storage-location erc7201:l1.escrow.actions.v1.storage
    struct V1L1EscrowActionsStorage {
        /// @notice Last block number that an admin action was performed
        uint256 lastAdminActionBlock;
        /// @notice A mapping of asset indexes to their corresponding in-flight bridge struct
        mapping(uint64 => InflightBridge) inFlightBridge;
    }

    /*//////////////////////////////////////////////////////////////
                                Constants
    //////////////////////////////////////////////////////////////*/

    /// @notice The L1 vault address that is being tokenized
    address public immutable L1_VAULT;

    /*==== Precompile Addresses ====*/

    /// @notice The address of the write precompile, used for sending transactions to the L1.
    IL1Write public constant L1_WRITE_PRECOMPILE = IL1Write(0x3333333333333333333333333333333333333333);

    /*==== Additional Constants ====*/

    /// @notice Spot market indexes start at index 10000
    uint32 public constant SPOT_MARKET_INDEX_OFFSET = 10000;

    /// @notice The role that is granted to the admin who can direct the escrows liquidity
    bytes32 public constant LIQUIDITY_ADMIN_ROLE = keccak256("LIQUIDITY_ADMIN_ROLE");

    /// @notice The location for the vault escrow storage
    bytes32 public constant V1_L1_ESCROW_ACTIONS_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("l1.escrow.actions.v1.storage"))) - 1)) & ~bytes32(uint256(0xff));

    /*//////////////////////////////////////////////////////////////
                            Modifiers
    //////////////////////////////////////////////////////////////*/

    // This modifier prevents contract admins from interacting with the contract multiple
    //     times within a single evm block. This is to protect from the lag time in contract
    //     state that occurs between L1 on Hyperliquid Core.
    modifier singleActionBlock() {
        V1L1EscrowActionsStorage storage $ = _getV1L1EscrowActionsStorage();
        require(block.number > $.lastAdminActionBlock, Errors.TOO_FREQUENT_ACTIONS());
        $.lastAdminActionBlock = block.number;
        _;
    }

    constructor(address vault, address router) EscrowAssetStorage(router) {
        L1_VAULT = vault;
    }

    /*//////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bridge assets to the escrows L1 spot account
     * @param assetIndex The index of the assets to bridge
     * @param amount The amounts of the assets to bridge
     */
    function bridgeToL1(uint64 assetIndex, uint256 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        V1AssetStorage storage $ = _getV1AssetStorage();
        V1L1EscrowActionsStorage storage $$ = _getV1L1EscrowActionsStorage();

        AssetDetails memory details = $.assetDetails[assetIndex];
        require(details.evmContract != address(0), Errors.ADDRESS_ZERO());

        // Sanitize the amount to the correct spot decimals so åthat we dont lose small amounts in the
        //     bridging process.
        uint256 factor =
            (details.evmDecimals > details.weiDecimals) ? 10 ** (details.evmDecimals - details.weiDecimals) : 1;

        uint256 amountAdjusted = amount - (amount % factor);
        IERC20(details.evmContract).transfer(_assetSystemAddr(assetIndex), amountAdjusted);

        // Update the in-flight bridge struct with the new amount sent and block number
        $$.inFlightBridge[assetIndex] = InflightBridge({blockNumber: uint64(block.number), amount: amountAdjusted});
    }

    /**
     * @notice Bridges a spot asset from the L1 to the escrow's evm contract
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param assetIndex The index of the asset to bridge
     * @param amount The amount of the assets to pull
     */
    function bridgeFromL1(uint64 assetIndex, uint64 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        require(isAssetSupported(assetIndex), Errors.COLLATERAL_NOT_SUPPORTED());
        L1_WRITE_PRECOMPILE.sendSpot(_assetSystemAddr(assetIndex), assetIndex, amount);
    }

    /**
     * @notice Executes an IOC order on the L1
     * @dev No balance/price validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param assetIndex The index of the asset to trade
     * @param isBuy Whether to buy or sell
     * @param limitPx The limit price
     * @param sz The size of the trade
     */
    function trade(uint32 assetIndex, bool isBuy, uint64 limitPx, uint64 sz)
        external
        onlyRole(LIQUIDITY_ADMIN_ROLE)
        singleActionBlock
    {
        V1AssetStorage storage $ = _getV1AssetStorage();
        require($.supportedAssets.contains(assetIndex), Errors.COLLATERAL_NOT_SUPPORTED());
        uint32 iocIndex = SPOT_MARKET_INDEX_OFFSET + $.assetDetails[assetIndex].spotMarket;
        L1_WRITE_PRECOMPILE.sendIocOrder(iocIndex, isBuy, limitPx, sz);
    }

    /**
     * @notice Transfers spot USDC to perps
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in spot to transfer
     */
    function spotToPerps(uint64 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(amount, true);
    }

    /**
     * @notice Transfers perps USDC to spot
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in perps to transfer
     */
    function perpsToSpot(uint64 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(amount, false);
    }

    /**
     * @notice Deposits USDC into the vault
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in perps to deposit
     */
    function vaultDeposit(uint64 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        L1_WRITE_PRECOMPILE.sendVaultTransfer(L1_VAULT, true, amount);
    }

    /**
     * @notice Withdraws USDC from the vault
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in perps to withdraw
     */
    function vaultWithdraw(uint64 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        L1_WRITE_PRECOMPILE.sendVaultTransfer(L1_VAULT, false, amount);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc EscrowAssetStorage
    function _inflightBalance(uint64 assetIndex) internal view override returns (uint256) {
        V1L1EscrowActionsStorage storage $ = _getV1L1EscrowActionsStorage();
        if (block.number != $.inFlightBridge[assetIndex].blockNumber) return 0;
        return $.inFlightBridge[assetIndex].amount;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the last block number that a LIQUIDITY_ADMIN_ROLE action was performed
    function lastAdminActionBlock() public view returns (uint256) {
        V1L1EscrowActionsStorage storage $ = _getV1L1EscrowActionsStorage();
        return $.lastAdminActionBlock;
    }

    /*//////////////////////////////////////////////////////////////
                            Pure Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the L1 actions storage
     * @return $ The L1 actions storage
     */
    function _getV1L1EscrowActionsStorage() internal pure returns (V1L1EscrowActionsStorage storage $) {
        bytes32 slot = V1_L1_ESCROW_ACTIONS_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Returns the system address for an asset
     * @param token The token index
     * @return The system address for the asset
     */
    function _assetSystemAddr(uint64 token) internal pure returns (address) {
        uint160 base = uint160(0x2000000000000000000000000000000000000000);
        return address(base | uint160(token));
    }
}
