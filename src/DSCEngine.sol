// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

/*
 * @title DSCEngine
 * @author Miguel Mota (following Patrick Collins' course with code repository at https://github.com/Cyfrin/foundry-defi-stablecoin-cu)
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 private constant FEED_PRECISION_ADJUSTMENT = 1e8;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;
    

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if(amount == 0){
            revert DSCEngine__NeedsMoreThanZero();
        }

        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0) || _isCollateralToken(tokenAddress)) {
            revert DSCEngine__TokenNotAllowed();
        }

        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if(tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for(uint256 i=0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * 
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountToMint The amount of decentralized stablecoin to mint
     * @notice this function will deposit your collateral DSC in one transaction
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToMint) external {
        _depositCollateral(tokenCollateralAddress, amountCollateral);
        _mintDsc(amountToMint);
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external {
        _depositCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateralForDsc() external {}

    /**
     * @notice the health factor must be > 1 AFTER pulling the collateral
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 collateralAmountToRedeem) external moreThanZero(collateralAmountToRedeem) moreThanZero(s_collateralDeposited[msg.sender][tokenCollateralAddress] - collateralAmountToRedeem) isAllowedToken(tokenCollateralAddress) nonReentrant {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= collateralAmountToRedeem;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, collateralAmountToRedeem);

        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, collateralAmountToRedeem);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice followes CEI
     * @param amountDscToMint the amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) external {
        _mintDsc(amountDscToMint);
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external {}

    /*//////////////////////////////////////////////////////////////
                     PRIVATE AND INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) internal moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _mintDsc(uint256 amountDscToMint) private moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;

        // if they minted too much ($150 DSC minted with only 100$ ETH collateral)
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }
    
    function _isCollateralToken(address tokenAddress) private view returns(bool) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            if (s_collateralTokens[i] == tokenAddress) {
                return true;
            }
        }
        return false;
    }

    function _calculateHealthFactor(uint256 collateralAmount, uint256 amountMinted) internal pure returns (uint256) {
        // (LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION) normalises the ratio of collateral/minted to [0,1]
        uint256 maximumMintedAmount = collateralAmount * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;

        // we multiply by the precision because if both maximumMintedAmount and s_dscMinted[user] have 1e18 decimal places,
        // then the result would be normalised, instead of keeping 1e18 decimal places.
        return maximumMintedAmount * PRECISION / amountMinted;
    }

    /**
     * @notice health factor represents how close the user is to the limit how much their collateral allows them to borrow (i.e. mint).
     *          For example, if:
     *              1. we require that collateral be 3x greater than minted value and
     *              2. the user has 1200$ in collateral
     *              3. the user has borrowed (i.e.: minted) 250$, then
     * 
     *              a. The maximum borrow amount is 1200$ / 3 = 400$
     *              b. The user has a health factor of 400 / 250 = 1.6
     * 
     *          We use this metric to determine when to liquidate a user and/or prevent further minting by a user. 
     *          When health factor goes below 1, then the user's has exceeding their collateral's borrowing power.
     */
    function _getHealthFactor(address user) private view returns (uint256) {
        // 1. Check health factor (does the user have enough collateral for the amount they minted?)
        uint256 userCollateral = getUserCollateralValue(user);

        return _calculateHealthFactor(userCollateral, s_dscMinted[user]);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // If the user hasn't minted anything, they can't have a poor health factor
        if (s_dscMinted[user] == 0) {
            return;
        }
        
        uint256 userHealthFactor = _getHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    /*//////////////////////////////////////////////////////////////
                   PUBLIC AND EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getUserCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD){
        // loop through each collateral token, get the amount they have
        // deposited, and map it to the price, to get the USD value.
        uint256 result = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            
            result += getUsdValue(token, amount);
        }

        return result;
    }

    /** 
     * @notice this returns the USD value with 18 decimal places
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);

        // TODO: different feeds will return price in different number of decimals, we need to be flexible in adjusting for it
        (,int256 price,,,) = priceFeed.latestRoundData();

        // price will come as ETH * 1e8, so we have to divide by 1e8 here (the ADDITIONAL_FEED_PRECISION value)
        return uint256(price) * amount / FEED_PRECISION_ADJUSTMENT;
    }
}
