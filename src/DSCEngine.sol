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
    error DSCEngine__HealthFactorIsBroken(healthFactorPercent);
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MIN_HEALTH_FACTOR_PERCENT = 70;
    uint256 private constant FEED_PRECISION_ADJUSTMENT = 1e8;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;
    

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if(amount == 0){
            revert DSCEngine__NeedsMoreThanZero();
        }

        _;
    }

    modifer isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }

        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if(tokenAddresses.length != priceFeedAddresses) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for(uint256 i=0; i < tokenAddresses.length: i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function depositCollateralAndMintDsc() external {}

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
     * @notice followes CEI
     * @param amountDscToMint the amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;

        // if they minted too much ($150 DSC minted with only 100$ ETH collateral)
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external {}

    /*//////////////////////////////////////////////////////////////
                     PRIVATE AND INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getHealthFactor(address user) private view returns (uint256) {
        // 1. Check health factor (does the user have enough collateral for the amount they minted?)
        uint256 userCollateral = getUserCollateralValue(user);
        return 100 * userCollateral / s_dscMinted[user];
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // If the user hasn't minted anything, they can't have a poor health factor
        if (s_dscMinted[user] == 0) {
            return;
        }
        
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactorPercent < MIN_HEALTH_FACTOR_PERCENT) {
            revert DSCEngine__HealthFactorIsBroken(healthFactorPercent);
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

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();

        // price will come as ETH * 1e8, so we have to divide by 1e8 here (the ADDITIONAL_FEED_PRECISION value)
        return uint256(price) * amount / FEED_PRECISION_ADJUSTMENT;
    }
}
