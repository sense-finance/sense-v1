// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Mintable.sol";

// @title Zero token contract that allows Divider contract to burn Zero tokens for any address
// @dev This is an EXAMPLE interface, the actual functions one needs
// to override depend on the ERC20 implementation
contract BaseToken is Mintable {
    // The Target token's address this feed applies to
    uint256 public maturity;
    address public divider;
    address public feed;

    constructor(
        uint256 _maturity,
        address _divider,
        address _feed,
        string memory _name,
        string memory _symbol
    ) Mintable(_name, _symbol) {
        maturity = _maturity;
        divider = _divider;
        feed = _feed;
    }

    /**
     * @dev Mintable override that adds onlyWards auth.
     * See {Mintable-burn}.
     * @param usr The address to send the minted tokens.
     * @param amount The amount to be minted.
     **/
    function burn(address usr, uint256 amount) public virtual override onlyWards {
        super.burn(usr, amount);
    }
}
