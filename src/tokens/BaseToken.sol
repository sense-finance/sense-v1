pragma solidity ^0.8.6;

// External references
import "../external/openzeppelin/ERC20.sol";

// Internal references
import "../interfaces/IDivider.sol";
import "../interfaces/IFeed.sol";

// @title Zero token contract that allows Divider contract to burn Zero tokens for any address
// @dev This is an EXAMPLE interface, the actual functions one needs
// to override depend on the ERC20 implementation
contract BaseToken is ERC20 {
    // The Target token's address this feed applies to
    uint256 public maturity;
    IDivider public divider;
    IFeed public feed;

    constructor(
        uint256 _maturity,
        address _divider,
        address _feed,
        string memory _name,
        string memory _symbol
    ) public ERC20(_name, _symbol) {
        maturity = _maturity;
        divider = IDivider(_divider);
        feed = IFeed(_feed);
    }

    /**
     * @dev Mints new Zero or Claim tokens for user, increasing the total supply.
     * @param user The address to send the minted tokens.
     * @param amount The amount to be minted.
     **/
    function mint(address user, uint256 amount) public onlyDivider {
        _mint(user, amount);
        emit Mint(user, amount);
    }

    /**
     * @dev ERC20 override that adds a call to collect on each burn.
     * @dev Destroys `amount` tokens from the caller.
     * See {ERC20-_burn}.
     * @param account The address to send the minted tokens.
     * @param amount The amount to be minted.
     **/
    function burn(address account, uint256 amount) public virtual onlyDivider {
        _burn(account, amount);
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
    event Mint(address user, uint256 amount);
}
