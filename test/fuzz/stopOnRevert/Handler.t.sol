// SPDX-License-Identifier: MIT

// The handler will narrow down the way we can call our functions

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import { MockV3Aggregator } from "../../mocks/MockV3Aggregator.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin coin;
    mapping(address => ERC20Mock) mockTokensByAddress;
    mapping(address => MockV3Aggregator) usdPriceFeeds;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public usersWithCollateralDeposited;

    constructor(DSCEngine _engine, DecentralizedStableCoin _coin, ERC20Mock[] memory mockTokens) {
        engine = _engine;
        coin = _coin;

        for (uint256 i=0; i < mockTokens.length; i++) {
            ERC20Mock mockToken = mockTokens[i];
            mockTokensByAddress[address(mockToken)] = mockToken;
            usdPriceFeeds[address(mockToken)] = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(mockToken)));
        }
    }

    // redeem collateral - insteads
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address user = msg.sender;
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        
        vm.startPrank(user);
        collateral.mint(user, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        usersWithCollateralDeposited.push(user);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address user = msg.sender;
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.prank(user);
        uint256 userMintedValue = engine.getDscMinted();
        uint256 userTotalCollateralValue = engine.getUserCollateralValue(user);
        uint256 userTokenCollateral = engine.getCollateralBalanceOfUser(user, address(collateral));
        
        vm.assume(userTokenCollateral > 0);
        
        uint256 redeemableValueUsd = userTotalCollateralValue - userMintedValue;
        uint256 maxCollateralAmountToRedeem = engine.getCollateralAmountFromUsdValue(address(collateral), redeemableValueUsd);
        maxCollateralAmountToRedeem = Math.min(maxCollateralAmountToRedeem, userTokenCollateral);

        amountCollateral = bound(amountCollateral, 1, maxCollateralAmountToRedeem);
        
        vm.prank(user);
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amountDscToMint, uint256 addressSeed) public {
        // We can't just mint with whatever address calls this.
        // We have to use an address that already has collateral.
        vm.assume(usersWithCollateralDeposited.length > 0);
        uint256 addressIndex = addressSeed % usersWithCollateralDeposited.length;
        address user = usersWithCollateralDeposited[addressIndex];

        _mintDsc(amountDscToMint, user);
    }

    // function depositCollateralAndMintDsc(
    //     uint256 collateralSeed,
    //     uint256 amountCollateral,
    //     uint256 amountToMint
    // )
    //     external
    // {
    //     depositCollateral(collateralSeed, amountCollateral);
    //     _mintDsc(amountToMint, msg.sender);
    // }

    // function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public {
    //     int256 intNewPrice = int256(uint256(newPrice));
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     MockV3Aggregator priceFeed = usdPriceFeeds[collateralSeed];

    //     priceFeed.updateAnswer(intNewPrice);
    // }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getCollateralFromSeed(uint256 seed) private view returns(ERC20Mock) {
        uint256 collateralIndex = seed % engine.getCollateralTokens().length;
        address tokenAddress = engine.getCollateralTokens()[collateralIndex];
        return mockTokensByAddress[tokenAddress];
    }

    function _mintDsc(uint256 amountDscToMint, address user) private {
        vm.startPrank(user);
        uint256 amountMintedByUser = engine.getDscMinted();
        uint256 userCollateralValue = engine.getUserCollateralValue(user);
        uint256 availableMintAmount = engine.getUserMaxMintAmount(userCollateralValue) - amountMintedByUser;
        vm.stopPrank();
        
        vm.assume(availableMintAmount > 0);
        amountDscToMint = bound(amountDscToMint, 1, availableMintAmount);

        vm.prank(user);
        engine.mintDsc(amountDscToMint);
    }
}