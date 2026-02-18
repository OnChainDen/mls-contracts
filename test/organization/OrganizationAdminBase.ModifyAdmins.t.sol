// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {OrganizationAdminBaseSuiteBase} from "test/organization/helpers/OrganizationAdminBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationAdminBase.modifyAdmins` behavior.
 */
contract OrganizationAdminBaseModifyAdminsTest is OrganizationAdminBaseSuiteBase {
    /// @dev Non-guardian caller reverts via onlyGuardian.
    function test_modifyAdmins_nonGuardianCaller_revertsOnlyGuardian() public {
        // Arrange: valid baseline config, but call from a non-guardian account.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        AdminAuthParams memory auth;
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        // Act/Assert: authorization should fail before signature checks run.
        vm.prank(NON_GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });
    }

    /// @dev Guardian + valid signatures succeeds for add flow.
    function test_modifyAdmins_guardianWithValidAuth_addFlow_succeeds() public {
        address newAdmin = address(0x201);
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
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        assertTrue(harness.isAdmin(newAdmin), "new admin should be added");
        assertEq(harness.adminCount(), 2, "admin count should increment");
    }

    /// @dev Guardian + valid signatures succeeds for remove flow.
    function test_modifyAdmins_guardianWithValidAuth_removeFlow_succeeds() public {
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
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            authParams: auth
        });

        assertFalse(harness.isAdmin(admin2), "admin2 should be removed");
        assertEq(harness.adminCount(), 1, "admin count should decrement");
    }

    /// @dev Guardian + valid signatures succeeds for add+remove in one call.
    function test_modifyAdmins_guardianWithValidAuth_addAndRemove_succeeds() public {
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
        harness.modifyAdmins({
            adminsToAdd: buildArray(admin3), adminsToRemove: buildArray(admin2), newVotingThreshold: 2, authParams: auth
        });

        assertTrue(harness.isAdmin(admin3), "admin3 should be added");
        assertFalse(harness.isAdmin(admin2), "admin2 should be removed");
        assertEq(harness.adminCount(), 2, "final admin count should remain 2");
    }

    /// @dev Signatures for different operation type cannot authorize modifyAdmins.
    function test_modifyAdmins_signaturesForDifferentOperationType_cannotAuthorize() public {
        address newAdmin = address(0x202);
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

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: wrongAuth
        });

        // Nonce for the actual ModifyAdmins payload must stay unused because auth failed.
        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, operationData, salt);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Rejection signatures cannot execute modifyAdmins.
    function test_modifyAdmins_rejectionSignatures_cannotExecuteApprovalPath() public {
        address newAdmin = address(0x203);
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

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: rejectionAuth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, operationData, 2005);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Mutating adminsToAdd after signing causes authorization failure.
    function test_modifyAdmins_mutateAdminsToAddAfterSigning_reverts() public {
        address signedAdmin = address(0x204);
        address mutatedAdmin = address(0x205);
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

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(mutatedAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, mutatedOperationData, 2006);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Mutating adminsToRemove after signing causes authorization failure.
    function test_modifyAdmins_mutateAdminsToRemoveAfterSigning_reverts() public {
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

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(admin3),
            newVotingThreshold: 2,
            authParams: auth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, mutatedOperationData, 2007);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Mutating threshold after signing causes authorization failure.
    function test_modifyAdmins_mutateThresholdAfterSigning_reverts() public {
        address newAdmin = address(0x206);
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

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, mutatedOperationData, 2008);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Reordering adminsToAdd after signing invalidates signatures.
    function test_modifyAdmins_reorderAdminsToAddAfterSigning_reverts() public {
        address a = address(0x207);
        address b = address(0x208);
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

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: mutatedAdds, adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2, authParams: auth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, mutatedOperationData, 2009);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Reordering adminsToRemove after signing invalidates signatures.
    function test_modifyAdmins_reorderAdminsToRemoveAfterSigning_reverts() public {
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

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: mutatedRemovals,
            newVotingThreshold: 1,
            authParams: auth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, mutatedOperationData, 2010);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Expired auth params revert AdminOperationExpired.
    function test_modifyAdmins_expiredAuth_revertsAdminOperationExpired() public {
        address newAdmin = address(0x209);
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

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expiration, block.timestamp)
        );
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });
    }

    /// @dev Replay same nonce reverts NonceAlreadyUsed.
    function test_modifyAdmins_replaySameNonce_revertsNonceAlreadyUsed() public {
        address newAdmin = address(0x20A);
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
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, operationData, salt);
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });
    }

    /// @dev Downstream revert rolls back state and nonce consumption.
    function test_modifyAdmins_downstreamRevert_rollsBackNonceConsumption() public {
        address nonMember = address(0x20B);
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

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, operationData, salt);

        // Auth succeeds, then mutation fails in LibOrganizationAdmin because candidate is not a member.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, nonMember));
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(nonMember),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        // Transaction revert must also roll back nonce consumption.
        assertFalse(_isNonceUsed(nonce), "nonce should not remain consumed on downstream revert");
    }

    /// @dev Invalid threshold downstream revert also rolls back nonce.
    function test_modifyAdmins_invalidThresholdDownstreamRevert_rollsBackNonceConsumption() public {
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

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, operationData, salt);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 0, 1));
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 0,
            authParams: auth
        });

        assertFalse(_isNonceUsed(nonce), "nonce should not remain consumed on downstream revert");
    }

    /// @dev Emits AdminAdded/AdminRemoved/VotingThresholdUpdated with correct args.
    function test_modifyAdmins_emitsExpectedEventsOnSuccess() public {
        address newAdmin = address(0x20C);
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

        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminAdded(newAdmin);
        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminRemoved(admin2);
        vm.expectEmit(false, false, false, true);
        emit IOrganizationAdmin.VotingThresholdUpdated(2, 1);

        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            authParams: auth
        });
    }

    /// @dev No VotingThresholdUpdated event when threshold is unchanged.
    function test_modifyAdmins_unchangedThreshold_doesNotEmitVotingThresholdUpdated() public {
        address newAdmin = address(0x20D);
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
        harness.modifyAdmins({
            adminsToAdd: buildArray(newAdmin),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        // Verify no threshold-update event was emitted when threshold did not change.
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 votingThresholdUpdatedSig = keccak256("VotingThresholdUpdated(uint256,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(
                entries[i].topics[0] != votingThresholdUpdatedSig,
                "VotingThresholdUpdated must not be emitted when threshold is unchanged"
            );
        }
    }

    /// @dev Mixed EOA + ERC-1271 admin signatures authorize modifyAdmins successfully.
    function test_modifyAdmins_mixedEOAAndERC1271Signatures_authorizeSuccessfully() public {
        address contractAdmin = address(validSigner1271);
        address newAdmin = address(0x20E);
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
        bytes32 operationHash = _computeOperationHash({
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
        harness.modifyAdmins({
            adminsToAdd: adminsToAdd, adminsToRemove: adminsToRemove, newVotingThreshold: newThreshold, authParams: auth
        });

        assertTrue(harness.isAdmin(newAdmin), "new admin should be added");
    }
}
