// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {EscrowAssetStorage} from "@blueberry-v2/vaults/hyperliquid/EscrowAssetStorage.sol";
import {ICoreWriter} from "@blueberry-v2/vaults/hyperliquid/interfaces/ICoreWriter.sol";

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

    /// @notice Struct that encodes the params for sending tokens to spot accounts
    struct SpotSendParams {
        /// @notice Destination address to send the asset to
        address destination;
        /// @notice The index of the asset to send
        uint64 token;
        /// @notice The amount of the asset to send
        uint64 _wei;
    }

    /// @notice Struct that encodes the params for transferring USDC between perp & spot accounts
    struct UsdClassTransferParams {
        /// @notice Amount of USDC to transfer
        uint64 ntl;
        /// @notice True if transferring from spot to perp, false if transferring from perp to spot
        bool toPerp;
    }

    /// @notice Struct that encodes the params depositing or withdrawing from a vault
    struct VaultTransferParams {
        /// @notice Address of the target vault
        address vault;
        /// @notice True if depositing to the vault, false if withdrawing from the vault
        bool isDeposit;
        /// @notice Amount of USDC to deposit or withdraw
        uint64 usd;
    }

    /// @notice Struct that encodes the params for a limit order
    struct LimitOrderParams {
        /// @notice The index of the asset to trade
        uint32 asset;
        /// @notice True if the order is a buy order, false if it is a sell order
        bool isBuy;
        /// @notice The price at which the order should be executed
        uint64 limitPx;
        /// @notice The amount of the asset to trade
        uint64 sz;
        /// @notice True to reduce or close a position, false to open a new position
        bool reduceOnly;
        /// @notice The time in force for the order, 1 = Alo, 2 = Gtc, 3 = IOC
        uint8 encodedTif;
        /// @notice Client Order ID; 0 if not used
        uint128 cloid;
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
    ICoreWriter public constant L1_CORE_WRITER = ICoreWriter(0x3333333333333333333333333333333333333333);

    uint8 public constant CORE_WRITER_VERSION_1 = 1;

    uint24 public constant CORE_WRITER_ACTION_LIMIT_ORDER = 1;
    uint24 public constant CORE_WRITER_ACTION_VAULT_TRANSFER = 2;
    uint24 public constant CORE_WRITER_ACTION_SPOT_SEND = 6;
    uint24 public constant CORE_WRITER_ACTION_USD_CLASS_TRANSFER = 7;

    uint8 public constant LIMIT_ORDER_TIF_ALO = 1;
    uint8 public constant LIMIT_ORDER_TIF_GTC = 2;
    uint8 public constant LIMIT_ORDER_TIF_IOC = 3;

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

        // Sanitize the amount to the correct spot decimals so that we dont lose small amounts in the
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
        _spotSend(assetIndex, amount);
    }

    /**
     * @notice Executes an IOC order on the L1
     * @dev No balance/price validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param assetIndex The index of the asset to trade
     * @param isBuy Whether to buy or sell
     * @param limitPx The limit price
     * @param sz The size of the trade
     * @param tif The time in force for the order, 1 = Alo, 2 = Gtc, 3 = IOC
     */
    function trade(uint32 assetIndex, bool isBuy, uint64 limitPx, uint64 sz, uint8 tif)
        external
        onlyRole(LIQUIDITY_ADMIN_ROLE)
        singleActionBlock
    {
        V1AssetStorage storage $ = _getV1AssetStorage();
        require($.supportedAssets.contains(assetIndex), Errors.COLLATERAL_NOT_SUPPORTED());
        uint32 iocIndex = SPOT_MARKET_INDEX_OFFSET + $.assetDetails[assetIndex].spotMarket;
        _limitOrder(iocIndex, isBuy, limitPx, sz, tif);
    }

    /**
     * @notice Transfers spot USDC to perps
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in spot to transfer
     */
    function spotToPerps(uint64 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        _usdClassTransfer(amount, true);
    }

    /**
     * @notice Transfers perps USDC to spot
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in perps to transfer
     */
    function perpsToSpot(uint64 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        _usdClassTransfer(amount, false);
    }

    /**
     * @notice Deposits USDC into the vault
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in perps to deposit
     */
    function vaultDeposit(uint64 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        _vaultTransfer(amount, true);
    }

    /**
     * @notice Withdraws USDC from the vault
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in perps to withdraw
     */
    function vaultWithdraw(uint64 amount) external onlyRole(LIQUIDITY_ADMIN_ROLE) singleActionBlock {
        _vaultTransfer(amount, false);
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
                        Write Precompile Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encodes and sends SpotSendParams w/ a spot send action to the L1 Core Writer
     * @param assetIndex The index of the asset to send
     * @param amount The amount of the asset to send
     */
    function _spotSend(uint64 assetIndex, uint64 amount) internal {
        SpotSendParams memory action =
            SpotSendParams({destination: _assetSystemAddr(assetIndex), token: assetIndex, _wei: amount});
        L1_CORE_WRITER.sendRawAction(_encodeSpotSend(action));
    }

    /// @notice Encodes SpotSendParams into bytes for sending to the L1 Core Writer
    function _encodeSpotSend(SpotSendParams memory params) internal pure returns (bytes memory) {
        return abi.encodePacked(CORE_WRITER_VERSION_1, CORE_WRITER_ACTION_SPOT_SEND, abi.encode(params));
    }

    /**
     *  @notice Encodes and sends UsdClassTransferParams w/ a usd class transfer action to the L1 Core Writer
     *  @param amount The amount of USDC to transfer
     *  @param toPerp True if transferring from spot to perp, false if transferring from perp to spot
     */
    function _usdClassTransfer(uint64 amount, bool toPerp) internal {
        UsdClassTransferParams memory params = UsdClassTransferParams(amount, toPerp);
        L1_CORE_WRITER.sendRawAction(_encodeUsdClassTransfer(params));
    }

    /// @notice Encodes UsdClassTransferParams into bytes for sending to the L1 Core Writer
    function _encodeUsdClassTransfer(UsdClassTransferParams memory params) internal pure returns (bytes memory) {
        return abi.encodePacked(CORE_WRITER_VERSION_1, CORE_WRITER_ACTION_USD_CLASS_TRANSFER, abi.encode(params));
    }

    /**
     *  @notice Encodes and sends VaultTransferParams w/ a vault transfer action to the L1 Core Writer
     *  @param amount The amount of USDC to deposit or withdraw
     *  @param isDeposit True if depositing to the vault, false if withdrawing from the vault
     */
    function _vaultTransfer(uint64 amount, bool isDeposit) internal {
        VaultTransferParams memory params = VaultTransferParams({vault: L1_VAULT, isDeposit: isDeposit, usd: amount});
        L1_CORE_WRITER.sendRawAction(_encodeVaultTransfer(params));
    }

    /// @notice Encodes UsdClassTransferParams into bytes for sending to the L1 Core Writer
    function _encodeVaultTransfer(VaultTransferParams memory params) internal pure returns (bytes memory) {
        return abi.encodePacked(CORE_WRITER_VERSION_1, CORE_WRITER_ACTION_VAULT_TRANSFER, abi.encode(params));
    }

    /**
     * @notice Encodes and sends LimitOrderParams w/ a limit order action to the L1 Core Writer
     * @param iocIndex The index of the asset to trade
     * @param isBuy Whether to buy or sell
     * @param limitPx The limit price
     * @param sz The size of the trade
     */
    function _limitOrder(uint32 iocIndex, bool isBuy, uint64 limitPx, uint64 sz, uint8 tif) internal {
        require(tif == LIMIT_ORDER_TIF_ALO || tif == LIMIT_ORDER_TIF_GTC || tif == LIMIT_ORDER_TIF_IOC, Errors.INVALID_TIF());
        LimitOrderParams memory params = LimitOrderParams({
            asset: iocIndex,
            isBuy: isBuy,
            limitPx: limitPx,
            sz: sz,
            reduceOnly: false,
            encodedTif: tif,
            cloid: 0
        });
        L1_CORE_WRITER.sendRawAction(_encodeLimitOrderParams(params));
    }

    /// @notice Encodes a LimitOrderParams into bytes for sending to the L1 Core Writer
    function _encodeLimitOrderParams(LimitOrderParams memory params) internal pure returns (bytes memory) {
        return abi.encodePacked(CORE_WRITER_VERSION_1, CORE_WRITER_ACTION_LIMIT_ORDER, abi.encode(params));
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
