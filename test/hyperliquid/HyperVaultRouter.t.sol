// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test,console} from "forge-std/Test.sol";
import {HyperVaultRouter} from "src/vaults/hyperliquid/HyperVaultRouter.sol";
import {HyperliquidEscrow} from "src/vaults/hyperliquid/HyperliquidEscrow.sol";
import {WrappedVaultShare} from "src/vaults/hyperliquid/WrappedVaultShare.sol";
import {MintableToken} from "src/utils/MintableToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {LibRLP} from "@solady/utils/LibRLP.sol";

contract HyperVaultRouterTest is Test {
    struct TokenInfo {
        string name;
        uint64[] spots;
        uint64 deployerTradingFeeShare;
        address deployer;
        address evmContract;
        uint8 szDecimals;
        uint8 weiDecimals;
        int8 evmExtraWeiDecimals;
    }

    struct SpotInfo {
        string name;
        uint64[2] tokens;
    }

    struct SpotBalance {
        uint64 total;
        uint64 hold;
        uint64 entryNtl;
    }

    address public constant L1_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0;

    // Constants
    uint64 constant USDC_SPOT_INDEX = 0;
    uint64 constant PURR_SPOT_INDEX = 1;
    
    // Contracts
    HyperVaultRouter public router;
    WrappedVaultShare public shareToken;
    HyperliquidEscrow public escrow1;
    HyperliquidEscrow public escrow2;
    HyperliquidEscrow public escrow3;
    address[] public escrows;
    
    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public purr;
    
    // Test addresses
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    uint256 escrowCounts = 3;

    modifier initialDeposit() {
        // Demonstrate the initial deposit of 10 USDC from the admins.
        vm.startPrank(admin);
        usdc.mint(admin, 10e6);
        usdc.approve(address(router), 10e6);
        router.deposit(address(usdc), 10e6, 0);
        vm.stopPrank();
        _;
    }
    
    // Setup function
    function setUp() public {
        address deployer = admin;

        // Deploy mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        purr = new MockERC20("PURR", "PURR", 18);

        vm.startPrank(deployer);

        // 1. Compute the expected address of the vault wrapper
        address expectedRouter = LibRLP.computeAddress(deployer, vm.getNonce(deployer) + 4 + escrowCounts);

        // 2. Deploy Share Token & Mock Asset
        shareToken = new WrappedVaultShare("Wrapped HLP", "wHLP", expectedRouter, deployer);

        // 3. Deploy the HyperliquidEscrow via the Beacon Proxy Pattern
        // 3(a). Deploy Escrow Implementation Contract
        address escrowImplementation = address(
            new HyperliquidEscrow(
                L1_VAULT, // L1 Vault
                expectedRouter // vault router address
            )
        );

        // 3(b). Deploy the Beacon and set the Implementation & Owner
        UpgradeableBeacon beacon = new UpgradeableBeacon(escrowImplementation, deployer);

        // 3(c). Deploy all escrow proxies
        for (uint256 i = 0; i < escrowCounts; i++) {
            address escrowProxy = address(
                new BeaconProxy(
                    address(beacon), abi.encodeWithSelector(HyperliquidEscrow.initialize.selector, deployer)
                )
            );
            escrows.push(escrowProxy);
            bytes32 role = keccak256("LIQUIDITY_ADMIN_ROLE");
            HyperliquidEscrow(escrowProxy).grantRole(role, admin);
        }

        escrow1 = HyperliquidEscrow(escrows[0]);
        escrow2 = HyperliquidEscrow(escrows[1]);
        escrow3 = HyperliquidEscrow(escrows[2]);

        // 4. Deploy the HyperVaultRouter via the UUPS Proxy Pattern
        // 4(a). Deploy the Implementation Contract
        address implementation = address(new HyperVaultRouter(address(shareToken)));

        // 4(b). Deploy the Proxy Contract
        router = HyperVaultRouter(
            address(
                new TransparentUpgradeableProxy(
                    implementation,
                    admin,
                    abi.encodeWithSelector(
                        HyperVaultRouter.initialize.selector,
                        escrows,
                        10e18, // Min Deposit Amount
                        deployer // Owner
                    )
                )
            )
        );

        require(address(router) == expectedRouter, "Router address mismatch");

        vm.stopPrank();

        TokenInfo memory usdcInfo = TokenInfo({
            name: "USDC",
            spots: new uint64[](0),
            deployerTradingFeeShare: 0,
            deployer: address(0),
            evmContract: address(usdc),
            szDecimals: 6,
            weiDecimals: 6,
            evmExtraWeiDecimals: 0
        });

        TokenInfo memory purrInfo = TokenInfo({
            name: "PURR",
            spots: new uint64[](0),
            deployerTradingFeeShare: 0,
            deployer: address(0),
            evmContract: address(purr),
            szDecimals: 6,
            weiDecimals: 6,
            evmExtraWeiDecimals: 0
        });

        SpotInfo memory purrSpotInfo = SpotInfo({
            name: "PURR/USDC",
            tokens: [PURR_SPOT_INDEX, USDC_SPOT_INDEX]
        });
        
        // Setup mock token info.
        vm.mockCall(
            address(0x000000000000000000000000000000000000080C), // TOKEN_INFO_PRECOMPILE_ADDRESS
            abi.encode(USDC_SPOT_INDEX),
            abi.encode(usdcInfo)
        );
        
        vm.mockCall(
            address(0x000000000000000000000000000000000000080C), // TOKEN_INFO_PRECOMPILE_ADDRESS
            abi.encode(PURR_SPOT_INDEX),
            abi.encode(purrInfo)
        );

        // Setup mock spot info
        vm.mockCall(
            address(0x080B), // SPOT_INFO_PRECOMPILE_ADDRESS
            abi.encode(1), // spot market 1
            abi.encode(purrSpotInfo)
        );
        
        vm.startPrank(admin);

        // Add USDC as supported asset
        router.addAsset(address(usdc), uint32(USDC_SPOT_INDEX), 0);
        
        // Add PURR as supported asset
        router.addAsset(address(purr), uint32(PURR_SPOT_INDEX), 1);
        
        // Set USDC as withdraw asset
        router.setWithdrawAsset(address(usdc));

        vm.stopPrank();
        
        // Mint tokens to users
        usdc.mint(user1, 1000e6);
        purr.mint(user1, 10e18);
        usdc.mint(user2, 1000e6);
        purr.mint(user2, 10e18);
    }
    
    // Helper function to mock TVL
    function mockTVL(uint256 tvl_) internal {
        // Dictate what the TVL of the all escrows would be. One of them would be `tvl_` and the others `0`.
        uint256 escrow = router.depositEscrowIndex();

        if (escrow == 0) {
            vm.mockCall(
                address(escrow1),
                abi.encodeWithSelector(HyperliquidEscrow.tvl.selector),
                abi.encode(tvl_)
            );
            vm.mockCall(
                address(escrow2),
                abi.encodeWithSelector(HyperliquidEscrow.tvl.selector),
                abi.encode(0)
            );
            vm.mockCall(
                address(escrow3),
                abi.encodeWithSelector(HyperliquidEscrow.tvl.selector),
                abi.encode(0)
            );
        } else if (escrow == 1) {
            vm.mockCall(
                address(escrow1),
                abi.encodeWithSelector(HyperliquidEscrow.tvl.selector),
                abi.encode(0)
            );
            vm.mockCall(
                address(escrow2),
                abi.encodeWithSelector(HyperliquidEscrow.tvl.selector),
                abi.encode(tvl_)
            );
            vm.mockCall(
                address(escrow3),
                abi.encodeWithSelector(HyperliquidEscrow.tvl.selector),
                abi.encode(0)
            );
        } else if (escrow == 2) {
            vm.mockCall(
                address(escrow1),
                abi.encodeWithSelector(HyperliquidEscrow.tvl.selector),
                abi.encode(0)
            );
            vm.mockCall(
                address(escrow2),
                abi.encodeWithSelector(HyperliquidEscrow.tvl.selector),
                abi.encode(0)
            );
            vm.mockCall(
                address(escrow3),
                abi.encodeWithSelector(HyperliquidEscrow.tvl.selector),
                abi.encode(tvl_)
            );
        }
    }
    
    // Helper function to mock rate
    function mockRate(uint256 rate_) internal {
        vm.mockCall(
            address(escrow1),
            abi.encodeWithSelector(HyperliquidEscrow.getRate.selector),
            abi.encode(rate_)
        );
        vm.mockCall(
            address(escrow2),
            abi.encodeWithSelector(HyperliquidEscrow.getRate.selector),
            abi.encode(rate_)
        );
        vm.mockCall(
            address(escrow3),
            abi.encodeWithSelector(HyperliquidEscrow.getRate.selector),
            abi.encode(rate_)
        );
    }
    
    // Test deposit with USDC
    function testDepositUSDC() public initialDeposit {
        uint256 depositAmount = 20e6; // 20e6 USDC
        uint256 minOut = 0;

        // Mock TVL to be 10e18 for first deposit since this amount were deposited by admin.
        mockTVL(10e18);
        
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, minOut);
        vm.stopPrank();

        assertEq(shares, depositAmount * 1e12); // Scale to 18 decimals
        assertEq(shareToken.balanceOf(user1), shares);
    }

    // Test deposit with PURR
    function testDepositPURR() public initialDeposit {
        uint256 depositAmount = 1e18; // 1 PURR
        uint256 minOut = 0;
        
        mockTVL(10e18);
        // Mock PURR price to be 20 USDC for 1.
        mockRate(20e6);
        
        vm.startPrank(user1);
        purr.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(purr), depositAmount, minOut);
        vm.stopPrank();
        
        assertEq(shares, 20e18); // 1 PURR * 20e18 USDC
        assertEq(shareToken.balanceOf(user1), shares);
    }

    // Test deposit with unsupported asset
    function testDepositUnsupportedAsset() public initialDeposit {
        MockERC20 unsupportedToken = new MockERC20("UNSUPPORTED", "UNSP", 18);
        uint256 depositAmount = 1e18;
        
        vm.startPrank(user1);
        unsupportedToken.mint(user1, depositAmount);
        unsupportedToken.approve(address(router), depositAmount);
        vm.expectRevert();
        router.deposit(address(unsupportedToken), depositAmount, 0);
        vm.stopPrank();
    }

    // Test deposit with slippage protection
    function testDepositWithSlippage() public initialDeposit {
        uint256 depositAmount = 20e6; // 20 USDC
        uint256 minOut = 21e18; // Expect more shares than possible
        
        mockTVL(10e18);
        
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        vm.expectRevert();
        router.deposit(address(usdc), depositAmount, minOut);
        vm.stopPrank();
    }

    // Test deposit with zero amount
    function testDepositZeroAmount() public initialDeposit {
        vm.startPrank(user1);
        usdc.approve(address(router), 0);
        vm.expectRevert();
        router.deposit(address(usdc), 0, 0);
        vm.stopPrank();
    }

    // Test deposit with minimum deposit requirement
    function testDepositBelowMinimum() public initialDeposit {
        uint256 depositAmount = 5e6; // 5 USDC (below min deposit of 10e18)
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        vm.expectRevert();
        router.deposit(address(usdc), depositAmount, 0);
        vm.stopPrank();
    }

    // Test deposit with multiple users
    function testDepositMultipleUsers() public initialDeposit {
        uint256 depositAmount1 = 20e6; // 20 USDC
        uint256 depositAmount2 = 30e6; // 30 USDC
        
        // First user deposits
        mockTVL(10e18);
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount1);
        uint256 shares1 = router.deposit(address(usdc), depositAmount1, 0);
        vm.stopPrank();
        
        // Second user deposits
        mockTVL(30e18);
        vm.startPrank(user2);
        usdc.approve(address(router), depositAmount2);
        uint256 shares2 = router.deposit(address(usdc), depositAmount2, 0);
        vm.stopPrank();
        
        // Check share distribution
        assertEq(shares1, depositAmount1 * 1e12);
        assertEq(shares2, depositAmount2 * 1e12);
        assertEq(shareToken.totalSupply(), shares1 + shares2 + 10e18);
        assertEq(shareToken.balanceOf(user1), shares1);
        assertEq(shareToken.balanceOf(user2), shares2);
    }

    // Test subsequent deposit (when share supply > 0)
    function testSubsequentDeposit() public initialDeposit {
        uint256 depositAmount = 10e6; // 10 USDC
        mockTVL(10e18);
        
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 firstShares = router.deposit(address(usdc), depositAmount, 0);
        
        // Second deposit
        uint256 secondDeposit = 20e6; // 20 USDC
        mockTVL(20e18); // TVL is now 20 USDC
        usdc.approve(address(router), secondDeposit);
        uint256 secondShares = router.deposit(address(usdc), secondDeposit, 0);
        vm.stopPrank();

        // Second deposit should get proportionally more shares
        assertEq(secondShares, 20e18); // 20 USDC worth of shares
        assertEq(shareToken.balanceOf(user1), firstShares + secondShares);
        assertEq(shareToken.totalSupply(), 10e18 + firstShares + secondShares);
    }

    // Test deposit with PURR token and slippage
    function testDepositPURRWithSlippage() public initialDeposit {
        uint256 depositAmount = 1e18; // 1 PURR
        uint256 minOut = 21e18; // Expect more shares than possible
        
        mockTVL(10e18);
        mockRate(20e6);
        
        vm.startPrank(user1);
        purr.approve(address(router), depositAmount);
        vm.expectRevert();
        router.deposit(address(purr), depositAmount, minOut);
        vm.stopPrank();
    }
    
    // Test deposit with huge TVL and little deposit
    function testDepositRoundsToZeroShares() public initialDeposit {
        // huge TVL, tiny deposit
        mockTVL(1e30); // TVL = 1e30
        uint256 depositAmount = 1; // 1 wei
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        vm.expectRevert();
        router.deposit(address(usdc), depositAmount, 0);
        vm.stopPrank();
    }

    // Test admin sells, and user gets fresh
    function testDepositOnEmptySupplyAfterAdminRedeem() public initialDeposit {
        mockTVL(10e18);
        // 1) Admin redeems all of their shares
        uint256 adminShares = shareToken.balanceOf(admin);
        vm.startPrank(admin);
        shareToken.approve(address(router), adminShares);
        uint256 redeemed = router.redeem(adminShares, 0);
        vm.stopPrank();
        assertEq(shareToken.totalSupply(), 0);

        mockTVL(0);

        // 2) Now user1 makes a fresh deposit (supply == 0)
        uint256 depositAmount = 10e6; // 10 USDC (6 decimals)
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, 0);
        vm.stopPrank();

        mockTVL(10e18);

        // For initial deposits when supply == 0, shares == usdValue == depositAmount * 1e12
        assertEq(shares, depositAmount * 1e12);
        assertEq(shareToken.balanceOf(user1), shares);
    }

    // Test fee accrual
    function testDepositAccruesManagementFee() public initialDeposit {
        uint256 initialAdminShares = shareToken.balanceOf(admin);

        // Mock TVL equal to initial deposit value
        mockTVL(10e18);

        uint256 depositAmount = 10e6; // 10 USDC
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        router.deposit(address(usdc), depositAmount, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 360 days);

        // Mock TVL to be 20 USDC initial + 5 USDC accrued yield
        mockTVL(20e18 + 5e18);
        usdc.mint(escrows[router.depositEscrowIndex()], 5e6); // mint the yield
        router.pokeFees();

        uint256 adminSharesAfter = shareToken.balanceOf(admin);
        assertGt(adminSharesAfter, initialAdminShares);
    }

    // Test revert for zero shares
    function testDepositZeroSharesReverts() public initialDeposit {
        // Simulate huge TVL so new shares round down to zero.
        mockTVL(1e40);

        uint256 depositAmount = 10e6; // meets min deposit check

        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        vm.expectRevert();
        router.deposit(address(usdc), depositAmount, 0);
        vm.stopPrank();
    }

    // Test empty router
    function testFirstDepositByUserWorksEvenWithoutAdmin() public {
        mockTVL(0);

        uint256 depositAmount = 10e6; // meets minDepositValue
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, 0);
        vm.stopPrank();

        // Should mint exactly usdValue == 10e6 * 1e12
        assertEq(shares, depositAmount * 1e12);
        assertEq(shareToken.balanceOf(user1), shares);
    }

    // Test TVL goes to zero with non zero shares.
    function testDepositRevertsWhenTvlZeroAndSupplyNonZero() public initialDeposit {
        // shareSupply > 0 but tvl() == 0, deposit() will hit a division-by-zero and revert.
        // Force tvl() to return zero maybe because all money were lost or something happened in the vaults.
        mockTVL(0);

        uint256 depositAmount = 10e6; // 10 USDC
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        vm.expectRevert(); // division by zero in mulDivDown
        router.deposit(address(usdc), depositAmount, 0);
        vm.stopPrank();
    }

    // Test deposit with exact
    function testDepositSucceedsWithExactMinOut() public initialDeposit {
        mockTVL(10e18);

        uint256 depositAmount = 20e6;   // 20 USDC
        uint256 expectedShares = 20e18; // shareSupply * (usdValue/tvl) = 10e18 * (20e18/10e18)
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, expectedShares);
        vm.stopPrank();

        assertEq(shares, expectedShares, "Should mint exactly expectedShares");
    }

    // Test not supported asset with USDC not supported too
    function testDepositRevertsWhenAssetNotSupported() public {
        // Depositing a unsupported asset when USDC is also unsupported will hit COLLATERAL_NOT_SUPPORTED error.

        // Add USDT as supported in order to remove USDC (we must have >=2 supported)
        MockERC20 usdt = new MockERC20("USDT", "USDT", 6);

        TokenInfo memory usdtInfo = TokenInfo({
            name: "USDT",
            spots: new uint64[](0),
            deployerTradingFeeShare: 0,
            deployer: address(0),
            evmContract: address(usdt),
            szDecimals: 6,
            weiDecimals: 6,
            evmExtraWeiDecimals: 0
        });

        SpotInfo memory usdtSpotInfo = SpotInfo({
            name: "USDT/USDC",
            tokens: [4, USDC_SPOT_INDEX]
        });
        
        vm.mockCall(
            address(0x000000000000000000000000000000000000080C),
            abi.encode(4),
            abi.encode(usdtInfo)
        );

        vm.mockCall(
            address(0x080B), // SPOT_INFO_PRECOMPILE_ADDRESS
            abi.encode(4), // spot market 4
            abi.encode(usdtSpotInfo)
        );
        
        vm.startPrank(admin);

        // Add USDT as supported asset.
        router.addAsset(address(usdt), uint32(4), 4);

        vm.mockCall(
            address(0x0000000000000000000000000000000000000801), // SPOT_BALANCE_PRECOMPILE_ADDRESS
            abi.encode(address(escrow1), USDC_SPOT_INDEX),
            abi.encode(SpotBalance({
                total: 0,
                hold: 0,
                entryNtl: 0
            }))
        );

        vm.mockCall(
            address(0x0000000000000000000000000000000000000801), // SPOT_BALANCE_PRECOMPILE_ADDRESS
            abi.encode(address(escrow2), USDC_SPOT_INDEX),
            abi.encode(SpotBalance({
                total: 0,
                hold: 0,
                entryNtl: 0
            }))
        );

        vm.mockCall(
            address(0x0000000000000000000000000000000000000801), // SPOT_BALANCE_PRECOMPILE_ADDRESS
            abi.encode(address(escrow3), USDC_SPOT_INDEX),
            abi.encode(SpotBalance({
                total: 0,
                hold: 0,
                entryNtl: 0
            }))
        );

        vm.startPrank(admin);
        router.setWithdrawAsset(address(purr));
        router.removeAsset(address(usdc));
        vm.stopPrank();

        vm.startPrank(user1);
        usdc.mint(user1, 10e6);
        usdc.approve(address(router), 10e6);
        vm.expectRevert(); // COLLATERAL_NOT_SUPPORTED
        router.deposit(address(usdc), 10e6, 0);
        vm.stopPrank();
    }

    // Test redeem USDC
    function testRedeemUSDC() public initialDeposit {
        // First deposit some USDC
        uint256 depositAmount = 100e6; // 100 USDC
        mockTVL(10e18);
        
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, 0);
        
        // Mock TVL to be 100 USDC
        mockTVL(110e18);
        
        // Approve router to burn shares
        shareToken.approve(address(router), shares);
        
        // Redeem all shares
        uint256 redeemed = router.redeem(shares, 0);
        vm.stopPrank();
        
        assertEq(redeemed, depositAmount);
        assertEq(shareToken.balanceOf(user1), 0);
    }

    // Test redeem PURR
    function testRedeemPURR() public initialDeposit {
        // First deposit some PURR
        uint256 depositAmount = 1e18; // 1 ETH

        mockTVL(10e18);
        mockRate(20e6);
        
        vm.startPrank(user1);
        purr.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(purr), depositAmount, 0);
        vm.stopPrank();
        
        mockTVL(30e18);

        // User 2 deposit USDC since it is the `withdrawAsset`.
        vm.startPrank(user2);
        usdc.approve(address(router), 20e6);
        uint256 shares2 = router.deposit(address(usdc), 20e6, 0);
        vm.stopPrank();

        vm.startPrank(user1);

        mockTVL(50e18);
        
        // Approve router to burn shares
        shareToken.approve(address(router), shares);
        
        // Redeem all shares for the withdrawAsset which is USDC
        uint256 redeemed = router.redeem(shares, 0);
        vm.stopPrank();
        
        assertEq(redeemed, 20e6);
        assertEq(shareToken.balanceOf(user1), 0);
    }

    // Test redeem with zero shares
    function testRedeemZeroShares() public initialDeposit {
        vm.startPrank(user1);
        vm.expectRevert();
        router.redeem(0, 0);
        vm.stopPrank();
    }

    // Test deposit and redeem with yield
    function testDepositRedeemWithYield() public initialDeposit {
        uint256 depositAmount = 100e6; // 100 USDC
        
        mockTVL(10e18);

        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, 0);
        
        // Move time forward 1 year to accrue fees
        vm.warp(block.timestamp + 365 days);
        
        // Mock TVL to be 110 USDC initial + 5 USDC accrued yield
        mockTVL(110e18 + 5e18);
        usdc.mint(escrows[router.depositEscrowIndex()], 5e6); // mint the yield
        
        // Approve router to burn shares
        shareToken.approve(address(router), shares);
        
        // Redeem all shares
        uint256 redeemed = router.redeem(shares, 0);
        vm.stopPrank();
        
        assertTrue(redeemed > depositAmount);
        assertEq(shareToken.balanceOf(user1), 0);
    }

    // Test redeem with demanding more as minOut
    function testRedeemWithSlippageProtection() public initialDeposit {
        // user1 deposits 50 USDC
        uint256 depositAmount = 50e6;

        mockTVL(10e18);

        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, 0);
        vm.stopPrank();

        mockTVL(60e18);

        // 3) Now ask redeem() with minOut == 51
        vm.startPrank(user1);
        shareToken.approve(address(router), shares);
        vm.expectRevert(); // slippage guard
        router.redeem(shares, 51e6);
        vm.stopPrank();
    }

    // Test redeem with zero TVL
    function testRedeemWithZeroTVL() public {
        // First deposit some USDC
        uint256 depositAmount = 100e6; // 100 USDC
        mockTVL(0);
        
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, 0);
        
        // Mock TVL to be zero
        mockTVL(100e18);
        
        // Approve router to burn shares
        shareToken.approve(address(router), shares);
        
        // Redeem all shares
        uint256 redeemed = router.redeem(shares, 0);
        vm.stopPrank();
        
        assertEq(redeemed, depositAmount);
        assertEq(shareToken.balanceOf(user1), 0);
    }

    // Test redeem with very small share amount
    function testRedeemWithVerySmallShareAmount() public {
        // First deposit some USDC
        uint256 depositAmount = 100e6; // 100 USDC

        mockTVL(0);
        
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        router.deposit(address(usdc), depositAmount, 0);
        
        // Try to redeem 1 wei of shares
        mockTVL(100e18);
        shareToken.approve(address(router), 1);
        vm.expectRevert(); // Should revert with AMOUNT_ZERO
        router.redeem(1, 0);
        vm.stopPrank();
    }

    // Test redeem with multiple escrows having different balances
    function testRedeemWithMultipleEscrows() public {
        // First deposit some USDC
        uint256 depositAmount = 100e6; // 100 USDC
        mockTVL(0);
        
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, 0);
        
        // Mock different balances in different escrows
        usdc.mint(address(escrow1), 30e6);
        usdc.mint(address(escrow2), 40e6);
        usdc.mint(address(escrow3), 30e6);
        
        // Mock TVL to be 100 USDC
        mockTVL(100e18);
        
        // Approve router to burn shares
        shareToken.approve(address(router), shares);
        
        // Redeem all shares
        uint256 redeemed = router.redeem(shares, 0);
        vm.stopPrank();
        
        assertEq(redeemed, depositAmount);
        assertEq(shareToken.balanceOf(user1), 0);
    }

    // Test redeem with insufficient escrow balances for withdraw asset
    function testRedeemWithInsufficientEscrowBalances() public initialDeposit {
        // First deposit some PURR
        uint256 depositAmount = 10e18; // 10 PURR

        mockTVL(10e18);

        mockRate(20e6); // 1 PURR = 20 USDC
        
        vm.startPrank(user1);
        purr.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(purr), depositAmount, 0);
        
        // Mock TVL to be 100 USDC
        mockTVL(200e18 + 10e18);
        
        // Approve router to burn shares
        shareToken.approve(address(router), shares);
        
        // Redeem all shares should fail
        vm.expectRevert(); // Should revert with FETCH_ASSETS_FAILED
        router.redeem(shares, 0);
        vm.stopPrank();
    }

    // Test redeem with withdraw asset not set.
    function testRedeemRevertsWhenWithdrawAssetUnset() public {
        uint256 depositAmount = 10e6; // 10 USDC
        mockTVL(10e18);
        vm.startPrank(user1);
        usdc.approve(address(router), depositAmount);
        uint256 shares = router.deposit(address(usdc), depositAmount, 0);
        vm.stopPrank();

        // Manually zero out withdrawAsset in storage (since it can not happen through setWithdrawAsset)
        //    The V1Storage struct is stored at slot V1_HYPERVAULT_ROUTER_STORAGE_LOCATION,
        //    and withdrawAsset is the *second* storage slot within it (after the packed uint64s).
        bytes32 baseSlot = router.V1_HYPERVAULT_ROUTER_STORAGE_LOCATION();
        bytes32 withdrawAssetSlot = bytes32(uint256(baseSlot) + 1);
        vm.store(address(router), withdrawAssetSlot, bytes32(uint256(0)));

        vm.startPrank(user1);
        shareToken.approve(address(router), shares);
        vm.expectRevert();
        router.redeem(shares, 0);
        vm.stopPrank();
    }

    // Test redeem with exact min out
    function testRedeemSucceedsWithExactMinOut() public initialDeposit {
        // Redeeming with minOut == actual amount should pass the slippage check

        mockTVL(10e18);

        // user1 first deposits 50 USDC
        vm.startPrank(user1);
        usdc.approve(address(router), 50e6);
        uint256 shares = router.deposit(address(usdc), 50e6, 0);
        vm.stopPrank();

        // Set tvl so redeem returns exactly 60 USDC
        mockTVL(60e18);

        vm.startPrank(user1);
        shareToken.approve(address(router), shares);
        uint256 redeemed = router.redeem(shares, 50e6);
        vm.stopPrank();

        assertEq(redeemed, 50e6);
    }

    // Test redeem with TVL to be 0
    function testRedeemRevertsWhenTvlZero() public initialDeposit {
        mockTVL(10e18);

        // user1 deposits 10 USDC
        vm.startPrank(user1);
        usdc.approve(address(router), 10e6);
        uint256 shares = router.deposit(address(usdc), 10e6, 0);
        vm.stopPrank();

        // Now force tvl() == 0 because all the money were lost or something.
        mockTVL(0);

        vm.startPrank(user1);
        shareToken.approve(address(router), shares);
        vm.expectRevert(); // AMOUNT_ZERO
        router.redeem(shares, 0);
        vm.stopPrank();
    }
} 