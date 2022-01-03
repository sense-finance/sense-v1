// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { DateTime } from "./external/DateTime.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

// Internal references
import { Divider } from "./Divider.sol";
import { Claim } from "./tokens/Claim.sol";
import { Zero } from "./tokens/Zero.sol";
import { BaseAdapter as Adapter } from "./adapters/BaseAdapter.sol";

library TokenFactory {
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;

    function deployTokens(
        address divider,
        address adapter,
        uint48 maturity
    ) internal returns (address zero, address claim) {
        zero = address(new Zero{ salt: keccak256(abi.encode(adapter, maturity)) }(divider, adapter, maturity));
        claim = address(new Claim{ salt: keccak256(abi.encode(adapter, maturity)) }(divider, adapter, maturity));
    }

    function getTokenAddresses(
        address divider,
        address adapter,
        uint48 maturity
    ) internal returns (address zero, address claim) {
        zero = address(
            keccak256(
                abi.encodePacked(
                    // Prefix:
                    hex"ff",
                    // Creator:
                    divider,
                    // Salt:
                    keccak256(abi.encode(adapter, maturity)),
                    // Bytecode hash:
                    keccak256(
                        abi.encodePacked(
                            // Deployment bytecode:
                            type(Zero).creationCode,
                            // Constructor arguments:
                            abi.encode(divider, adapter, maturity)
                        )
                    )
                )
            ).fromLast20Bytes()
        );

        claim = address(
            keccak256(
                abi.encodePacked(
                    hex"ff",
                    divider,
                    keccak256(abi.encode(adapter, maturity)),
                    keccak256(
                        abi.encodePacked(
                            type(Claim).creationCode,
                            abi.encode(divider, adapter, maturity)
                        )
                    )
                )
            ).fromLast20Bytes()
        );
    }

    function tokensExist(
        address divider,
        address adapter,
        uint48 maturity
    ) internal returns (bool) {
        address zero = address(
            keccak256(
                abi.encodePacked(
                    // Prefix:
                    hex"ff",
                    // Creator:
                    divider,
                    // Salt:
                    keccak256(abi.encode(adapter, maturity)),
                    // Bytecode hash:
                    keccak256(
                        abi.encodePacked(
                            // Deployment bytecode:
                            type(Zero).creationCode,
                            // Constructor arguments:
                            abi.encode(divider, adapter, maturity)
                        )
                    )
                )
            ).fromLast20Bytes()
        );

        // There should never be a case where one token is deployed without the other
        return address(zero).code.length > 0;
    }
}
