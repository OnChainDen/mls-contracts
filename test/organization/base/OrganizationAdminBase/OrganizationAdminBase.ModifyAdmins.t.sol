// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationAdminBaseSuiteBase
} from "test/organization/base/OrganizationAdminBase/OrganizationAdminBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationAdminBase.modifyAdmins` behavior.
 */
contract OrganizationAdminBaseModifyAdminsTest is OrganizationAdminBaseSuiteBase {
    /// @dev Verifies that a non-guardian caller reverts via the `onlyGuardian` modifier.
    function test_modifyAdmins_nonGuardianCaller_revertsOnlyGuardian() public {
        // Arrange: valid baseline config, but call from a non-guardian account.
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        AdminAuthParams memory auth;
        // Verify: non-guardian caller must be rejected by the guardian-only modifier.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        // Act/Assert: authorization should fail before signature checks run.
        vm.prank(NON_GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });
    }

    /// @dev Verifies that a guardian with valid signatures can add a new admin.
    function test_modifyAdmins_guardianWithValidAuth_addFlow_succeeds() public {
        address newAdmin = address(0x201);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, newAdmin), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: 2001,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        // Verify: assert that the address has admin status expected for this branch.

        assertTrue(harness.isAdmin(newAdmin), "new admin should be added");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 2, "admin count should increment");
    }

    /// @dev Verifies that a guardian with valid signatures can remove an existing admin.
    function test_modifyAdmins_guardianWithValidAuth_removeFlow_succeeds() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            salt: 2002,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            authParams: auth
        });

        // Verify: assert that the address does not have admin status for this branch.

        assertFalse(harness.isAdmin(admin2), "admin2 should be removed");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 1, "admin count should decrement");
    }

    /// @dev Verifies that a guardian with valid signatures can add and remove admins in one call.
    function test_modifyAdmins_guardianWithValidAuth_addAndRemove_succeeds() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2), threshold: 2
        });

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(admin3),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 2,
            salt: 2003,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(admin3), adminsToRemove: buildArray(admin2), newVotingThreshold: 2, authParams: auth
        });

        // Verify: assert that the address has admin status expected for this branch.

        assertTrue(harness.isAdmin(admin3), "admin3 should be added");
        // Verify: assert that the address does not have admin status for this branch.
        assertFalse(harness.isAdmin(admin2), "admin2 should be removed");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 2, "final admin count should remain 2");
    }

    /// @dev Verifies that signatures for a different operation type cannot authorize `modifyAdmins`.
    function test_modifyAdmins_signaturesForDifferentOperationType_cannotAuthorize() public {
        address newAdmin = address(0x202);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, newAdmin), admins: buildArray(admin1), threshold: 1});

        bytes memory operationData =
            _encodeOperationDataForModifyAdmins(buildArray(newAdmin), buildEmptyAddressArray(), 1);
        uint256 salt = 2004;
        uint256 expiration = block.timestamp + 1 hours;

        AdminAuthParams memory wrongAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyMembers,
            operationData: operationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: wrongAuth
        });

        // Nonce for the actual ModifyAdmins payload must stay unused because auth failed.
        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");

        // Nonce for the wrongAuth (ModifyMembers) payload must also stay unused.
        uint256 wrongAuthNonce = harness.computeNonce({
            operationType: OperationType.ModifyMembers, operationData: operationData, salt: salt
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(wrongAuthNonce), "wrong auth nonce should remain unused");
    }

    /// @dev Verifies that rejection signatures cannot execute the `modifyAdmins` approval path.
    function test_modifyAdmins_rejectionSignatures_cannotExecuteApprovalPath() public {
        address newAdmin = address(0x203);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, newAdmin), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory rejectionAuth, bytes memory operationData) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: 2005,
            expiration: block.timestamp + 1 hours,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: rejectionAuth
        });

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: 2005});
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies that mutating `adminsToAdd` after signing causes an authorization failure.
    function test_modifyAdmins_mutateAdminsToAddAfterSigning_reverts() public {
        address signedAdmin = address(0x204);
        address mutatedAdmin = address(0x205);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, signedAdmin, mutatedAdmin), admins: buildArray(admin1), threshold: 1
        });

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(signedAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: 2006,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Execute with a different payload than what was signed.
        bytes memory mutatedOperationData =
            _encodeOperationDataForModifyAdmins(buildArray(mutatedAdmin), buildEmptyAddressArray(), 1);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(mutatedAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2006
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies that mutating `adminsToRemove` after signing causes an authorization failure.
    function test_modifyAdmins_mutateAdminsToRemoveAfterSigning_reverts() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 2
        });

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 2,
            salt: 2007,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        bytes memory mutatedOperationData =
            _encodeOperationDataForModifyAdmins(buildEmptyAddressArray(), buildArray(admin3), 2);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(admin3),
            newVotingThreshold: 2,
            authParams: auth
        });

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2007
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies that mutating the threshold after signing causes an authorization failure.
    function test_modifyAdmins_mutateThresholdAfterSigning_reverts() public {
        address newAdmin = address(0x206);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, newAdmin), admins: buildArray(admin1, admin2), threshold: 2
        });

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2,
            salt: 2008,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        bytes memory mutatedOperationData =
            _encodeOperationDataForModifyAdmins(buildArray(newAdmin), buildEmptyAddressArray(), 1);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2008
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies that reordering `adminsToAdd` after signing invalidates the signatures.
    function test_modifyAdmins_reorderAdminsToAddAfterSigning_reverts() public {
        address a = address(0x207);
        address b = address(0x208);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, a, b), admins: buildArray(admin1, admin2), threshold: 2
        });

        address[] memory signedAdds = buildArray(a, b);
        address[] memory mutatedAdds = buildArray(b, a);

        // Array ordering is part of the signed hash and therefore part of authorization.
        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: signedAdds,
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2,
            salt: 2009,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        bytes memory mutatedOperationData =
            _encodeOperationDataForModifyAdmins(mutatedAdds, buildEmptyAddressArray(), 2);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: mutatedAdds, adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2, authParams: auth
        });

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2009
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies that reordering `adminsToRemove` after signing invalidates the signatures.
    function test_modifyAdmins_reorderAdminsToRemoveAfterSigning_reverts() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 2
        });

        address[] memory signedRemovals = buildArray(admin2, admin3);
        address[] memory mutatedRemovals = buildArray(admin3, admin2);

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: signedRemovals,
            newVotingThreshold: 1,
            salt: 2010,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        bytes memory mutatedOperationData =
            _encodeOperationDataForModifyAdmins(buildEmptyAddressArray(), mutatedRemovals, 1);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: mutatedRemovals,
            newVotingThreshold: 1,
            authParams: auth
        });

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2010
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies that expired auth params revert with `AdminOperationExpired`.
    function test_modifyAdmins_expiredAuth_revertsAdminOperationExpired() public {
        address newAdmin = address(0x209);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, newAdmin), admins: buildArray(admin1), threshold: 1});

        uint256 expiration = block.timestamp - 1;
        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: 2011,
            expiration: expiration,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expiration, block.timestamp)
        );
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });
    }

    /// @dev Verifies that replaying the same nonce reverts with `NonceAlreadyUsed`.
    function test_modifyAdmins_replaySameNonce_revertsNonceAlreadyUsed() public {
        address newAdmin = address(0x20A);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, newAdmin), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 2012;
        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: salt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});
        // Verify: replay protection should reject nonce reuse.
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });
    }

    /// @dev Verifies that a downstream revert rolls back both state and nonce consumption.
    function test_modifyAdmins_downstreamRevert_rollsBackNonceConsumption() public {
        address nonMember = address(0x20B);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 2013;
        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(nonMember),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: salt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});

        // Auth succeeds, then mutation fails in LibOrganizationAdmin because candidate is not a member.
        // Verify: confirm this branch reverts for the intended failure condition.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, nonMember));
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(nonMember),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        // Transaction revert must also roll back nonce consumption.
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should not remain consumed on downstream revert");
    }

    /// @dev Verifies that an invalid-threshold downstream revert also rolls back nonce consumption.
    function test_modifyAdmins_invalidThresholdDownstreamRevert_rollsBackNonceConsumption() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 2014;
        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyAdminsAuth({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 0,
            salt: salt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 0, 1));
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 0,
            authParams: auth
        });

        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.

        assertFalse(harness.getUsedNonce(nonce), "nonce should not remain consumed on downstream revert");
    }

    /// @dev Verifies that `AdminAdded`, `AdminRemoved`, and `VotingThresholdUpdated` events are emitted with correct
    /// args.
    function test_modifyAdmins_emitsExpectedEventsOnSuccess() public {
        address newAdmin = address(0x20C);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, newAdmin), admins: buildArray(admin1, admin2), threshold: 2
        });

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            salt: 2015,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        // Verify: confirm the expected event (and args/topics) is emitted for this success path.

        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminAdded(newAdmin);
        // Verify: confirm the expected event (and args/topics) is emitted for this success path.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminRemoved(admin2);
        // Verify: confirm the expected event (and args/topics) is emitted for this success path.
        vm.expectEmit(false, false, false, true);
        emit IOrganizationAdmin.VotingThresholdUpdated(2, 1);

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            authParams: auth
        });
    }

    /// @dev Verifies that no `VotingThresholdUpdated` event is emitted when the threshold is unchanged.
    function test_modifyAdmins_unchangedThreshold_doesNotEmitVotingThresholdUpdated() public {
        address newAdmin = address(0x20D);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, newAdmin), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: 2016,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.recordLogs();
        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        // Verify no threshold-update event was emitted when threshold did not change.
        Vm.Log[] memory actualLogs = vm.getRecordedLogs();
        bytes32 expectVotingThresholdUpdatedSig = keccak256("VotingThresholdUpdated(uint256,uint256)");
        for (uint256 i = 0; i < actualLogs.length; i++) {
            // Verify: confirm the resulting state/value matches the expected branch outcome.
            assertTrue(
                actualLogs[i].topics[0] != expectVotingThresholdUpdatedSig,
                "VotingThresholdUpdated must not be emitted when threshold is unchanged"
            );
        }
    }

    /// @dev Verifies that mixed EOA and ERC-1271 admin signatures authorize `modifyAdmins` successfully.
    function test_modifyAdmins_mixedEOAAndERC1271Signatures_authorizeSuccessfully() public {
        address contractAdmin = address(validSigner1271);
        address newAdmin = address(0x20E);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, contractAdmin, newAdmin),
            admins: buildArray(admin1, contractAdmin),
            threshold: 2
        });

        address[] memory adminsToAdd = buildArray(newAdmin);
        address[] memory adminsToRemove = buildEmptyAddressArray();
        uint256 newThreshold = 2;
        uint256 salt = 2017;
        uint256 expiration = block.timestamp + 1 hours;

        bytes memory operationData = _encodeOperationDataForModifyAdmins(adminsToAdd, adminsToRemove, newThreshold);
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        address[] memory signers = buildArray(admin1, contractAdmin);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signHash(ADMIN_PK_1, operationHash);
        signatures[1] = _buildContractSignature({signer: contractAdmin, innerSig: hex"abcd"});

        AdminAuthParams memory auth = AdminAuthParams({
            salt: salt, expirationTimestamp: expiration, signatures: _sortAndConcatSignatures(signers, signatures)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: adminsToAdd, adminsToRemove: adminsToRemove, newVotingThreshold: newThreshold, authParams: auth
        });

        // Verify: assert that the address has admin status expected for this branch.

        assertTrue(harness.isAdmin(newAdmin), "new admin should be added");
    }
}
