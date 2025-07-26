// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract TestDSCSEngine is Test {
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
        address[] memory tokenAddresses = engine.getCollateralTokens();
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = engine.getPriceFeeds()[0];

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
        uint256 ethAmount = 15e18;
        // with ETH/USD = 3700$ as set in ServerConstants,
        // 15 ETH should equal 15 * 3700 = 55000$, with 18 decimals
        uint256 expectedUsd = 55500e18;  
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    function testGetBtcUsdValue() public {
        uint256 btcAmount = 35e17;
        // with BTC/USD = 120k$ as set in ServerConstants,
        // 3.5 BTC should equal to 3.5 * 120_000 = 420_000$, with 18 decimals
        uint256 expectedUsd = 420_000e18;  
        uint256 actualUsd = engine.getUsdValue(wbtc, btcAmount);

        assertEq(expectedUsd, actualUsd);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertsIfCollateralIsZero() public depositsCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
    }
}
