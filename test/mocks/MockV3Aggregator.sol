// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title MockV3Aggregator
 * @author Hitesh P (adapted from Chainlink)
 * @notice Mock implementation of Chainlink's AggregatorV3Interface for testing
 * @dev Use this contract to simulate Chainlink price feeds in local and test environments
 *
 * Features:
 * - Simulates price updates with configurable decimals
 * - Allows manual price updates for testing different scenarios
 * - Implements full AggregatorV3Interface
 * - Tracks round data for testing staleness checks
 *
 * Example Usage:
 * ```solidity
 * // Deploy with 8 decimals and $2000 initial price
 * MockV3Aggregator ethUsdFeed = new MockV3Aggregator(8, 2000e8);
 *
 * // Update price to simulate price movement
 * ethUsdFeed.updateAnswer(1800e8); // ETH drops to $1800
 * ```
 */
contract MockV3Aggregator {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint8 public decimals;
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint256 public latestRound;

    mapping(uint256 => int256) public getAnswer;
    mapping(uint256 => uint256) public getTimestamp;
    mapping(uint256 => uint256) private getStartedAt;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the mock price feed
     * @param _decimals Number of decimals for the price (typically 8 for USD pairs)
     * @param _initialAnswer Initial price value (e.g., 2000e8 for $2000)
     *
     * @dev Example: MockV3Aggregator(8, 2000e8) creates ETH/USD feed at $2000
     */
    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Updates the price to a new value
     * @param _answer New price value
     *
     * @dev Increments round number and updates timestamp
     * @dev Use this to simulate price movements in tests
     *
     * Example:
     * ```solidity
     * mockFeed.updateAnswer(1500e8); // Update ETH price to $1500
     * ```
     */
    function updateAnswer(int256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = block.timestamp;
        getStartedAt[latestRound] = block.timestamp;
    }

    /**
     * @notice Updates round data (for advanced testing scenarios)
     * @param _roundId Round identifier
     * @param _answer Price value
     * @param _timestamp Timestamp of the update
     * @param _startedAt When the round started
     */
    function updateRoundData(uint80 _roundId, int256 _answer, uint256 _timestamp, uint256 _startedAt) public {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = _timestamp;
        getStartedAt[latestRound] = _startedAt;
    }

    /*//////////////////////////////////////////////////////////////
                       AGGREGATOR V3 INTERFACE
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns data for a specific round
     * @param _roundId Round identifier
     * @return roundId The round ID
     * @return answer The price at that round
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round in which the answer was computed
     */
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, getAnswer[_roundId], getStartedAt[_roundId], getTimestamp[_roundId], _roundId);
    }

    /**
     * @notice Returns the latest round data
     * @return roundId The latest round ID
     * @return answer The latest price
     * @return startedAt When the latest round started
     * @return updatedAt When the latest round was updated
     * @return answeredInRound The round in which the answer was computed
     *
     * @dev This is the primary function used by VyqnoEngine for price fetching
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            uint80(latestRound),
            getAnswer[latestRound],
            getStartedAt[latestRound],
            getTimestamp[latestRound],
            uint80(latestRound)
        );
    }

    /**
     * @notice Returns a human-readable description
     * @return Description of the price feed
     */
    function description() external pure returns (string memory) {
        return "v0.8/tests/MockV3Aggregator.sol";
    }

    /**
     * @notice Returns the version number
     * @return Version identifier
     */
    function version() external pure returns (uint256) {
        return 0;
    }
}
