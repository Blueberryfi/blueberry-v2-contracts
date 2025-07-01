// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ICoreWriter
 * @notice An interface for sending transactions to the HyperLiquid L1.
 */
interface ICoreWriter {
    function sendRawAction(bytes calldata data) external;
}
