// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Vyqno Stable Coin
 * @author Hitesh P
 * @notice This contract is the implementation of the Vyqno Stable Coin (VYQNO)
 * @notice VYQNO is a decentralized, collateral-backed stable coin pegged to the USD
 * @notice This contract allows only the owner (VyqnoEngine.sol) to mint and burn VYQNO tokens 
 *          1. Minting: When users deposit collateral into the VyqnoEngine, it mints VSC tokens to the user's address.
 *          2. Burning: When users repay their stable coin debt, the VyqnoEngine burns VSC tokens from the user's address.
 */

contract VyqnoStableCoin is ERC20Burnable, Ownable {

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error VyqnoStableCoin__AmountLessThanEqualToZero();
    error VyqnoStableCoin__BurnAmountExceedsBalance();
    error VyqnoStableCoin__NotZeroAddress();



    /**
     * @notice ERC20 constructor takes in the name and symbol of the token
     * @notice Ownable constructor sets the owner of the contract to the deployer
     */
    constructor() ERC20("VyqnoStableCoin", "VSC") Ownable(msg.sender) {}

    /**
     * @notice Burns VSC tokens (only callable by VyqnoEngine)
     * @param _amount The amount of VSC to burn
     * @dev Burns tokens from the caller's (Engine's) balance
     */
    function burn(uint256 _amount) public override onlyOwner{
        if(_amount <= 0) revert VyqnoStableCoin__AmountLessThanEqualToZero();   //  Can't mint negative or 0 tokens
        super.burn(_amount);
    }


    /**
     * @notice Mints VSC tokens to a specified address (only callable by VyqnoEngine)
     * @param _to The address of the user who deposited the collateratl 
     * @param _amount The amount of VSC to mint for that user 
     * @dev Used when users deposit collateral
     */
    function mint(address _to, uint256 _amount) external onlyOwner{
        if (_to == address(0))  revert VyqnoStableCoin__NotZeroAddress();  //  Can't send tokens to a black hole i.e address(0)
        if(_amount <= 0) revert VyqnoStableCoin__AmountLessThanEqualToZero();   //  Can't mint negative or 0 tokens
        _mint(_to, _amount);
        }   

}
