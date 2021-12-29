pragma solidity >=0.7.0;

// External references
import { DateTime } from "./external/DateTime.sol";

// Internal references
import { Divider } from "./Divider.sol";
import { Claim } from "./tokens/Claim.sol";
import { Token } from "./tokens/Token.sol";
import { BaseAdapter as Adapter } from "./adapters/BaseAdapter.sol";

library TokenFactory {
    string internal constant ZERO_SYMBOL_PREFIX = "z";
    string internal constant ZERO_NAME_PREFIX = "Zero";
    string internal constant CLAIM_SYMBOL_PREFIX = "c";
    string internal constant CLAIM_NAME_PREFIX = "Claim";

    function create(
        address divider,
        address adapter,
        uint48 maturity
    ) internal returns (address zero, address claim) {
        Token target = Token(Adapter(adapter).getTarget());
        uint8 decimals = target.decimals();
        string memory name = target.name();

        (, string memory m, string memory y) = DateTime.toDateString(maturity);
        string memory datestring = string(abi.encodePacked(m, "-", y));
        string memory adapterId = DateTime.uintToString(Divider(divider).adapterIDs(adapter));

        zero = address(
            new Token{ salt: keccak256(abi.encode(adapter, maturity, "zero")) }(
                string(abi.encodePacked(name, " ", datestring, " ", ZERO_NAME_PREFIX, " #", adapterId, " by Sense")),
                string(abi.encodePacked(ZERO_SYMBOL_PREFIX, target.symbol(), ":", datestring, ":#", adapterId)),
                decimals,
                divider
            )
        );

        claim = address(
            new Claim{ salt: keccak256(abi.encode(adapter, maturity, "claim")) }(
                maturity,
                divider,
                adapter,
                string(abi.encodePacked(name, " ", datestring, " ", CLAIM_NAME_PREFIX, " #", adapterId, " by Sense")),
                string(abi.encodePacked(CLAIM_SYMBOL_PREFIX, target.symbol(), ":", datestring, ":#", adapterId)),
                decimals
            )
        );
    }

    function getTokenAddresses(
        address divider,
        address adapter,
        uint48 maturity
    ) internal returns (address zero, address claim) {
        zero = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        divider,
                        keccak256(abi.encode(adapter, maturity, "zero")),
                        ZERO_INIT_CODE_HASH
                    )
                )
            )
        );

        claim = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        divider,
                        keccak256(abi.encode(adapter, maturity, "claim")),
                        CLAIM_INIT_CODE_HASH
                    )
                )
            )
        );
    }
}
