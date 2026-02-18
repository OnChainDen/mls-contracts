// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationAdminHarness} from "test/organization/harness/LibOrganizationAdminHarness.sol";
import {LibOrganizationAdminSuiteBase} from "test/organization/helpers/LibOrganizationAdminSuiteBase.sol";
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

    /// @dev Deterministic hash for same input tuple.
    function test_getAdminOperationHash_sameInput_isDeterministic() public view {
        bytes memory operationData = abi.encode("op68", uint256(1));

        bytes32 a = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 1,
            expirationTimestamp: 10,
            isApproval: true
        });
        bytes32 b = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 1,
            expirationTimestamp: 10,
            isApproval: true
        });

        assertEq(a, b, "hash must be deterministic");
    }

    /// @dev Different operationType yields different hash.
    function test_getAdminOperationHash_differentOperationType_producesDifferentHash() public view {
        bytes memory operationData = abi.encode("op69");

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

        assertTrue(a != b, "hash must bind operationType");
    }

    /// @dev Different operationData yields different hash.
    function test_getAdminOperationHash_differentOperationData_producesDifferentHash() public view {
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

        assertTrue(a != b, "hash must bind operationData");
    }

    /// @dev Different salt yields different hash.
    function test_getAdminOperationHash_differentSalt_producesDifferentHash() public view {
        bytes memory operationData = abi.encode("op71");

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

        assertTrue(a != b, "hash must bind salt");
    }

    /// @dev Different expirationTimestamp yields different hash.
    function test_getAdminOperationHash_differentExpiration_producesDifferentHash() public view {
        bytes memory operationData = abi.encode("op72");

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

        assertTrue(a != b, "hash must bind expiration timestamp");
    }

    /// @dev isApproval=true/false yields different hash.
    function test_getAdminOperationHash_differentIsApproval_producesDifferentHash() public view {
        bytes memory operationData = abi.encode("op73");

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

        assertTrue(approval != rejection, "hash must domain-separate approval and rejection");
    }

    /// @dev Different chainId yields different hash.
    function test_getAdminOperationHash_differentChainId_producesDifferentHash() public {
        bytes memory operationData = abi.encode("op74");
        bytes32 oldHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 14,
            expirationTimestamp: 103,
            isApproval: true
        });

        vm.chainId(block.chainid + 7);
        bytes32 newHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 14,
            expirationTimestamp: 103,
            isApproval: true
        });

        assertTrue(oldHash != newHash, "hash must bind chainId");
    }

    /// @dev Different contract address yields different hash.
    function test_getAdminOperationHash_differentContractAddress_producesDifferentHash() public {
        bytes memory operationData = abi.encode("op75");
        LibOrganizationAdminHarness secondHarness = new LibOrganizationAdminHarness();

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

        assertTrue(a != b, "hash must bind verifying contract");
    }

    /// @dev Hash equals manual EIP-712 typed-data computation.
    function test_getAdminOperationHash_matchesManualEIP712Computation() public view {
        bytes memory operationData = abi.encode("op76", uint256(42));
        uint256 salt = 16;
        uint256 expiration = 105;
        bool isApproval = true;
        OperationType operationType = OperationType.ModifyPolicies;

        bytes32 libraryHash = harness.getAdminOperationHash({
            operationType: operationType,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: isApproval
        });

        // Build a reference struct hash from the EIP-712 schema used by this protocol.
        bytes32 structHash = keccak256(
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
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("MLSWalletOrganization"),
                keccak256("1"),
                block.chainid,
                address(harness)
            )
        );

        bytes32 manualHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        assertEq(libraryHash, manualHash, "manual EIP-712 hash must match library output");
    }

    /// @dev Same bytes content across different memory instances yields identical hash.
    function test_getAdminOperationHash_sameByteContentDifferentMemoryInstances_sameHash() public view {
        bytes memory operationDataA = abi.encode("same-content", uint256(77));
        bytes memory operationDataB = abi.encode("same-content", uint256(77));

        bytes32 hashA = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationDataA,
            salt: 17,
            expirationTimestamp: 106,
            isApproval: true
        });
        bytes32 hashB = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationDataB,
            salt: 17,
            expirationTimestamp: 106,
            isApproval: true
        });

        assertEq(hashA, hashB, "hashing must depend on byte content, not memory pointer");
    }
}
