// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationAdminBaseSuiteBase
} from "test/organization/base/OrganizationAdminBase/OrganizationAdminBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationAdminBase.rejectAdminOperation`.
 */
contract OrganizationAdminBaseRejectOperationTest is OrganizationAdminBaseSuiteBase {
    /// @dev Verifies that a non-guardian caller reverts via the `onlyGuardian` modifier.
    function test_rejectAdminOperation_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        AdminAuthParams memory auth;
        // Verify: non-guardian caller must be rejected by the guardian-only modifier.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(OperationType.Upgrade, bytes("payload"), auth);
    }

    /// @dev Verifies that a valid rejection succeeds and burns the nonce.
    function test_NMADB_RAO_1_rejectAdminOperation_validRejection_succeedsAndBurnsNonce() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
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
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(operationType, operationData, auth);

        // Rejection path intentionally burns the same nonce execution would use.
        uint256 nonce = harness.computeNonce({operationType: operationType, operationData: operationData, salt: salt});
        // Verify: assert that the nonce is marked used after successful authorization/execution.
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed by rejection");
    }

    /// @dev Verifies that `AdminOperationRejected` is emitted with the exact operation tuple.
    function test_NMADB_RAO_1_rejectAdminOperation_emitsAdminOperationRejectedWithExactArgs() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        OperationType operationType = OperationType.ModifyPolicies;
        // Casting a short literal to bytes32 keeps this test payload deterministic and explicit.
        // forge-lint: disable-next-line(unsafe-typecast)
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

        uint256 nonce = harness.computeNonce({operationType: operationType, operationData: operationData, salt: salt});

        // Verify: confirm the expected event (and args/topics) is emitted for this success path.

        vm.expectEmit(true, true, false, true);
        emit IOrganizationAdmin.AdminOperationRejected(operationType, operationData, nonce);

        vm.prank(GUARDIAN);
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(operationType, operationData, auth);
    }

    /// @dev Verifies that approval signatures cannot be reused to authorize a rejection.
    function test_rejectAdminOperation_approvalSignaturesCannotAuthorizeRejection() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
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

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(operationType, operationData, approvalAuth);

        uint256 nonce = harness.computeNonce({operationType: operationType, operationData: operationData, salt: salt});
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed rejection auth");
    }

    /// @dev Verifies that mutating the signed operation type or data causes a rejection authorization failure.
    function test_rejectAdminOperation_mutatingSignedPayload_reverts() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
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

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(OperationType.ModifyPolicies, signedData, authTypeMutation);

        AdminAuthParams memory authDataMutation = _buildAdminAuthParamsForEOA({
            operationType: OperationType.Upgrade,
            operationData: signedData,
            isApproval: false,
            salt: 2022,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(OperationType.Upgrade, mutatedData, authDataMutation);
    }

    /// @dev Verifies that expired auth params revert with `AdminOperationExpired`.
    function test_rejectAdminOperation_expiredAuth_revertsAdminOperationExpired() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
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

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expiration, block.timestamp)
        );
        vm.prank(GUARDIAN);
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(OperationType.Upgrade, abi.encode(address(0xAAE)), auth);
    }

    /// @dev Verifies that replaying a rejection with the same nonce reverts with `NonceAlreadyUsed`.
    function test_NMADB_RAO_2_rejectAdminOperation_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
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
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(operationType, operationData, auth);

        uint256 nonce = harness.computeNonce({operationType: operationType, operationData: operationData, salt: salt});
        // Verify: replay protection should reject nonce reuse.
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(operationType, operationData, auth);
    }

    /// @dev Verifies that rejecting first and then executing the same payload fails due to the consumed nonce.
    function test_NMADB_RAO_4_rejectThenExecuteSamePayload_executionFailsByUsedNonce() public {
        address newAdmin = address(0x210);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
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
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(OperationType.ModifyAdmins, operationData, rejectionAuth);

        // Same operation/salt pair should now be replay-protected.
        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});
        // Verify: replay protection should reject nonce reuse.
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: adminsToAdd,
            adminsToRemove: adminsToRemove,
            newVotingThreshold: newThreshold,
            authParams: approvalAuth
        });
    }

    /// @dev Verifies that executing first and then rejecting the same payload fails due to the consumed nonce.
    function test_NMADB_RAO_5_executeThenRejectSamePayload_rejectionFailsByUsedNonce() public {
        address newAdmin = address(0x211);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
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
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: adminsToAdd,
            adminsToRemove: adminsToRemove,
            newVotingThreshold: newThreshold,
            authParams: approvalAuth
        });

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});
        // Verify: replay protection should reject nonce reuse.
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(OperationType.ModifyAdmins, operationData, rejectionAuth);
    }

    /// @dev Verifies that a failed rejection authorization does not consume the nonce.
    function test_rejectAdminOperation_failedAuthorization_doesNotConsumeNonce() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
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

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(OperationType.Upgrade, mutatedData, auth);

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.Upgrade, operationData: mutatedData, salt: salt});
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "failed rejection authorization must not burn nonce");
    }

    /// @dev Verifies `OrganizationAdminBase.rejectAdminOperation` burns only the nonce for the rejected payload.
    function test_NMADB_RAO_3_rejectAdminOperation_wrongOperationDataConsumesDifferentNonceWithoutBlockingIntendedOperation()
        public
    {
        address intendedAdmin = address(0x212);
        address wrongAdmin = address(0x213);

        // Setup: configure one-admin auth, then build two distinct `ModifyAdmins` payloads that share the same salt.
        _setMembersAndAdmins({
            members: buildArray(admin1, intendedAdmin, wrongAdmin), admins: buildArray(admin1), threshold: 1
        });

        address[] memory intendedAdminsToAdd = buildArray(intendedAdmin);
        address[] memory wrongAdminsToAdd = buildArray(wrongAdmin);
        address[] memory noAdminsToRemove = buildEmptyAddressArray();
        uint256 salt = 2029;
        uint256 expiration = block.timestamp + 1 hours;

        bytes memory intendedOperationData =
            _encodeOperationDataForModifyAdmins(intendedAdminsToAdd, noAdminsToRemove, 1);
        bytes memory wrongOperationData = _encodeOperationDataForModifyAdmins(wrongAdminsToAdd, noAdminsToRemove, 1);

        AdminAuthParams memory rejectionAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: wrongOperationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        AdminAuthParams memory approvalAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: intendedOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: reject the wrong payload first, then execute the intended payload with the same salt.
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.ModifyAdmins, wrongOperationData, rejectionAuth);

        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: intendedAdminsToAdd,
            adminsToRemove: noAdminsToRemove,
            newVotingThreshold: 1,
            authParams: approvalAuth
        });

        uint256 wrongNonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: wrongOperationData, salt: salt});
        uint256 intendedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: intendedOperationData, salt: salt
        });

        // Verify: the rejected payload burns only its own nonce, and the intended admin mutation still succeeds.
        assertTrue(harness.getUsedNonce(wrongNonce), "wrong payload nonce should be consumed by rejection");
        assertTrue(harness.getUsedNonce(intendedNonce), "intended payload nonce should be consumed by execution");
        assertTrue(harness.isAdmin(intendedAdmin), "intended admin should be added");
        assertFalse(harness.isAdmin(wrongAdmin), "wrong payload should not mutate admin state");
    }

    /// @dev Verifies `OrganizationAdminBase.rejectAdminOperation` rejects `OperationType.AccountTransaction`.
    function test_NMADB_RAO_6_rejectAdminOperation_accountTransactionType_revertsAndDoesNotBurnNonce() public {
        bytes memory operationData = abi.encode(address(0xAB1), address(0xAB2), uint256(1), keccak256("tx"), uint256(9));
        uint256 salt = 2030;

        // Setup: configure one-admin auth signed over the account-transaction domain that reject-admin must reject.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.AccountTransaction,
            operationData: operationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: attempt to reject an account-transaction nonce through the admin-reject entry point.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminOperationType.selector, OperationType.AccountTransaction));
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.AccountTransaction, operationData, auth);

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.AccountTransaction, operationData: operationData, salt: salt});
        // Verify: the unsupported account-transaction domain leaves its nonce unused.
        assertFalse(harness.getUsedNonce(nonce), "account-transaction nonce should remain unused");
    }

    /// @dev Verifies `OrganizationAdminBase.rejectAdminOperation` rejects `OperationType.AccountTransactionRejection`.
    function test_NMADB_RAO_7_rejectAdminOperation_accountTransactionRejectionType_revertsAndDoesNotBurnNonce()
        public
    {
        bytes memory operationData = abi.encode(address(0xAB3), address(0xAB4), uint256(2), keccak256("reject"), uint256(10));
        uint256 salt = 2031;

        // Setup: configure one-admin auth signed over the account-transaction rejection domain that admin reject must reject.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.AccountTransactionRejection,
            operationData: operationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: attempt to reject an account-transaction rejection nonce through the admin-reject entry point.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdmin.InvalidAdminOperationType.selector, OperationType.AccountTransactionRejection
            )
        );
        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.AccountTransactionRejection, operationData, auth);

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.AccountTransactionRejection, operationData: operationData, salt: salt
        });
        // Verify: the unsupported account-transaction rejection domain leaves its nonce unused.
        assertFalse(harness.getUsedNonce(nonce), "account-transaction rejection nonce should remain unused");
    }

    /// @dev Verifies that rejection works for supported admin operation types when properly signed.
    function test_rejectAdminOperation_supportedAdminOperationTypes_workWhenProperlySigned() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        OperationType[2] memory operationTypes = [OperationType.Upgrade, OperationType.ModifyPolicies];
        // Casting a short literal to bytes32 is intentional for deterministic synthetic operation payloads.
        // forge-lint: disable-next-line(unsafe-typecast)
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
            // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
            harness.rejectAdminOperation(operationTypes[i], operationData[i], auth);

            uint256 nonce =
                harness.computeNonce({operationType: operationTypes[i], operationData: operationData[i], salt: salt});
            // Verify: assert that the nonce is marked used after successful authorization/execution.
            assertTrue(harness.getUsedNonce(nonce), "rejection should consume nonce for arbitrary operation type");
        }
    }

    /// @dev Verifies that empty operation data can be rejected when signatures cover the empty payload.
    function test_rejectAdminOperation_emptyOperationData_canBeRejected() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
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
        // Call: invoke `rejectAdminOperation` for the prepared operation tuple and rejection auth params.
        harness.rejectAdminOperation(OperationType.Upgrade, emptyOperationData, auth);

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.Upgrade, operationData: emptyOperationData, salt: salt});
        // Verify: assert that the nonce is marked used after successful authorization/execution.
        assertTrue(harness.getUsedNonce(nonce), "empty payload rejection should consume nonce");
    }
}
