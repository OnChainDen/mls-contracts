// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Shared setup/helpers for `LibPolicyParameterConstraints` subsection suites.
 */
abstract contract LibPolicyParameterConstraintsSuiteBase is LibOrganizationPolicySuiteBase {
    /// @dev Deterministic selector used for handcrafted calldata fixtures.
    bytes4 internal constant BASE_SELECTOR = bytes4(0x12345678);

    /**
     * @dev Builds an empty Merkle proof array.
     */
    function _emptyProof() internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](0);
    }

    /**
     * @dev Builds a one-element constraints array.
     */
    function _constraints(ParameterConstraint memory first)
        internal
        pure
        returns (ParameterConstraint[] memory constraints)
    {
        constraints = new ParameterConstraint[](1);
        constraints[0] = first;
    }

    /**
     * @dev Builds a two-element constraints array.
     */
    function _constraints(ParameterConstraint memory first, ParameterConstraint memory second)
        internal
        pure
        returns (ParameterConstraint[] memory constraints)
    {
        constraints = new ParameterConstraint[](2);
        constraints[0] = first;
        constraints[1] = second;
    }

    /**
     * @dev Builds a three-element constraints array.
     */
    function _constraints(
        ParameterConstraint memory first,
        ParameterConstraint memory second,
        ParameterConstraint memory third
    ) internal pure returns (ParameterConstraint[] memory constraints) {
        constraints = new ParameterConstraint[](3);
        constraints[0] = first;
        constraints[1] = second;
        constraints[2] = third;
    }

    /**
     * @dev Unsafely mutates `paramType` enum backing value to craft malformed-enum inputs.
     */
    function _unsafeSetParamType(ParameterConstraint memory constraint, uint256 rawValue)
        internal
        pure
        returns (ParameterConstraint memory)
    {
        assembly {
            mstore(constraint, rawValue)
        }
        return constraint;
    }

    /**
     * @dev Unsafely mutates `constraintType` enum backing value to craft malformed-enum inputs.
     */
    function _unsafeSetConstraintType(ParameterConstraint memory constraint, uint256 rawValue)
        internal
        pure
        returns (ParameterConstraint memory)
    {
        assembly {
            mstore(add(constraint, 0x20), rawValue)
        }
        return constraint;
    }

    /**
     * @dev Encodes an address to the 32-byte ABI head representation used by helpers.
     */
    function _encodeAddressHead(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }

    /**
     * @dev Encodes a single dynamic-bytes argument calldata blob for helper tests.
     */
    function _encodeSingleBytesArg(bytes memory value) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(BASE_SELECTOR, value);
    }

    /**
     * @dev Encodes a single-string argument calldata blob for helper tests.
     */
    function _encodeSingleStringArg(string memory value) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(BASE_SELECTOR, value);
    }
}
