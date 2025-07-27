// SPDX-License-Identifier: MIT

// The handler will narrow down the way we can call our functions

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin coin;
    mapping(address => ERC20Mock) mockTokensByAddress;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _engine, DecentralizedStableCoin _coin, ERC20Mock[] memory mockTokens) {
        engine = _engine;
        coin = _coin;

        for (uint256 i=0; i < mockTokens.length; i++) {
            ERC20Mock mockToken = mockTokens[i];
            mockTokensByAddress[address(mockToken)] = mockToken;
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
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address user = msg.sender;
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(user, address(collateral));

        // User must have some collateral to redeem.
        // vm.assume(condition) stops the fuzz run and
        // discards the inputs the condition isn't met.
        vm.assume(maxCollateralToRedeem > 0);
        amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);
        
        vm.prank(user);
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amountDscToMint) public {
        address user = msg.sender;

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

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountToMint
    )
        external
    {
        engine.depositCollateralAndMintDsc(tokenCollateralAddress, amountCollateral, amountToMint);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getCollateralFromSeed(uint256 seed) private view returns(ERC20Mock) {
        uint256 collateralIndex = seed % engine.getCollateralTokens().length;
        address tokenAddress = engine.getCollateralTokens()[collateralIndex];
        return mockTokensByAddress[tokenAddress];
    }
}