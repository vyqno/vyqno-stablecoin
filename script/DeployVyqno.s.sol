// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {VyqnoStableCoin} from "../src/VyqnoStableCoin.sol";
import {VyqnoEngine} from "../src/VyqnoEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title DeployVyqno
 * @author Hitesh P
 * @notice Deployment script for the Vyqno Stablecoin Protocol
 * @dev Deploys VyqnoStableCoin and VyqnoEngine contracts with proper configuration
 *
 * Deployment Flow:
 * 1. Get network configuration from HelperConfig
 * 2. Deploy VyqnoStableCoin (ERC20 token)
 * 3. Deploy VyqnoEngine with collateral tokens and price feeds
 * 4. Transfer VyqnoStableCoin ownership to VyqnoEngine
 * 5. Return deployed contract addresses
 *
 * Usage:
 * ```bash
 * # Deploy to Sepolia
 * forge script script/DeployVyqno.s.sol:DeployVyqno --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 *
 * # Deploy to Polygon
 * forge script script/DeployVyqno.s.sol:DeployVyqno --rpc-url $POLYGON_RPC_URL --broadcast --verify
 *
 * # Deploy to Arbitrum
 * forge script script/DeployVyqno.s.sol:DeployVyqno --rpc-url $ARBITRUM_RPC_URL --broadcast --verify
 *
 * # Deploy to local Anvil
 * forge script script/DeployVyqno.s.sol:DeployVyqno --rpc-url http://localhost:8545 --broadcast
 * ```
 */
contract DeployVyqno is Script {
    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @dev Oracle heartbeat: 1 hour (3600 seconds)
    /// @dev Price data older than this is considered stale
    uint256 private constant ORACLE_HEARTBEAT = 3600;

    /*//////////////////////////////////////////////////////////////
                           MAIN DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Main deployment function
     * @return vsc The deployed VyqnoStableCoin contract
     * @return engine The deployed VyqnoEngine contract
     * @return helperConfig The HelperConfig instance used for deployment
     *
     * @dev This function:
     * 1. Loads network-specific configuration
     * 2. Deploys both contracts
     * 3. Transfers VSC ownership to the Engine
     * 4. Returns all contract instances for testing/verification
     */
    function run() external returns (VyqnoStableCoin vsc, VyqnoEngine engine, HelperConfig helperConfig) {
        // Get network configuration
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        // Deploy contracts
        (vsc, engine) = deployVyqnoProtocol(
            config.weth, config.wbtc, config.wethUsdPriceFeed, config.wbtcUsdPriceFeed, config.deployerKey
        );

        return (vsc, engine, helperConfig);
    }

    /*//////////////////////////////////////////////////////////////
                         DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deploys the complete Vyqno Stablecoin Protocol
     * @param weth WETH token address
     * @param wbtc WBTC token address
     * @param wethUsdPriceFeed Chainlink WETH/USD price feed address
     * @param wbtcUsdPriceFeed Chainlink WBTC/USD price feed address
     * @param deployerKey Private key for signing deployment transactions
     * @return vsc The deployed VyqnoStableCoin contract
     * @return engine The deployed VyqnoEngine contract
     *
     * @dev Deployment Steps:
     *
     * Step 1: Deploy VyqnoStableCoin
     * - ERC20 token with name "VyqnoStableCoin" and symbol "VSC"
     * - Initially owned by deployer (will be transferred to Engine)
     *
     * Step 2: Prepare VyqnoEngine Constructor Parameters
     * - tokenAddresses: [weth, wbtc]
     * - priceFeedAddresses: [wethUsdPriceFeed, wbtcUsdPriceFeed]
     * - heartbeats: [3600, 3600] (1 hour for both feeds)
     * - vscAddress: Address of deployed VyqnoStableCoin
     *
     * Step 3: Deploy VyqnoEngine
     * - Automatically detects token decimals (18 for WETH, 8 for WBTC)
     * - Sets up price feed validation with heartbeat monitoring
     * - Configures 200% overcollateralization requirement
     * - Enables 50% maximum liquidation cap
     *
     * Step 4: Transfer Ownership
     * - Transfer VyqnoStableCoin ownership from deployer to VyqnoEngine
     * - Only the Engine can now mint/burn VSC tokens
     * - This ensures collateral backing for all minted tokens
     */
    function deployVyqnoProtocol(
        address weth,
        address wbtc,
        address wethUsdPriceFeed,
        address wbtcUsdPriceFeed,
        uint256 deployerKey
    ) public returns (VyqnoStableCoin, VyqnoEngine) {
        vm.startBroadcast(deployerKey);

        // Step 1: Deploy VyqnoStableCoin (VSC token)
        VyqnoStableCoin vsc = new VyqnoStableCoin();

        // Step 2: Prepare collateral configuration
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = weth;
        tokenAddresses[1] = wbtc;

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = wethUsdPriceFeed;
        priceFeedAddresses[1] = wbtcUsdPriceFeed;

        uint256[] memory heartbeats = new uint256[](2);
        heartbeats[0] = ORACLE_HEARTBEAT;
        heartbeats[1] = ORACLE_HEARTBEAT;

        // Step 3: Deploy VyqnoEngine
        VyqnoEngine engine = new VyqnoEngine(tokenAddresses, priceFeedAddresses, heartbeats, address(vsc));

        // Step 4: Transfer VSC ownership to Engine
        // CRITICAL: Engine must be the owner to mint/burn VSC
        vsc.transferOwnership(address(engine));

        vm.stopBroadcast();

        return (vsc, engine);
    }
}
