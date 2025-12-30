// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VyqnoStableCoin} from "./VyqnoStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract VyqnoEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                           ERRORS
    //////////////////////////////////////////////////////////////*/
    error VyqnoEngine__NeedsMoreThanZero();
    error VyqnoEngine__TokenNotAllowed();
    error VyqnoEngine__BothAddressLengthShouldBeEqual();
    error VyqnoEngine__CollateralTransferFailed();
    error VyqnoEngine__MintFailed();
    error VyqnoEngine__BreaksHealthFactor(uint256 healthFactor);
    error VyqnoEngine__BurnFailed();
    error VyqnoEngine__HealthFactorOk();
    error VyqnoEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 VSCminted) private s_VSCminted;
    address[] private s_collateralTokens;
    VyqnoStableCoin private immutable i_vyqnoStableCoin;

    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event VscMinted(address indexed user, uint256 amount);
    event VscBurned(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert VyqnoEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) revert VyqnoEngine__TokenNotAllowed();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory allowedTokenAddresses, address[] memory priceFeedAddresses, address vscAddress) {
        if (allowedTokenAddresses.length != priceFeedAddresses.length) {
            revert VyqnoEngine__BothAddressLengthShouldBeEqual();
        }
        for (uint256 i = 0; i < allowedTokenAddresses.length; i++) {
            s_priceFeeds[allowedTokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_vyqnoStableCoin = VyqnoStableCoin(vscAddress);
        s_collateralTokens = allowedTokenAddresses;
    }

    /*//////////////////////////////////////////////////////////////
                                 EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function depositCollateral(address adressOfTokenWhichIsBeingDeposited, uint256 amountOfTokenBeingDeposited)
        external
        moreThanZero(amountOfTokenBeingDeposited)
        isAllowedToken(adressOfTokenWhichIsBeingDeposited)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][adressOfTokenWhichIsBeingDeposited] += amountOfTokenBeingDeposited;
        emit CollateralDeposited(msg.sender, adressOfTokenWhichIsBeingDeposited, amountOfTokenBeingDeposited);
        bool success = IERC20(adressOfTokenWhichIsBeingDeposited)
            .transferFrom(msg.sender, address(this), amountOfTokenBeingDeposited);
        if (!success) revert VyqnoEngine__CollateralTransferFailed();
    }

    /**
     * @notice Mints VSC tokens to the caller
     * @param amountVscToMint Amount of VSC to mint
     * @dev Must maintain health factor above MIN_HEALTH_FACTOR
     */
    function mintVsc(uint256 amountVscToMint) external moreThanZero(amountVscToMint) nonReentrant {
        s_VSCminted[msg.sender] += amountVscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        i_vyqnoStableCoin.mint(msg.sender, amountVscToMint);
        emit VscMinted(msg.sender, amountVscToMint);
    }

    /**
     * @notice Burns VSC tokens from the caller
     * @param amountVscToBurn Amount of VSC to burn
     * @dev Reduces the user's debt, improving their health factor
     */
    function burnVsc(uint256 amountVscToBurn) external moreThanZero(amountVscToBurn) nonReentrant {
        s_VSCminted[msg.sender] -= amountVscToBurn;
        bool success = i_vyqnoStableCoin.transferFrom(msg.sender, address(this), amountVscToBurn);
        if (!success) revert VyqnoEngine__BurnFailed();
        i_vyqnoStableCoin.burn(amountVscToBurn);
        emit VscBurned(msg.sender, amountVscToBurn);
    }

    /**
     * @notice Withdraws collateral from the protocol
     * @param tokenCollateralAddress The collateral token to redeem
     * @param amountCollateral Amount of collateral to withdraw
     * @dev Must maintain health factor above MIN_HEALTH_FACTOR after withdrawal
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Deposits collateral and mints VSC in one transaction
     * @param tokenCollateralAddress The collateral token to deposit
     * @param amountCollateral Amount of collateral to deposit
     * @param amountVscToMint Amount of VSC to mint
     * @dev More gas efficient than calling depositCollateral() and mintVsc() separately
     */
    function depositCollateralAndMintVsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountVscToMint
    ) external moreThanZero(amountCollateral) moreThanZero(amountVscToMint) nonReentrant {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert VyqnoEngine__CollateralTransferFailed();

        s_VSCminted[msg.sender] += amountVscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        i_vyqnoStableCoin.mint(msg.sender, amountVscToMint);
        emit VscMinted(msg.sender, amountVscToMint);
    }

    /**
     * @notice Burns VSC and redeems collateral in one transaction
     * @param tokenCollateralAddress The collateral token to redeem
     * @param amountCollateral Amount of collateral to withdraw
     * @param amountVscToBurn Amount of VSC to burn
     * @dev More gas efficient than calling burnVsc() and redeemCollateral() separately
     */
    function redeemCollateralForVsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountVscToBurn
    ) external moreThanZero(amountCollateral) moreThanZero(amountVscToBurn) nonReentrant {
        s_VSCminted[msg.sender] -= amountVscToBurn;
        bool success = i_vyqnoStableCoin.transferFrom(msg.sender, address(this), amountVscToBurn);
        if (!success) revert VyqnoEngine__BurnFailed();
        i_vyqnoStableCoin.burn(amountVscToBurn);
        emit VscBurned(msg.sender, amountVscToBurn);

        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Liquidates an undercollateralized user
     * @param collateral The collateral token to liquidate
     * @param user The user to liquidate (health factor < MIN_HEALTH_FACTOR)
     * @param debtToCover Amount of VSC debt to burn to improve user's health factor
     * @dev Liquidator receives a 10% bonus on the collateral value
     * @dev The liquidator must have enough VSC to cover the debt
     * @dev The user being liquidated must have health factor < MIN_HEALTH_FACTOR
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert VyqnoEngine__HealthFactorOk();
        }

        // Calculate how much collateral to give to the liquidator
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // Give liquidator a 10% bonus
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        // Redeem collateral from the user to the liquidator
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

        // Burn the VSC debt from the liquidator
        s_VSCminted[user] -= debtToCover;
        bool success = i_vyqnoStableCoin.transferFrom(msg.sender, address(this), debtToCover);
        if (!success) revert VyqnoEngine__BurnFailed();
        i_vyqnoStableCoin.burn(debtToCover);
        emit VscBurned(user, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert VyqnoEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL / PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns account information for a user
     * @param user The address to get information for
     * @return totalVscMinted Total VSC the user has minted
     * @return collateralValueInUsd Total collateral value in USD
     */
    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalVscMinted, uint256 collateralValueInUsd)
    {
        totalVscMinted = s_VSCminted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Gets the total USD value of all user's collateral
     * @param user The address to calculate for
     * @return totalCollateralValueInUsd Total value in USD (18 decimals)
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // Loop through each collateral token
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    /**
     * @notice Converts token amount to USD value using Chainlink
     * @param token The token address
     * @param amount The amount of tokens
     * @return The USD value (18 decimals)
     *
     *
     * external → Can ONLY be called from outside
     *        Cannot be called by other functions in same contract
     *
     * public   → Can be called from outside AND inside
     *        Perfect for helper functions!
     *
     * So yes, it's `public` because:
     * 1. `getAccountInformation()` calls it internally ✅
     * 2. Users/frontend can also call it directly ✅
     *
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // Price from Chainlink has 8 decimals
        // We want everything in 18 decimals (wei)
        // Formula: (amount * price * 1e10) / 1e18
        return ((uint256(price) * 1e10) * amount) / 1e18;
    }

    /**
     * @notice Converts USD amount to token amount
     * @param token The token address
     * @param usdAmountInWei USD amount in wei (18 decimals)
     * @return The token amount
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // Price has 8 decimals, we need to convert it to 18 decimals
        // Formula: (usdAmount * 1e18) / (price * 1e10)
        return (usdAmountInWei * 1e18) / (uint256(price) * 1e10);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to redeem collateral
     * @param tokenCollateralAddress Token to redeem
     * @param amountCollateral Amount to redeem
     * @param from Address to redeem from
     * @param to Address to send collateral to
     */
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        internal
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) revert VyqnoEngine__CollateralTransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if user's health factor is safe
     * @param user Address to check
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert VyqnoEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * @notice Calculates user's health factor
     * @param user Address to calculate for
     * @return Health factor (1e18 = 1.0)
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalVscMinted, uint256 collateralValueInUsd) = getAccountInformation(user);

        return _calculateHealthFactor(totalVscMinted, collateralValueInUsd);
    }

    /**
     * @notice Calculates health factor from values
     * @param totalVscMinted Total VSC minted
     * @param collateralValueInUsd Total collateral value
     * @return Health factor (1e18 = 1.0)
     */
    function _calculateHealthFactor(uint256 totalVscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalVscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * 1e18) / totalVscMinted;
    }
}
