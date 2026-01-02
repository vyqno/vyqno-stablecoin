// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/**
 * @title HelperConfig
 * @author Hitesh P
 * @notice Manages network-specific configuration for VyqnoStableCoin deployment
 * @dev Provides collateral token addresses and Chainlink price feed addresses for each network
 *
 * Supported Networks:
 * - Sepolia Testnet (chainid: 11155111)
 * - Polygon Mainnet (chainid: 137)
 * - Arbitrum Mainnet (chainid: 42161)
 * - Local Anvil (chainid: 31337)
 *
 * For each network, this contract provides:
 * - WETH token address
 * - WBTC token address
 * - WETH/USD price feed address
 * - WBTC/USD price feed address
 * - Deployer private key (from environment)
 *
 * Usage in deployment scripts:
 * ```solidity
 * HelperConfig helperConfig = new HelperConfig();
 * NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
 *
 * // Use config.weth, config.wethUsdPriceFeed, etc.
 * ```
 */
contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Configuration parameters for a specific network
     * @param wethUsdPriceFeed Chainlink WETH/USD price feed address
     * @param wbtcUsdPriceFeed Chainlink WBTC/USD price feed address
     * @param weth WETH token contract address
     * @param wbtc WBTC token contract address
     * @param deployerKey Private key for deployment (from environment variable)
     */
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint8 private constant DECIMALS = 8; // Chainlink price feed decimals
    int256 private constant ETH_USD_PRICE = 2000e8; // $2000 per ETH
    int256 private constant BTC_USD_PRICE = 43000e8; // $43000 per BTC
    uint256 private constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the config for the active network
     * @dev Auto-detects network based on block.chainid and loads appropriate configuration
     */
    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 137) {
            activeNetworkConfig = getPolygonMainnetConfig();
        } else if (block.chainid == 42161) {
            activeNetworkConfig = getArbitrumMainnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the configuration for the currently active network
     * @return NetworkConfig struct containing all network-specific addresses
     */
    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    /*//////////////////////////////////////////////////////////////
                         NETWORK CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Configuration for Sepolia testnet
     * @return NetworkConfig for Sepolia
     * @dev Uses official Chainlink price feeds on Sepolia
     *
     * Sepolia Addresses:
     * - WETH/USD Feed: 0x694AA1769357215DE4FAC081bf1f309aDC325306
     * - WBTC/USD Feed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
     * - WETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81
     * - WBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063 (example, verify before use)
     */
    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, // Example address - verify
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    /**
     * @notice Configuration for Polygon mainnet
     * @return NetworkConfig for Polygon
     * @dev Uses official Chainlink price feeds on Polygon
     *
     * Polygon Addresses:
     * - WETH/USD Feed: 0xF9680D99D6C9589e2a93a78A04A279e509205945
     * - WBTC/USD Feed: 0xc907E116054Ad103354f2D350FD2514433D57F6f
     * - WETH: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619
     * - WBTC: 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6
     */
    function getPolygonMainnetConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0xF9680D99D6C9589e2a93a78A04A279e509205945,
            wbtcUsdPriceFeed: 0xc907E116054Ad103354f2D350FD2514433D57F6f,
            weth: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619,
            wbtc: 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    /**
     * @notice Configuration for Arbitrum mainnet
     * @return NetworkConfig for Arbitrum
     * @dev Uses official Chainlink price feeds on Arbitrum
     *
     * Arbitrum Addresses:
     * - WETH/USD Feed: 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
     * - WBTC/USD Feed: 0x6ce185860a4963106506C203335A2910413708e9
     * - WETH: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
     * - WBTC: 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f
     */
    function getArbitrumMainnetConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,
            wbtcUsdPriceFeed: 0x6ce185860a4963106506C203335A2910413708e9,
            weth: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            wbtc: 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    /**
     * @notice Configuration for local Anvil network
     * @return NetworkConfig for Anvil
     * @dev Deploys mock contracts for local testing
     *
     * Deployment Process:
     * 1. Deploy MockV3Aggregator for WETH/USD (8 decimals, $2000)
     * 2. Deploy MockV3Aggregator for WBTC/USD (8 decimals, $43000)
     * 3. Deploy MockERC20 for WETH (18 decimals)
     * 4. Deploy MockERC20 for WBTC (8 decimals)
     * 5. Return addresses in NetworkConfig struct
     */
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Check if we already have an active config for Anvil
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        // Deploy mock price feeds
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);

        // Deploy mock tokens with appropriate decimals
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
