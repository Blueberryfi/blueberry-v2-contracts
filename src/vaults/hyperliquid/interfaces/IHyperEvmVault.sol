// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IHyperEvmVault
 * @author Blueberry
 * @notice Interface for the ERC4626 compatible HyperEvmVault contract that will be deployed on Hyperliquid EVM
 */
interface IHyperEvmVault is IERC4626 {
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Emitted when a new escrow is deployed
     * @param escrow The address of the new escrow contract for the vault
     */
    event EscrowDeployed(address indexed escrow);

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice The L1 address of the vault being deposited into on Hyperliquid L1
    function l1Vault() external view returns (address);
}
