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

    function setL1BlockNumber(uint64 blockNumber_) external {
        _block = blockNumber_;
    }
}

contract MockVaultEquityPrecompile {
    struct UserVaultEquity {
        uint64 equity;
    }

    mapping(address => mapping(address => UserVaultEquity)) private _userVaultEquity;

    fallback(bytes calldata data) external returns (bytes memory) {
        (address user, address vault) = abi.decode(data, (address, address));
        return abi.encode(_userVaultEquity[user][vault]);
    }

    function setUserVaultEquity(address user_, address vault_, uint64 equity_) external {
        _userVaultEquity[user_][vault_] = UserVaultEquity({equity: equity_});
    }
}

contract MockWritePrecompile {}
