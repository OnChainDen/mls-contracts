// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ContractInteractionUtils} from "libraries/ContractInteractionUtils.sol";
import {MerkleUtils} from "libraries/MerkleUtils.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Policy Parameter Constraints
 * @dev Library for validating function call parameter constraints.
 *      Handles validation of function parameters against policy-defined constraints.
 *      Supports various parameter types (uint, int, address, bool, bytes, etc.) and
 *      constraint types (exact, range, list).
 * @author Den Technologies Inc
 */
library LibPolicyParameterConstraints {
    /**
     * @dev Checks if transaction parameters match the specified constraints.
     *      Iterates through each constraint and validates the corresponding parameter.
     *      Each constraint contains its own proof for OneOf constraints, eliminating
     *      the need for separate proof arrays.
     *
     *      Constraint validation for dynamic types (Bytes, String) does not enforce ABI
     *      canonical encoding. See _isBytesOrStringParameterAllowedByConstraint for details.
     * @param parameterConstraints ABI-encoded array of ParameterConstraint structs
     * @param data The transaction calldata
     * @return True if all constraints are satisfied, false otherwise
     */
    function areParametersAllowedByConstraints(bytes calldata parameterConstraints, bytes calldata data)
        internal
        pure
        returns (bool)
    {
        // Case: No constraints defined, any parameters are accepted
        if (parameterConstraints.length == 0) return true;

        // Case: Malformed top-level ABI encoding fails closed before decode.
        // `abi.encode(ParameterConstraint[])` must contain at least offset + length (2 words).
        if (parameterConstraints.length < 64) return false;

        // Decode the constraints array
        ParameterConstraint[] memory constraints = abi.decode(parameterConstraints, (ParameterConstraint[]));

        // Case: No constraints in the array
        if (constraints.length == 0) return true;

        // Use a helper function to process constraints (reduces stack depth)
        return _processConstraints(constraints, data);
    }

    /**
     * @dev Internal helper to process parameter constraints.
     *      Separated to manage stack depth in the main function.
     *      Each constraint is self-contained with its own merkle proof for OneOf constraints.
     * @param constraints The array of parameter constraints to validate
     * @param data The full transaction calldata
     * @return True if all constraints are satisfied, false otherwise
     */
    function _processConstraints(ParameterConstraint[] memory constraints, bytes calldata data)
        internal
        pure
        returns (bool)
    {
        // Validate each parameter against its constraint
        // Parameters start at byte 4 (after the selector)
        uint256 paramCalldataOffset = ContractInteractionUtils.SELECTOR_LENGTH;

        for (uint256 i = 0; i < constraints.length; ++i) {
            // Case: Primitive and dynamic single-head types cannot declare multi-slot heads.
            if (
                constraints[i].paramCalldataHeadSlotCount > 1 && constraints[i].paramType != ParamType.Array
                    && constraints[i].paramType != ParamType.Struct
            ) {
                return false;
            }

            // Number of bytes this parameter's head occupies in calldata
            uint256 paramCalldataHeadSize =
                uint256(constraints[i].paramCalldataHeadSlotCount) * ContractInteractionUtils.SLOT_SIZE;

            // Case: Constraint is not configured correctly (paramCalldataHeadSlotCount == 0)
            if (paramCalldataHeadSize == 0) {
                return false;
            }

            // Case: Transaction data is too short for this parameter (not enough data for the full parameter head)
            if (data.length < paramCalldataOffset + paramCalldataHeadSize) {
                return false;
            }

            // Extract the first 32 bytes of the parameter head for validation
            // Note: For multi-slot params like static arrays/structs, only "Any" constraint is supported,
            // so we don't need to extract the full parameter value
            bytes32 paramHeadValue =
                bytes32(data[paramCalldataOffset:paramCalldataOffset + ContractInteractionUtils.SLOT_SIZE]);

            // Case: The parameter does not satisfy its constraint
            // Each constraint carries its own proof for OneOf constraints
            if (!_isParameterAllowedByConstraint(constraints[i], paramHeadValue, data)) {
                return false;
            }

            // Move on to the next parameter in calldata
            paramCalldataOffset += paramCalldataHeadSize;
        }

        return true;
    }

    /**
     * @dev Validates a single parameter against its constraint.
     *      Dispatches to type-specific validation functions based on parameter type.
     *      For Address+OneOf constraints, the merkle proof is read from constraint.paramValueInListProof.
     * @param constraint The constraint to validate against (includes proof for OneOf constraints)
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @param data The full transaction calldata (for dynamic types)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isParameterAllowedByConstraint(
        ParameterConstraint memory constraint,
        bytes32 paramHeadValue,
        bytes calldata data
    ) internal pure returns (bool) {
        ConstraintType constraintType = constraint.constraintType;
        ParamType pType = constraint.paramType;

        // Case: Constraint is a wildcard constraint (any value is accepted)
        if (constraintType == ConstraintType.Any) {
            return true;
        }

        bytes memory comparisonData = constraint.comparisonData;

        if (pType == ParamType.Bool) {
            return _isBoolParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue);
        }

        if (pType == ParamType.Uint) {
            return _isUintParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue);
        }

        if (pType == ParamType.Int) {
            return _isIntParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue);
        }

        if (pType == ParamType.Address) {
            return _isAddressParameterAllowedByConstraint(
                constraintType, comparisonData, paramHeadValue, constraint.paramValueInListProof
            );
        }

        if (pType == ParamType.FixedBytes) {
            return _isFixedBytesParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue);
        }

        // Bytes and String have identical ABI encoding, so we use the same validation function
        if (pType == ParamType.Bytes || pType == ParamType.String) {
            return _isBytesOrStringParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue, data);
        }

        // Case: The parameter is an Array or Struct type, which only support the "Any" constraint
        // If we reach here, the constraint type is not "Any", which is invalid for these types.
        if (pType == ParamType.Array || pType == ParamType.Struct) {
            return false;
        }

        // Case: The parameter is an unknown type
        return false;
    }

    /**
     * @dev Validates a Bool parameter against its constraint.
     *      Bool only supports Exact constraint.
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isBoolParameterAllowedByConstraint(
        ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue
    ) internal pure returns (bool) {
        if (constraintType != ConstraintType.Exact) return false;
        if (comparisonData.length != ContractInteractionUtils.SLOT_SIZE) return false;

        uint256 expectedValueRaw = abi.decode(comparisonData, (uint256));
        uint256 actualValueRaw = uint256(paramHeadValue);

        // Enforce canonical bool encoding (0/1 only).
        if (expectedValueRaw > 1 || actualValueRaw > 1) return false;

        return expectedValueRaw == actualValueRaw;
    }

    /**
     * @dev Validates a Uint parameter against its constraint.
     *      Uint supports Exact and Range constraints (also used for enums).
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value(s) encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isUintParameterAllowedByConstraint(
        ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue
    ) internal pure returns (bool) {
        uint256 actualValue = uint256(paramHeadValue);
        if (constraintType == ConstraintType.Exact) {
            if (comparisonData.length != ContractInteractionUtils.SLOT_SIZE) return false;
            uint256 expectedValue = abi.decode(comparisonData, (uint256));
            return actualValue == expectedValue;
        }
        if (constraintType == ConstraintType.Range) {
            if (comparisonData.length != 2 * ContractInteractionUtils.SLOT_SIZE) return false;
            (uint256 minValue, uint256 maxValue) = abi.decode(comparisonData, (uint256, uint256));
            return actualValue >= minValue && actualValue <= maxValue;
        }
        // Uint doesn't support OneOf constraint
        return false;
    }

    /**
     * @dev Validates an Int parameter against its constraint.
     *      Int supports Exact and Range constraints.
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value(s) encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isIntParameterAllowedByConstraint(
        ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue
    ) internal pure returns (bool) {
        int256 actualValue = int256(uint256(paramHeadValue));
        if (constraintType == ConstraintType.Exact) {
            if (comparisonData.length != ContractInteractionUtils.SLOT_SIZE) return false;
            int256 expectedValue = abi.decode(comparisonData, (int256));
            return actualValue == expectedValue;
        }
        if (constraintType == ConstraintType.Range) {
            if (comparisonData.length != 2 * ContractInteractionUtils.SLOT_SIZE) return false;
            (int256 minValue, int256 maxValue) = abi.decode(comparisonData, (int256, int256));
            return actualValue >= minValue && actualValue <= maxValue;
        }
        // Int doesn't support OneOf constraint
        return false;
    }

    /**
     * @dev Validates an Address parameter against its constraint.
     *      Address supports Exact and OneOf constraints.
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value or merkle root encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @param addressListProof Merkle proof for OneOf constraint (empty for Exact constraint)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isAddressParameterAllowedByConstraint(
        ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue,
        bytes32[] memory addressListProof
    ) internal pure returns (bool) {
        address actualValue = address(uint160(uint256(paramHeadValue)));
        if (constraintType == ConstraintType.Exact) {
            if (comparisonData.length != ContractInteractionUtils.SLOT_SIZE) return false;
            address expectedValue = abi.decode(comparisonData, (address));
            return actualValue == expectedValue;
        }
        if (constraintType == ConstraintType.OneOf) {
            if (comparisonData.length != ContractInteractionUtils.SLOT_SIZE) return false;
            // comparisonData contains the merkle root of allowed addresses
            bytes32 allowedAddressesRoot = abi.decode(comparisonData, (bytes32));
            // Compute leaf for the actual address using double-hashing
            bytes32 addressLeaf = MerkleUtils.computeAddressLeaf(actualValue);
            // Verify the address is in the allowed addresses merkle tree
            return MerkleProof.verify(addressListProof, allowedAddressesRoot, addressLeaf);
        }
        // Address doesn't support Range constraint
        return false;
    }

    /**
     * @dev Validates a FixedBytes parameter against its constraint.
     *      FixedBytes (bytes1-bytes32) only supports Exact constraint.
     *      For fixed-size bytes, the value is stored directly in the 32-byte slot (left-aligned).
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isFixedBytesParameterAllowedByConstraint(
        ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue
    ) internal pure returns (bool) {
        if (constraintType != ConstraintType.Exact) return false;
        if (comparisonData.length != ContractInteractionUtils.SLOT_SIZE) return false;
        bytes32 expectedValue = abi.decode(comparisonData, (bytes32));
        return paramHeadValue == expectedValue;
    }

    /**
     * @dev Validates a dynamic Bytes or String parameter against its constraint.
     *      Dynamic bytes and strings only support Exact constraint (hash comparison).
     *      Both types have identical ABI encoding (offset -> length -> data), so this
     *      function handles both ParamType.Bytes and ParamType.String.
     *      The paramHeadValue contains the offset to the data location in calldata.
     *      The comparisonData should contain the keccak256 hash of the expected bytes/string.
     *
     *      This function does NOT enforce ABI canonical encoding. It follows the offset in
     *      paramHeadValue to locate the dynamic payload without verifying that the offset
     *      points to the canonical tail position for that parameter. Non-canonical but
     *      otherwise valid calldata layouts (e.g., non-monotonic offsets, overlapping tails)
     *      will pass validation as long as the referenced payload hashes to the expected value.
     *      Standard Solidity decoders follow the same offset, so destination contracts will
     *      typically decode the same value that was validated. It is the responsibility of
     *      admins and the Guardian to ensure that calldata is canonically ABI-encoded.
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected hash encoded as bytes
     * @param paramHeadValue The parameter value (offset to bytes/string data)
     * @param data The full transaction calldata
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isBytesOrStringParameterAllowedByConstraint(
        ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue,
        bytes calldata data
    ) internal pure returns (bool) {
        if (constraintType != ConstraintType.Exact) return false;
        if (comparisonData.length != ContractInteractionUtils.SLOT_SIZE) return false;

        // paramHeadValue is the offset (relative to start of encoded params, i.e., after selector)
        uint256 offset = uint256(paramHeadValue);

        // Case: Offsets pointing into the ABI head region are invalid.
        if (offset < ContractInteractionUtils.SLOT_SIZE) return false;

        // Case: Offset arithmetic overflow fails closed.
        if (offset > type(uint256).max - ContractInteractionUtils.SELECTOR_LENGTH) return false;

        // The offset is relative to the start of the encoded parameters (after selector)
        // So actual position in data = 4 (selector) + offset
        uint256 dataPosition = ContractInteractionUtils.SELECTOR_LENGTH + offset;

        // First 32 bytes at that position is the length
        if (dataPosition > data.length) return false;
        if (data.length - dataPosition < ContractInteractionUtils.SLOT_SIZE) return false;

        uint256 length = uint256(bytes32(data[dataPosition:dataPosition + ContractInteractionUtils.SLOT_SIZE]));

        if (dataPosition > type(uint256).max - ContractInteractionUtils.SLOT_SIZE) return false;
        uint256 dataStart = dataPosition + ContractInteractionUtils.SLOT_SIZE;

        // Check we have enough data for the content
        if (length > data.length - dataStart) return false;
        uint256 dataEnd = dataStart + length;

        // Hash the actual content
        bytes32 actualHash = keccak256(data[dataStart:dataEnd]);
        bytes32 expectedHash = abi.decode(comparisonData, (bytes32));
        return actualHash == expectedHash;
    }
}
