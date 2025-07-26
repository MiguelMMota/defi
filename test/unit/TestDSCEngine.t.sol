// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract TestDSCSEngine is Test {
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin coin;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant COLLATERAL_DEPOSIT_AMOUNT = 10 ether;
    uint256 public constant START_ERC20_BALANCE = 10 ether;

    modifier depositsCollateral() {
        vm.prank(USER);

        // The user needs to approve the transfer of the amount of WETH
        // to the smart contract.
        // In live deployments, this probably occurs via a wallet popup.
        ERC20Mock(weth).approve(address(engine), COLLATERAL_DEPOSIT_AMOUNT);

        _;
    }

    modifier onlyOnLocalNetwork() {
        if (block.chainid == config.LOCAL_CHAIN_ID()) {
            _;
        }
    }

    function setUp() public {
        deployer = new DeployDSC();
        (coin, engine, config) = deployer.createContracts();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        // give the user 10 ether worth of WETH.
        ERC20Mock(weth).mint(USER, START_ERC20_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    function testConstructorRevertsIfTokenAddressesAndPriceFeedAddressesHaveDifferentLengths() public {
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = weth;
        tokenAddresses[1] = wbtc;

        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = ethUsdPriceFeed;

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(coin));
    }

    function testConstructorRevertsWithoutTokenAndPriceData() public {
        vm.expectRevert(DSCEngine.DSCEngine__NoTokenAndPriceFeedData.selector);
        new DSCEngine(new address[](0), new address[](0), address(coin));   
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE FEED TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetEthUsdValue() public {
        uint256 precisionDigits = engine.PRECISION_DIGITS();

        // TODO: fix this, so it also works on other test nets like Sepolia,
        // which get their own price values
        uint256 ethAmount = 15e18;
        // with ETH/USD = 3700$ as set in ServerConstants,
        // 15 ETH should equal 15 * 3700 = 55000$, with 18 decimals
        uint256 expectedUsd = config.INITIAL_ETH_PRICE() * ethAmount * (10 ** (precisionDigits - config.DECIMALS())) / (10 ** precisionDigits);
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    function testGetBtcUsdValue() public {
        // Arrange
        uint256 precisionDigits = engine.PRECISION_DIGITS();

        uint256 btcAmount = 35e17;
        // with BTC/USD = 120k$ as set in ServerConstants,
        // 3.5 BTC should equal to 3.5 * 120_000 = 420_000$, with 18 decimals
        uint256 expectedUsd = config.INITIAL_BTC_PRICE() * btcAmount * (10 ** (precisionDigits - config.DECIMALS())) / (10 ** precisionDigits); 
        
        // Act
        uint256 actualUsd = engine.getUsdValue(wbtc, btcAmount);

        // Assert
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmountInWei = 125_000e18;  // 125k$

        console2.log(usdAmountInWei);
        console2.log(config.INITIAL_ETH_PRICE());
        console2.log(usdAmountInWei / config.INITIAL_ETH_PRICE());
        uint256 expectedEth = 10 ** config.DECIMALS() * usdAmountInWei / config.INITIAL_ETH_PRICE();

        uint256 actualEth = engine.getTokenAmountFromUsd(weth, usdAmountInWei);

        assertEq(expectedEth, actualEth);
    }

    function testGetTokenAmountFromUsdInLocalNetwork() public onlyOnLocalNetwork {
        // We do a test with specific values to make sure there isn't an error in
        // both testGetTokenAmountFromUsd and our contract, as they have repeated logic.
        uint256 expectedEth = 123456;
        uint256 usdAmountInWei = expectedEth * config.INITIAL_ETH_PRICE() * (10 ** (18 - config.DECIMALS()));
        uint256 actualEth = engine.getTokenAmountFromUsd(weth, usdAmountInWei);

        assertEq(actualEth, expectedEth * (10 ** engine.PRECISION_DIGITS()));
    }

    function testNormalisingPriceFeedResult(uint256 rawPrice, uint256 priceDigits, uint256 decimals) public {
        // Arrange
        uint256 precisionDigits = engine.PRECISION_DIGITS();

        // [4-18]
        decimals = bound(decimals, 4, precisionDigits);
    
        // [1e3, 9.(9)e17]
        priceDigits = bound(priceDigits, 4, precisionDigits);    
        uint256 minPrice = 10 ** (priceDigits - 1);
        uint256 maxPrice = (10 ** priceDigits) - 1;
        uint256 price = bound(rawPrice, minPrice, maxPrice);
        
        // Act
        uint256 result = engine.getNormalisedPriceFeedResult(price, decimals);

        // Assert
        if (decimals <= precisionDigits) {
            uint256 numberOfZeros = precisionDigits - decimals;
            uint256 expectedResult = price * (10 ** numberOfZeros);
            
            assertEq(result, expectedResult, "Result should be price followed by zeros");
            
            // Additional check: verify the result has the right number of digits
            uint256 expectedDigits = priceDigits + numberOfZeros;
            uint256 actualDigits = _countDigits(result);
            assertEq(actualDigits, expectedDigits, "Result should have correct number of digits");
        } else {
            // If decimals > precision, result should be price divided down
            uint256 divisor = 10 ** (decimals - precisionDigits);
            uint256 expectedResult = price / divisor;
            assertEq(result, expectedResult, "Result should be price divided down");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertsIfCollateralIsZero() public depositsCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
    }

    function testRevertsIfCollateralTokenIsNotAllowed() public depositsCollateral {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, START_ERC20_BALANCE);

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), 1 ether);
        vm.stopPrank();
    }

    function testDepositCollateralTransfersToContractAndUpdatesCollateral() public depositsCollateral {
        // NB: the course by Patrick Collins actually does a much simpler implementation of this, by
        // only checking the USD value of the whole collateral for the user, instead of the amount of
        // each token.

        // Arrange
        uint256 amountToDeposit = 1 ether;
        address collateralTokenToDeposit = weth;
        
        address[] memory collateralTokens = engine.getCollateralTokens();
        uint256[] memory userBalancesBefore = new uint256[](collateralTokens.length);
        uint256[] memory contractBalancesBefore = new uint256[](collateralTokens.length);

        vm.prank(USER);
        uint256 initialDscMinted = engine.getDscMinted();

        for (uint256 i=0; i<collateralTokens.length; i++) {
            address token = collateralTokens[i];
            userBalancesBefore[i] = ERC20Mock(token).balanceOf(USER);
            contractBalancesBefore[i] = ERC20Mock(token).balanceOf(address(engine));
        }

        // Act
        vm.startPrank(USER);
        uint256[] memory initialCollateralAmounts = engine.getUserCollateral();
        
        engine.depositCollateral(collateralTokenToDeposit, amountToDeposit);
        uint256[] memory intermediateCollateralAmounts = engine.getUserCollateral();

        vm.expectEmit(true, true, true, false, address(engine));
        emit CollateralDeposited(USER, collateralTokenToDeposit, amountToDeposit);
        
        engine.depositCollateral(collateralTokenToDeposit, amountToDeposit);
        
        uint256[] memory finalCollateralAmounts = engine.getUserCollateral();
        vm.stopPrank();

        // Assert
        // 1. The only amount of collateral that we recorded as having changed is the 
        // one for the token that was deposited, which was increased by amonutToDeposit
        for (uint256 i=0; i<collateralTokens.length; i++) {
            address token = collateralTokens[i];
            if (token == collateralTokenToDeposit) {
                assertEq(initialCollateralAmounts[i] + amountToDeposit, intermediateCollateralAmounts[i]);
                assertEq(intermediateCollateralAmounts[i] + amountToDeposit, finalCollateralAmounts[i]);

                assertEq(ERC20Mock(token).balanceOf(USER), userBalancesBefore[i] - 2 * amountToDeposit);
                assertEq(ERC20Mock(token).balanceOf(address(engine)), contractBalancesBefore[i] + 2 * amountToDeposit);
            } else {
                assertEq(initialCollateralAmounts[i], intermediateCollateralAmounts[i]);
                assertEq(intermediateCollateralAmounts[i], finalCollateralAmounts[i]);

                assertEq(ERC20Mock(token).balanceOf(USER), userBalancesBefore[i]);
                assertEq(ERC20Mock(token).balanceOf(address(engine)), contractBalancesBefore[i]);
            }
        }

        vm.prank(USER);
        uint256 dscMinted = engine.getDscMinted();
        assertEq(initialDscMinted, dscMinted);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _countDigits(uint256 number) private pure returns (uint256) {
        if (number == 0) return 1;
        uint256 digits = 0;
        while (number > 0) {
            digits++;
            number /= 10;
        }
        return digits;
    }
}
