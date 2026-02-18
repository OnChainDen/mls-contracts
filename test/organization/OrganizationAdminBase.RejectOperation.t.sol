// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {OrganizationAdminBaseSuiteBase} from "test/organization/helpers/OrganizationAdminBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationAdminBase.rejectAdminOperation`.
 */
contract OrganizationAdminBaseRejectOperationTest is OrganizationAdminBaseSuiteBase {
    /// @dev Non-guardian caller reverts via onlyGuardian.
    function test_rejectAdminOperation_nonGuardianCaller_revertsOnlyGuardian() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        AdminAuthParams memory auth;
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.rejectAdminOperation(OperationType.Upgrade, bytes("payload"), auth);
    }

    /// @dev Valid rejection succeeds and burns nonce.
    function test_rejectAdminOperation_validRejection_succeedsAndBurnsNonce() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        OperationType operationType = OperationType.Upgrade;
        bytes memory operationData = abi.encode(address(0xAAA));
        uint256 salt = 2018;
        uint256 expiration = block.timestamp + 1 hours;

        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: operationType,
            operationData: operationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(operationType, operationData, auth);

        // Rejection path intentionally burns the same nonce execution would use.
        uint256 nonce = _computeNonce(operationType, operationData, salt);
        assertTrue(_isNonceUsed(nonce), "nonce should be consumed by rejection");
    }

    /// @dev Emits AdminOperationRejected with exact tuple.
    function test_rejectAdminOperation_emitsAdminOperationRejectedWithExactArgs() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        OperationType operationType = OperationType.ModifyPolicies;
        bytes memory operationData = abi.encode(bytes32("policyRoot"), "ipfs://cid");
        uint256 salt = 2019;
        uint256 expiration = block.timestamp + 1 hours;

        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: operationType,
            operationData: operationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce = _computeNonce(operationType, operationData, salt);

        vm.expectEmit(true, true, false, true);
        emit IOrganizationAdmin.AdminOperationRejected(operationType, operationData, nonce);

        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(operationType, operationData, auth);
    }

    /// @dev Approval signatures cannot be reused for rejection.
    function test_rejectAdminOperation_approvalSignaturesCannotAuthorizeRejection() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        OperationType operationType = OperationType.Upgrade;
        bytes memory operationData = abi.encode(address(0xAAB));
        uint256 salt = 2020;
        uint256 expiration = block.timestamp + 1 hours;

        AdminAuthParams memory approvalAuth = _buildAdminAuthParamsForEOA({
            operationType: operationType,
            operationData: operationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(operationType, operationData, approvalAuth);

        uint256 nonce = _computeNonce(operationType, operationData, salt);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed rejection auth");
    }

    /// @dev Mutating signed operation type/data causes rejection authorization failure.
    function test_rejectAdminOperation_mutatingSignedPayload_reverts() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        bytes memory signedData = abi.encode(address(0xAAC));
        bytes memory mutatedData = abi.encode(address(0xAAD));

        AdminAuthParams memory authTypeMutation = _buildAdminAuthParamsForEOA({
            operationType: OperationType.Upgrade,
            operationData: signedData,
            isApproval: false,
            salt: 2021,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.ModifyPolicies, signedData, authTypeMutation);

        AdminAuthParams memory authDataMutation = _buildAdminAuthParamsForEOA({
            operationType: OperationType.Upgrade,
            operationData: signedData,
            isApproval: false,
            salt: 2022,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.Upgrade, mutatedData, authDataMutation);
    }

    /// @dev Expired auth params revert AdminOperationExpired.
    function test_rejectAdminOperation_expiredAuth_revertsAdminOperationExpired() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 expiration = block.timestamp - 1;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.Upgrade,
            operationData: abi.encode(address(0xAAE)),
            isApproval: false,
            salt: 2023,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expiration, block.timestamp)
        );
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.Upgrade, abi.encode(address(0xAAE)), auth);
    }

    /// @dev Replay rejection with same nonce reverts NonceAlreadyUsed.
    function test_rejectAdminOperation_replaySameNonce_revertsNonceAlreadyUsed() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        OperationType operationType = OperationType.Upgrade;
        bytes memory operationData = abi.encode(address(0xAAF));
        uint256 salt = 2024;

        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: operationType,
            operationData: operationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(operationType, operationData, auth);

        uint256 nonce = _computeNonce(operationType, operationData, salt);
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(operationType, operationData, auth);
    }

    /// @dev Reject first, then execution of same payload fails by used nonce.
    function test_rejectThenExecuteSamePayload_executionFailsByUsedNonce() public {
        address newAdmin = address(0x210);
        _setMembersAndAdmins({members: buildArray(admin1, newAdmin), admins: buildArray(admin1), threshold: 1});

        address[] memory adminsToAdd = buildArray(newAdmin);
        address[] memory adminsToRemove = buildEmptyAddressArray();
        uint256 newThreshold = 1;
        uint256 salt = 2025;
        uint256 expiration = block.timestamp + 1 hours;

        bytes memory operationData = _encodeOperationDataForModifyAdmins(adminsToAdd, adminsToRemove, newThreshold);
        AdminAuthParams memory rejectionAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        AdminAuthParams memory approvalAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.ModifyAdmins, operationData, rejectionAuth);

        // Same operation/salt pair should now be replay-protected.
        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, operationData, salt);
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: adminsToAdd,
            adminsToRemove: adminsToRemove,
            newVotingThreshold: newThreshold,
            authParams: approvalAuth
        });
    }

    /// @dev Execute first, then reject same payload fails by used nonce.
    function test_executeThenRejectSamePayload_rejectionFailsByUsedNonce() public {
        address newAdmin = address(0x211);
        _setMembersAndAdmins({members: buildArray(admin1, newAdmin), admins: buildArray(admin1), threshold: 1});

        address[] memory adminsToAdd = buildArray(newAdmin);
        address[] memory adminsToRemove = buildEmptyAddressArray();
        uint256 newThreshold = 1;
        uint256 salt = 2026;
        uint256 expiration = block.timestamp + 1 hours;

        bytes memory operationData = _encodeOperationDataForModifyAdmins(adminsToAdd, adminsToRemove, newThreshold);
        AdminAuthParams memory approvalAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        AdminAuthParams memory rejectionAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: adminsToAdd,
            adminsToRemove: adminsToRemove,
            newVotingThreshold: newThreshold,
            authParams: approvalAuth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, operationData, salt);
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.ModifyAdmins, operationData, rejectionAuth);
    }

    /// @dev Failed rejection authorization does not consume nonce.
    function test_rejectAdminOperation_failedAuthorization_doesNotConsumeNonce() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        bytes memory signedData = abi.encode("signed");
        bytes memory mutatedData = abi.encode("mutated");
        uint256 salt = 2027;

        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.Upgrade,
            operationData: signedData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.Upgrade, mutatedData, auth);

        uint256 nonce = _computeNonce(OperationType.Upgrade, mutatedData, salt);
        assertFalse(_isNonceUsed(nonce), "failed rejection authorization must not burn nonce");
    }

    /// @dev Rejection works for arbitrary operation types when properly signed.
    function test_rejectAdminOperation_arbitraryOperationTypes_workWhenProperlySigned() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        OperationType[2] memory operationTypes = [OperationType.Upgrade, OperationType.ModifyPolicies];
        bytes[2] memory operationData = [abi.encode(address(0xAB0)), abi.encode(bytes32("root"), "cid")];

        for (uint256 i = 0; i < operationTypes.length; i++) {
            uint256 salt = 3000 + i;
            // Build operation-type-specific rejection authorization.
            AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
                operationType: operationTypes[i],
                operationData: operationData[i],
                isApproval: false,
                salt: salt,
                expirationTimestamp: block.timestamp + 1 hours,
                privateKeys: buildUint256Array(ADMIN_PK_1)
            });

            vm.prank(GUARDIAN);
            harness.rejectAdminOperation(operationTypes[i], operationData[i], auth);

            uint256 nonce = _computeNonce(operationTypes[i], operationData[i], salt);
            assertTrue(_isNonceUsed(nonce), "rejection should consume nonce for arbitrary operation type");
        }
    }

    /// @dev Empty operationData can be rejected when signatures are for empty payload.
    function test_rejectAdminOperation_emptyOperationData_canBeRejected() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        bytes memory emptyOperationData = bytes("");
        uint256 salt = 2028;

        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.Upgrade,
            operationData: emptyOperationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.Upgrade, emptyOperationData, auth);

        uint256 nonce = _computeNonce(OperationType.Upgrade, emptyOperationData, salt);
        assertTrue(_isNonceUsed(nonce), "empty payload rejection should consume nonce");
    }
}
