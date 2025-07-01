// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockHyperliquidPrecompiles
 * @notice Various Mock Precompiles for testing HyperEvmVault & VaultEscrow contracts
 */
contract MockL1BlockNumberPrecompile {
    uint64 private _block;

    fallback(bytes calldata) external returns (bytes memory) {
        return abi.encode(_block);
    }
}

contract MockVaultEquityPrecompile {
    struct UserVaultEquity {
        uint64 equity;
        uint64 lockedUntilTimestamp;
    }

    mapping(address => UserVaultEquity) private _userVaultEquity;

    fallback(bytes calldata data) external returns (bytes memory) {
        (address user,) = abi.decode(data, (address, address));
        return abi.encode(
            UserVaultEquity({
                equity: _userVaultEquity[user].equity,
                lockedUntilTimestamp: _userVaultEquity[user].lockedUntilTimestamp
            })
        );
    }
}

contract MockWritePrecompile {
    fallback(bytes calldata) external returns (bytes memory) {
        // Do nothing
    }
}
