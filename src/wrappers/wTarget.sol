// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { ERC20, SafeERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal
import { Divider } from "../Divider.sol";
import { BaseFeed as Feed } from "../feeds/BaseFeed.sol";

/// @notice
contract wTarget is Trust {
    using SafeERC20 for ERC20;
    using FixedMath for uint256;

    /// @notice Configuration
    uint256 MAX_INT = 2**256 - 1;

    /// @notice Mutable program state
    address public target;
    address public airdropToken;
    address public divider;
    mapping(address => uint256) public tBalances; // usr -> amount of airdrop tokens distributed
    mapping(address => uint256) public distributed; // usr -> amount of airdrop tokens distributed

    constructor(
        address _target,
        address _divider,
        address _airdropToken
    ) Trust(msg.sender) {
        target = _target;
        airdropToken = _airdropToken;
        divider = _divider;
        ERC20(target).approve(divider, MAX_INT);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Distributes airdropped tokens to Claim holders proportionally based on Claim balance
    /// @param _feed Feed to associate with the Series
    /// @param _maturity Maturity date
    /// @param _usr User to distribute airdrop tokens to
    function distribute(
        address _feed,
        uint256 _maturity,
        address _usr,
        uint256 collected
    ) external {
        (, address claim, , , , , ) = Divider(divider).series(_feed, _maturity);
        // uint256 scale = Divider(msg.sender).lscales(_feed, _maturity, _usr);
        // uint256 tBal = ERC20(_zero).balanceOf(_usr).fdiv(scale, 10**ERC20(target).decimals());
        // uint amount = (tBal / ERC20(target).balanceOf(address(this))) *
        // ERC20(airdropToken).balanceOf(address(this)) - distributed[_usr];
        uint256 amount = ERC20(claim).totalSupply() == 0
            ? 0
            : (ERC20(claim).balanceOf(_usr) / ERC20(claim).totalSupply()) *
                (ERC20(airdropToken).balanceOf(address(this)) - distributed[_usr]);
        // uint amount = ERC20(claim).totalSupply() == 0
        // ? 0
        // : (ERC20(claim).balanceOf(_usr) / ERC20(claim).totalSupply()) *
        // ERC20(airdropToken).balanceOf(address(this)) - distributed[_usr];
        emit Hi(ERC20(claim).totalSupply());
        emit Hi(ERC20(claim).balanceOf(_usr));
        emit Hi((ERC20(claim).balanceOf(_usr) / ERC20(claim).totalSupply()));
        emit Hi(ERC20(airdropToken).balanceOf(address(this)));
        emit Hi(amount);

        distributed[_usr] += amount;
        ERC20(airdropToken).transfer(_usr, amount);
        emit Distributed(_usr, airdropToken, amount);
    }

    /* ========== EVENTS ========== */
    event Distributed(address indexed usr, address indexed token, uint256 indexed amount);
    event Hi(uint256 h);
}
