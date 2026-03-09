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
    /**
     * @dev Recovers the EOA signer from a single packed `v|r|s` signature for the provided hash.
     * @param signature Packed 65-byte signature in `v|r|s` format
     * @param hash Operation hash used during verification
     * @return signer Recovered signer address, or `address(0)` if recovery fails
     */
    function _recoverEOASigner(bytes memory signature, bytes32 hash) internal pure returns (address signer) {
        require(signature.length == 65, "invalid signature length");

        uint8 v;
        bytes32 r;
        bytes32 s;

        assembly {
            v := byte(0, mload(add(signature, 0x20)))
            r := mload(add(signature, 0x21))
            s := mload(add(signature, 0x41))
        }

        signer = ecrecover(hash, v, r, s);
    }

    /// @dev Verifies `OrganizationAdminBase.modifyAdmins` reverts for non-guardian callers.
    function test_OAB_MA_2_modifyAdmins_nonGuardianCaller_revertsOnlyGuardian() public {
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

    /// @dev Verifies `OrganizationAdminBase.modifyAdmins` adds/removes admins and updates the threshold in one
    /// authorized execution.
    function test_OAB_MA_1_modifyAdmins_guardianWithValidAuth_addsRemovesAndUpdatesThreshold_endToEnd() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2), threshold: 2
        });

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(admin3),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            salt: 2003,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(admin3), adminsToRemove: buildArray(admin2), newVotingThreshold: 1, authParams: auth
        });

        // Verify: assert that the address has admin status expected for this branch.

        assertTrue(harness.isAdmin(admin3), "admin3 should be added");
        // Verify: assert that the address does not have admin status for this branch.
        assertFalse(harness.isAdmin(admin2), "admin2 should be removed");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 2, "final admin count should remain 2");
        assertEq(harness.votingThreshold(), 1, "voting threshold should update in the same execution");
    }

    /// @dev Verifies `OrganizationAdminBase.modifyAdmins` rejects duplicate signer entries in the packed approval
    /// signature list.
    function test_OAB_MA_3_modifyAdmins_duplicateSigner_revertsDuplicateOrOutOfOrderAdminSigner() public {
        address newAdmin = address(0x20F);
        // Setup: require two admin signatures, then build an approval payload that repeats the same signer twice.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, newAdmin), admins: buildArray(admin1, admin2), threshold: 2
        });

        uint256 salt = 2032;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory operationData =
            _encodeOperationDataForModifyAdmins(buildArray(newAdmin), buildEmptyAddressArray(), 2);
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signHash(ADMIN_PK_1, operationHash);
        signatures[1] = _signHash(ADMIN_PK_1, operationHash);
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: _concatSignatures(signatures)});

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});

        // Call: execute the admin mutation with duplicate signer entries and expect strict ordering validation to
        // reject the packed signatures.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, admin1, admin1)
        );
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2,
            authParams: auth
        });

        // Verify: duplicate-signer validation should fail before consuming the nonce or mutating admin state.
        assertFalse(harness.getUsedNonce(nonce), "duplicate signer revert should not consume nonce");
        assertFalse(harness.isAdmin(newAdmin), "duplicate signer revert should not add the admin");
    }

    /// @dev Verifies `OrganizationAdminBase.modifyAdmins` rejects out-of-order signer entries in the packed approval
    /// signature list.
    function test_OAB_MA_3_modifyAdmins_outOfOrderSigners_revertsDuplicateOrOutOfOrderAdminSigner() public {
        address newAdmin = address(0x210);
        // Setup: require two admin signatures, then build an approval payload whose packed signatures are descending by
        // signer address.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, newAdmin), admins: buildArray(admin1, admin2), threshold: 2
        });

        uint256 salt = 2033;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory operationData =
            _encodeOperationDataForModifyAdmins(buildArray(newAdmin), buildEmptyAddressArray(), 2);
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        bytes[] memory signatures = new bytes[](2);
        address firstSigner;
        address secondSigner;
        if (uint160(admin1) > uint160(admin2)) {
            signatures[0] = _signHash(ADMIN_PK_1, operationHash);
            signatures[1] = _signHash(ADMIN_PK_2, operationHash);
            firstSigner = admin1;
            secondSigner = admin2;
        } else {
            signatures[0] = _signHash(ADMIN_PK_2, operationHash);
            signatures[1] = _signHash(ADMIN_PK_1, operationHash);
            firstSigner = admin2;
            secondSigner = admin1;
        }
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: _concatSignatures(signatures)});

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});

        // Call: execute the admin mutation with out-of-order signatures and expect strict signer ordering validation
        // to reject the packed signatures.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, secondSigner, firstSigner
            )
        );
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2,
            authParams: auth
        });

        // Verify: out-of-order signer validation should fail before consuming the nonce or mutating admin state.
        assertFalse(harness.getUsedNonce(nonce), "out-of-order signatures should not consume nonce");
        assertFalse(harness.isAdmin(newAdmin), "out-of-order signatures should not add the admin");
    }

    /// @dev Verifies `OrganizationAdminBase.modifyAdmins` fails when a signer loses admin status after signatures are
    /// collected but before execution.
    function test_OAB_MA_4_modifyAdmins_adminRemovedAfterSigning_revertsSignerIsNotAdminAtExecutionTime() public {
        address newAdmin = address(0x211);
        // Setup: collect a valid two-admin approval, then demote one signer before the guardian executes the change.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, newAdmin), admins: buildArray(admin1, admin2), threshold: 2
        });

        uint256 salt = 2034;
        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2,
            salt: salt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        stateHarness.setAdminStatus(admin2, false);
        stateHarness.setAdminCount(1);

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});

        // Call: execute the pre-signed payload after the second signer has been demoted and expect live admin-status
        // validation to fail.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, admin2));
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2,
            authParams: auth
        });

        // Verify: execution-time admin validation should fail closed without consuming the nonce or mutating state.
        assertFalse(harness.getUsedNonce(nonce), "demoted-signer revert should not consume nonce");
        assertFalse(harness.isAdmin(newAdmin), "demoted-signer revert should not add the admin");
    }

    /// @dev Verifies `OrganizationAdminBase.modifyAdmins` rejects signatures that only satisfy the old threshold after
    /// the organization threshold increases.
    function test_OAB_MA_5_modifyAdmins_thresholdRaisedAfterSigning_revertsInsufficientAuthorization() public {
        address newAdmin = address(0x212);
        // Setup: collect a one-signature approval while the threshold is one, then raise the live threshold to two
        // before execution.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, newAdmin), admins: buildArray(admin1, admin2), threshold: 1
        });

        uint256 salt = 2035;
        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: salt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        stateHarness.setVotingThreshold(2);

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});

        // Call: execute the stale one-signature approval after the threshold rises and expect the live threshold check
        // to reject it.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        // Verify: the threshold change should invalidate the stale approval without consuming the nonce or changing
        // admin state.
        assertFalse(harness.getUsedNonce(nonce), "stale-threshold approval should not consume nonce");
        assertFalse(harness.isAdmin(newAdmin), "stale-threshold approval should not add the admin");
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

    /// @dev Verifies `OrganizationAdminBase.modifyAdmins` rejects signatures collected for the rejection domain.
    function test_OAB_RAO_3_modifyAdmins_rejectionSignatures_cannotExecuteApprovalPath() public {
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

        bytes32 approvalOperationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: 2005,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true
        });
        address recoveredSigner = _recoverEOASigner(rejectionAuth.signatures, approvalOperationHash);

        // Verify: using rejection-domain signatures for an approval execution should fail live signer validation and
        // leave the nonce unused.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, recoveredSigner));
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
        assertFalse(harness.getUsedNonce(nonce), "nonce for the operation should remain unused on failed auth");
    }

    /// @dev Verifies that mutating `adminsToAdd` after signing causes an authorization failure.
    function test_modifyAdmins_mutateAdminsToAddAfterSigning_reverts() public {
        address signedAdmin = address(0x204);
        address mutatedAdmin = address(0x205);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, signedAdmin, mutatedAdmin), admins: buildArray(admin1), threshold: 1
        });

        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildModifyAdminsAuth({
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

        uint256 mutatedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2006
        });
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: signedOperationData, salt: 2006
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(mutatedNonce), "mutated payload nonce should rollback on failed auth");
        assertFalse(harness.getUsedNonce(signedNonce), "signed payload nonce should remain unused on failed auth");
    }

    /// @dev Verifies that mutating `adminsToRemove` after signing causes an authorization failure.
    function test_modifyAdmins_mutateAdminsToRemoveAfterSigning_reverts() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 2
        });

        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildModifyAdminsAuth({
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

        uint256 mutatedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2007
        });
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: signedOperationData, salt: 2007
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(mutatedNonce), "mutated payload nonce should rollback on failed auth");
        assertFalse(harness.getUsedNonce(signedNonce), "signed payload nonce should remain unused on failed auth");
    }

    /// @dev Verifies that mutating the threshold after signing causes an authorization failure.
    function test_modifyAdmins_mutateThresholdAfterSigning_reverts() public {
        address newAdmin = address(0x206);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, newAdmin), admins: buildArray(admin1, admin2), threshold: 2
        });

        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildModifyAdminsAuth({
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

        uint256 mutatedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2008
        });
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: signedOperationData, salt: 2008
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(mutatedNonce), "mutated payload nonce should rollback on failed auth");
        assertFalse(harness.getUsedNonce(signedNonce), "signed payload nonce should remain unused on failed auth");
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
        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildModifyAdminsAuth({
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

        uint256 mutatedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2009
        });
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: signedOperationData, salt: 2009
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(mutatedNonce), "mutated payload nonce should rollback on failed auth");
        assertFalse(harness.getUsedNonce(signedNonce), "signed payload nonce should remain unused on failed auth");
    }

    /// @dev Verifies that reordering `adminsToRemove` after signing invalidates the signatures.
    function test_modifyAdmins_reorderAdminsToRemoveAfterSigning_reverts() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 2
        });

        address[] memory signedRemovals = buildArray(admin2, admin3);
        address[] memory mutatedRemovals = buildArray(admin3, admin2);

        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildModifyAdminsAuth({
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

        uint256 mutatedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: 2010
        });
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: signedOperationData, salt: 2010
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(mutatedNonce), "mutated payload nonce should rollback on failed auth");
        assertFalse(harness.getUsedNonce(signedNonce), "signed payload nonce should remain unused on failed auth");
    }

    /// @dev Verifies `OrganizationAdminBase.modifyAdmins` rejects expired auth and leaves the nonce unused.
    function test_OAB_MA_6_modifyAdmins_expiredAuth_revertsAndDoesNotConsumeNonce() public {
        address newAdmin = address(0x209);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, newAdmin), admins: buildArray(admin1), threshold: 1});

        uint256 expiration = block.timestamp - 1;
        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: 2011,
            expiration: expiration,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: 2011});

        // Call: execute the expired approval path and expect timestamp validation to revert before any nonce or state
        // mutation.
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

        // Verify: expired auth should leave the nonce unused and preserve admin state.
        assertFalse(harness.getUsedNonce(nonce), "expired auth should not consume nonce");
        assertFalse(harness.isAdmin(newAdmin), "expired auth should not add the admin");
    }

    /// @dev Verifies that replaying the same nonce reverts with `NonceAlreadyUsed`.
    function test_NMADB_MA_1_modifyAdmins_replaySameNonce_revertsNonceAlreadyUsed() public {
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
    function test_NMADB_MA_2_modifyAdmins_downstreamRevert_rollsBackNonceConsumption() public {
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
    function test_NMADB_MA_2_modifyAdmins_invalidThresholdDownstreamRevert_rollsBackNonceConsumption() public {
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
