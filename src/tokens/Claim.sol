pragma solidity ^0.8.6;

// External references
import "../external/openzeppelin/ERC20.sol";

// Internal references
import "./BaseToken.sol";

// @title Claim token contract that allows excess collection pre-maturity
// @dev This is an EXAMPLE interface, the actual functions one needs
// to override depend on the ERC20 implementation
contract Claim is BaseToken {
    constructor(
        uint256 _maturity,
        address _divider,
        address _feed,
        string memory _name,
        string memory _symbol
    ) public BaseToken(_maturity, _divider, _feed, _name, _symbol) {}

    //    // @dev ERC20 override that adds a call to collect on each transfer
    //    function transferFrom(
    //        address src,
    //        address dst,
    //        uint256 balance
    //    )
    //    public
    //    override
    //    returns (bool) {
    //        return true;
    //    }

    function collect() external returns (uint256 _collected) {
        IDivider(divider).collect(msg.sender, address(feed), maturity, balanceOf(msg.sender));
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        IDivider(divider).collect(msg.sender, address(feed), maturity, amount);
    }
}
