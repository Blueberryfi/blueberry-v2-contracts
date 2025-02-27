// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IL1Write
 * @notice An interface for sending transactions to the HyperLiquid L1.
 */
interface IL1Write {
    function sendIocOrder(uint32 asset, bool isBuy, uint64 limitPx, uint64 sz) external;
    function sendVaultTransfer(address vault, bool isDeposit, uint64 usd) external;
    function sendTokenDelegate(address validator, uint64 _wei, bool isUndelegate) external;
    function sendCDeposit(uint64 _wei) external;
    function sendCWithdrawal(uint64 _wei) external;
    function sendSpot(address destination, uint64 token, uint64 _wei) external;
    function sendUsdClassTransfer(uint64 ntl, bool toPerp) external;
}
