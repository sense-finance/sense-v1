pragma solidity ^0.8.6;

// External references
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// @title Zero token contract that allows Divider contract to burn Zero tokens for any address
// @dev This is an EXAMPLE interface, the actual functions one needs
// to override depend on the ERC20 implementation
contract BaseToken is ERC20 {
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
    ) ERC20(_name, _symbol) {
        maturity = _maturity;
        divider = _divider;
        feed = _feed;
    }

    /**
     * @dev Mints new Zero or Claim tokens for usr, increasing the total supply.
     * @param usr The address to send the minted tokens.
     * @param amount The amount to be minted.
     **/
    function mint(address usr, uint256 amount) public onlyDivider {
        _mint(usr, amount);
        emit Mint(usr, amount);
    }

    /**
     * @dev ERC20 override that adds a call to collect on each burn.
     * @dev Destroys `amount` tokens from the caller.
     * See {ERC20-_burn}.
     * @param usr The address to send the minted tokens.
     * @param amount The amount to be minted.
     **/
    function burn(address usr, uint256 amount) public virtual onlyDivider {
        _burn(usr, amount);
        emit Burn(usr, amount);
    }

    /* ========== MODIFIERS ========== */
    function _onlyDivider() internal view {
        require(msg.sender == address(divider), "Sender is not Gov");
    }

    modifier onlyDivider() {
        _onlyDivider();
        _;
    }

    /* ========== EVENTS ========== */
    event Mint(address usr, uint256 amount);
    event Burn(address usr, uint256 amount);
}
