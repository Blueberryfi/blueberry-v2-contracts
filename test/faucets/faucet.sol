// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MainnetFaucet} from "./mainnet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Faucet is Test {
    using SafeERC20 for IERC20;

    function _dripToken(string memory token, address to, uint256 amount) internal {
        if (keccak256(abi.encode(token)) == keccak256(abi.encode("USDC"))) {
            if (block.chainid == 1) {
                vm.startPrank(MainnetFaucet.USDC_WHALE);
                IERC20(MainnetFaucet.USDC).safeTransfer(to, amount);
            } else {
                revert("Faucet: Unsupported chain");
            }
        }
    }
}
