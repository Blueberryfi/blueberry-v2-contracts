// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";
import {IL1Write} from "@blueberry-v2/vaults/hyperliquid/interfaces/IL1Write.sol";
import {EscrowAssetStorage} from "@blueberry-v2/vaults/hyperliquid/EscrowAssetStorage.sol";

abstract contract L1EscrowActions is EscrowAssetStorage, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/
    /// @custom:storage-location erc7201:l1.escrow.actions.v1.storage

    struct V1L1EscrowActionsStorage {
        /// @notice Last block number that an admin action was performed
        uint256 lastAdminActionBlock;
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

    /// @notice The location for the vault escrow storage
    bytes32 public constant V1_L1_ESCROW_ACTIONS_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("l1.escrow.actions.v1.storage"))) - 1)) & ~bytes32(uint256(0xff));

    /*//////////////////////////////////////////////////////////////
                            Modifiers
    //////////////////////////////////////////////////////////////*/

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
     * @param assetIndexes The indexes of the assets to bridge
     * @param amounts The amounts of the assets to bridge
     */
    function bridgeToL1(uint64[] memory assetIndexes, uint256[] memory amounts)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        singleActionBlock
    {
        V1AssetStorage storage $ = _getV1AssetStorage();
        uint256 len = assetIndexes.length;
        require(len == amounts.length, Errors.MISMATCHED_LENGTH());

        for (uint256 i = 0; i < len; i++) {
            AssetDetails memory details = $.assetDetails[assetIndexes[i]];
            IERC20(details.evmContract).transfer(_assetSystemAddr(assetIndexes[i]), amounts[i]);
        }
    }

    /**
     * @notice Bridges a spot asset from the L1 to the escrow's evm contract
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param assetIndex The index of the asset to bridge
     * @param amount The amount of the assets to pull
     */
    function bridgeFromL1(uint64 assetIndex, uint64 amount) external onlyRole(DEFAULT_ADMIN_ROLE) singleActionBlock {
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
        onlyRole(DEFAULT_ADMIN_ROLE)
        singleActionBlock
    {
        L1_WRITE_PRECOMPILE.sendIocOrder(assetIndex, isBuy, limitPx, sz);
    }

    /**
     * @notice Transfers spot USDC to perps
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in spot to transfer
     */
    function spotToPerps(uint64 amount) external onlyRole(DEFAULT_ADMIN_ROLE) singleActionBlock {
        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(amount, true);
    }

    /**
     * @notice Transfers perps USDC to spot
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in perps to transfer
     */
    function perpsToSpot(uint64 amount) external onlyRole(DEFAULT_ADMIN_ROLE) singleActionBlock {
        L1_WRITE_PRECOMPILE.sendUsdClassTransfer(amount, false);
    }

    /**
     * @notice Deposits USDC into the vault
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in perps to deposit
     */
    function vaultDeposit(uint64 amount) external onlyRole(DEFAULT_ADMIN_ROLE) singleActionBlock {
        L1_WRITE_PRECOMPILE.sendVaultTransfer(L1_VAULT, true, amount);
    }

    /**
     * @notice Withdraws USDC from the vault
     * @dev No balance validation is necessary since we track the balances of all account types to calculate tvl,
     *      so any failures can simply be retried with different parameters.
     * @param amount The amount of USDC in perps to withdraw
     */
    function vaultWithdraw(uint64 amount) external onlyRole(DEFAULT_ADMIN_ROLE) singleActionBlock {
        L1_WRITE_PRECOMPILE.sendVaultTransfer(L1_VAULT, false, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

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
