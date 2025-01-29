// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVaultEscrow} from "./interfaces/IVaultEscrow.sol";
import {BlueberryErrors as Errors} from "../../helpers/BlueberryErrors.sol";

/**
 * @title VaultEscrow
 * @author Blueberry
 * @notice A contract that allows for increased redeemable liquidity in the event that there are
 *         deposits locks enforced on the L1 vault. (Example: HLP 4-day lock)
 * @dev If there are no deposit locks, there only needs to be a single escrow contract. It is recommended
 *      to have at least 1 more escrow contract than the number of deposit locks enforced on the L1 vault.
 */
contract VaultEscrow is IVaultEscrow {
    /*//////////////////////////////////////////////////////////////
                                Immutables
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the vault that corresponds to this escrow account
    address private immutable _vault;

    /*//////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/
    modifier onlyVault() {
        require(msg.sender == _vault, Errors.INVALID_SENDER());
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address vault_) {
        _vault = vault_;
    }

    /*//////////////////////////////////////////////////////////////
                                View Functions
    //////////////////////////////////////////////////////////////*/

    function vault() external view returns (address) {
        return _vault;
    }
}
