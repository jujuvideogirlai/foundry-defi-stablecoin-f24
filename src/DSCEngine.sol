// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

//import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {console} from "forge-std/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/Oracle.lib.sol";

/**
 * @author  Júlia Polbach
 * @title   DSCEngine
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
 * @notice This contract is based on the MakerDAO DSS system.
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__AmountMustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustHaveSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    using SafeMath for uint256;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1.000.000.000.000.000.000
    uint256 private constant LIQUIDATION_BONUS = 10; // 10 % bonus
    uint256 public constant MAX_DEPOSIT_SIZE = 1_000_000e18; // Example: 1 million tokens

    mapping(address token => address priceFeeds) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCminted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustHaveSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice This function is a convenience function that allows the user to deposit collateral and mint DSC in one transaction.
     * @param   tokenCollateralAddress // The address of the token to deposit collateral.
     * @param   collateralAmount // The amount of collateral to deposit.
     * @param   DSCamount // The amount of DSC to mint.
     */
    function depositCollateralAndMintDSC(address tokenCollateralAddress, uint256 collateralAmount, uint256 DSCamount)
        external
    {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDSC(DSCamount);
    }

    /**
     * @notice  This function burns DSC and redeems collateral in one transaction.
     * @param   tokenCollateralAddress // The address of the token to deposit collateral.
     * @param   collateralAmount // The amount of collateral to deposit.
     * @param   DSCamount // The amount of DSC to mint.
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 collateralAmount, uint256 DSCamount)
        external
    {
        burnDSC(DSCamount);
        redeemCollateral(tokenCollateralAddress, collateralAmount);
        // redeemCollateral already checks if the health factor is broken
    }

    /**
     * @param   collateral // The ERC20 address to liquidate from the user.
     * @param   user // The user who has broken the health factor.
     * @param   debtToCover // The amount of DSC you want to burn to improve the user's health factor.
     * @notice  You can partially liquidate a user's position by burning DSC.
     * @notice  You will get a liquidation bonus for taking the user funds.
     * @notice  This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        console.log("--------------------------------");

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice  Follows CEI pattern.
     * @param   tokenCollateralAddress The address of the token to deposit collateral.
     * @param   amountCollateral The amount of collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        //require(amountCollateral <= MAX_DEPOSIT_SIZE, "Amount too large");
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = ERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Follows CEI pattern.
     * @param  amountDSCToMint The amount of DSC to mint.
     * @notice They must have more collateral value than the minimum threshold.
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_dscMinted[msg.sender] = SafeMath.add(s_dscMinted[msg.sender], amountDSCToMint);
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would never hit
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                  INTERNAL AND PRIVATE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUSD = getAccountCollateralValueInUSD(user);
    }

    /**
     * Returns how close to liquidation a user is.
     * If a user goes below 1, then they can get liquidated.
     * @param   user The address of the user.
     * @return  uint256
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 healthFactor = _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
        return healthFactor;
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max; // If the user has no DSC minted, they are in good health
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * @notice  .
     * @dev     Low-level internal function, don't call unless the function calling checks the Health Factor.
     * @param   amountDscToBurn  .
     * @param   onBehalfOf  .
     * @param   dscFrom  .
     */
    function _burnDSC(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] =
            SafeMath.sub(s_dscMinted[onBehalfOf], amountDscToBurn, "DSCEngine: Underflow in DSC minted amount");
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] = SafeMath.sub(
            s_collateralDeposited[from][tokenCollateralAddress],
            collateralAmount,
            "DSCEngine: Underflow in collateral deposited amount"
        );
        emit CollateralRedeemed(from, to, tokenCollateralAddress, collateralAmount);

        bool success = ERC20(tokenCollateralAddress).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice  We want to have everything in terms of WEI, so we add 10 zeros at the end.
     * Most USD pairs have 8 decimals, so we will just pretend they all do.
     * @param   token  The address of the token to get the USD value for
     * @param   amount  The amount of tokens to get the USD value for
     * @return  uint256  Amount in USD terms (in wei)
     */
    function _getUsdValue(address token, uint256 amount) public view returns (uint256) {
        // Get price from chainlink price feed
        (, int256 price,,,) = AggregatorV3Interface(s_priceFeeds[token]).staleCheckLatestRoundData();
        require(price > 0, "Invalid price");

        uint256 normalizedPrice = _normalizePrice(uint256(price));

        // Revert if amount would cause overflow
        require(amount <= type(uint256).max / normalizedPrice, "Amount too large");

        return _calculateValueInUsd(amount, normalizedPrice);
    }

    // Helper functions for safe math operations
    function _calculateValueInUsd(uint256 amount, uint256 price) internal pure returns (uint256) {
        return (amount * price) / 1e18;
    }

    function _normalizePrice(uint256 price) internal pure returns (uint256) {
        // Chainlink prices come with 8 decimals, we want 18
        return price * 1e10;
    }

    /*//////////////////////////////////////////////////////////////
                   EXTERNAL AND PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 usdAmountInWei = s_collateralDeposited[user][token];
            totalCollateralValueInUSD = SafeMath.add(totalCollateralValueInUSD, _getUsdValue(token, usdAmountInWei));
        }
        return totalCollateralValueInUSD;
    }

    /**
     * @notice  Most USD pairs have 8 decimals, so we will just pretend they all do
     * @dev     .
     * @param   token  .
     * @param   usdAmountInWei  .
     * @return  uint256  .
     */
    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        (totalDscMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    function getCollateralDeposited(address user, address token)
        external
        view
        returns (uint256 totalCollateralDeposited)
    {
        return s_collateralDeposited[user][token];
    }

    function getDSCMinted(address user) external view returns (uint256 totalDscMinted) {
        return s_dscMinted[user];
    }

    function getAllowance(address owner, address spender) external view returns (uint256 allowance) {
        return i_dsc.allowance(owner, spender);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
