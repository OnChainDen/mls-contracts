// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAdminHarness
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminHarness.sol";
import {
    LibOrganizationAdminSuiteBase
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminSuiteBase.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for operation-hash helpers in `LibOrganizationAdmin`.
 */
contract LibOrganizationAdminHashingTest is LibOrganizationAdminSuiteBase {
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal constant ADMIN_OPERATION_TYPEHASH = keccak256(
        "AdminOperation(uint8 operationType,bytes operationData,uint256 salt,uint256 expirationTimestamp,bool isApproval,uint256 chainId,address organization)"
    );

    /// @dev Verifies that the same input tuple produces a deterministic hash.
    function test_getAdminOperationHash_sameInput_isDeterministic() public view {
        // Setup: define one operation payload and a fixed parameter tuple.
        bytes memory operationData = abi.encode("op68", uint256(1));

        // Call: compute operation hashes twice for identical inputs.
        bytes32 actualHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 1,
            expirationTimestamp: 10,
            isApproval: true
        });
        bytes32 expectHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 1,
            expirationTimestamp: 10,
            isApproval: true
        });

        // Verify: assert that the derived hash matches the expected reference hash.

        assertEq(actualHash, expectHash, "hash must be deterministic");
    }

    /// @dev Verifies that a different operation type produces a different hash.
    function test_getAdminOperationHash_differentOperationType_producesDifferentHash() public view {
        // Setup: define one payload used across both operation types.
        bytes memory operationData = abi.encode("op69");

        // Call: compute hashes for two operation types with the same remaining inputs.
        bytes32 a = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 2,
            expirationTimestamp: 11,
            isApproval: true
        });
        bytes32 b = harness.getAdminOperationHash({
            operationType: OperationType.ModifyMembers,
            operationData: operationData,
            salt: 2,
            expirationTimestamp: 11,
            isApproval: true
        });

        // Verify: assert that changing the selected input dimension changes the resulting hash.

        assertTrue(a != b, "hash must bind operationType");
    }

    /// @dev Verifies that different operation data produces a different hash.
    function test_getAdminOperationHash_differentOperationData_producesDifferentHash() public view {
        // Setup: define two distinct operation payloads.

        // Call: compute hashes for both payload variants.
        bytes32 a = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: abi.encode("A"),
            salt: 3,
            expirationTimestamp: 12,
            isApproval: true
        });
        bytes32 b = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: abi.encode("B"),
            salt: 3,
            expirationTimestamp: 12,
            isApproval: true
        });

        // Verify: assert that changing the selected input dimension changes the resulting hash.

        assertTrue(a != b, "hash must bind operationData");
    }

    /// @dev Verifies that a different salt produces a different hash.
    function test_getAdminOperationHash_differentSalt_producesDifferentHash() public view {
        // Setup: define one payload and two salt variants.
        bytes memory operationData = abi.encode("op71");

        // Call: compute hashes for both salt variants.
        bytes32 a = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 10,
            expirationTimestamp: 13,
            isApproval: true
        });
        bytes32 b = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 11,
            expirationTimestamp: 13,
            isApproval: true
        });

        // Verify: assert that changing the selected input dimension changes the resulting hash.

        assertTrue(a != b, "hash must bind salt");
    }

    /// @dev Verifies that a different expiration timestamp produces a different hash.
    function test_getAdminOperationHash_differentExpiration_producesDifferentHash() public view {
        // Setup: define one payload and two expiration variants.
        bytes memory operationData = abi.encode("op72");

        // Call: compute hashes for both expiration variants.
        bytes32 a = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 12,
            expirationTimestamp: 100,
            isApproval: true
        });
        bytes32 b = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 12,
            expirationTimestamp: 101,
            isApproval: true
        });

        // Verify: assert that changing the selected input dimension changes the resulting hash.

        assertTrue(a != b, "hash must bind expiration timestamp");
    }

    /// @dev Verifies that toggling `isApproval` produces a different hash.
    function test_getAdminOperationHash_differentIsApproval_producesDifferentHash() public view {
        // Setup: define one payload with approval and rejection variants.
        bytes memory operationData = abi.encode("op73");

        // Call: compute hashes for approval and rejection.
        bytes32 approval = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 13,
            expirationTimestamp: 102,
            isApproval: true
        });
        bytes32 rejection = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 13,
            expirationTimestamp: 102,
            isApproval: false
        });

        // Verify: assert that changing the selected input dimension changes the resulting hash.

        assertTrue(approval != rejection, "hash must domain-separate approval and rejection");
    }

    /// @dev Verifies that a different chain ID produces a different hash.
    function test_getAdminOperationHash_differentChainId_producesDifferentHash() public {
        // Setup: define one payload and keep all signed fields constant.
        bytes memory operationData = abi.encode("op74");

        // Call: compute hash on the original chain id.
        bytes32 oldHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 14,
            expirationTimestamp: 103,
            isApproval: true
        });

        // Call: switch chain id and recompute with the same payload.
        vm.chainId(block.chainid + 7);
        bytes32 newHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 14,
            expirationTimestamp: 103,
            isApproval: true
        });

        // Verify: assert that changing the selected input dimension changes the resulting hash.

        assertTrue(oldHash != newHash, "hash must bind chainId");
    }

    /// @dev Verifies that a different contract address produces a different hash.
    function test_getAdminOperationHash_differentContractAddress_producesDifferentHash() public {
        // Setup: define one payload and deploy a second harness address.
        bytes memory operationData = abi.encode("op75");
        LibOrganizationAdminHarness secondHarness = new LibOrganizationAdminHarness();

        // Call: compute hashes from two different verifying-contract addresses.
        bytes32 a = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 15,
            expirationTimestamp: 104,
            isApproval: true
        });
        bytes32 b = secondHarness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 15,
            expirationTimestamp: 104,
            isApproval: true
        });

        // Verify: assert that changing the selected input dimension changes the resulting hash.

        assertTrue(a != b, "hash must bind verifying contract");
    }

    /// @dev Verifies that the hash matches a manual EIP-712 typed-data computation.
    function test_getAdminOperationHash_matchesManualEIP712Computation() public view {
        // Setup: define one operation tuple and keep all signed fields explicit.
        bytes memory operationData = abi.encode("op76", uint256(42));
        uint256 salt = 16;
        uint256 expiration = 105;
        bool isApproval = true;
        OperationType operationType = OperationType.ModifyPolicies;

        // Call: compute the library-produced EIP-712 operation hash.
        bytes32 actualHash = harness.getAdminOperationHash({
            operationType: operationType,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: isApproval
        });

        // Build a reference struct hash from the EIP-712 schema used by this protocol.
        bytes32 expectStructHash = keccak256(
            abi.encode(
                ADMIN_OPERATION_TYPEHASH,
                uint8(operationType),
                keccak256(operationData),
                salt,
                expiration,
                isApproval,
                block.chainid,
                address(harness)
            )
        );

        // Build a reference domain separator from the protocol's typed-data domain fields.
        bytes32 expectDomainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("MLSWalletOrganization"),
                keccak256("1"),
                block.chainid,
                address(harness)
            )
        );

        bytes32 expectHash = keccak256(abi.encodePacked("\x19\x01", expectDomainSeparator, expectStructHash));
        // Verify: assert that the derived hash matches the expected reference hash.
        assertEq(actualHash, expectHash, "manual EIP-712 hash must match library output");
    }

    /// @dev Verifies that identical byte content in different memory instances produces the same hash.
    function test_getAdminOperationHash_sameByteContentDifferentMemoryInstances_sameHash() public view {
        // Setup: create two distinct byte arrays with identical content.
        bytes memory operationDataA = abi.encode("same-content", uint256(77));
        bytes memory operationDataB = abi.encode("same-content", uint256(77));

        // Call: compute hashes for both memory instances.
        bytes32 actualHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationDataA,
            salt: 17,
            expirationTimestamp: 106,
            isApproval: true
        });
        bytes32 expectHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationDataB,
            salt: 17,
            expirationTimestamp: 106,
            isApproval: true
        });

        // Verify: assert that the derived hash matches the expected reference hash.

        assertEq(actualHash, expectHash, "hashing must depend on byte content, not memory pointer");
    }
}
