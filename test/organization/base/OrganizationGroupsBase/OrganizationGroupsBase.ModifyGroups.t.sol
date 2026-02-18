// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {
    OrganizationGroupsBaseSuiteBase
} from "test/organization/base/OrganizationGroupsBase/OrganizationGroupsBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {GroupModification, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationGroupsBase.modifyGroups` behavior.
 */
contract OrganizationGroupsBaseModifyGroupsTest is OrganizationGroupsBaseSuiteBase {
    /**
     * @dev Raw-typed group modification used to craft malformed enum calldata.
     *      ABI shape intentionally mirrors `GroupModification` with `modificationType` as an unchecked integer.
     */
    struct RawGroupModification {
        uint256 groupId;
        uint256 modificationType;
        address[] membersToAdd;
        address[] membersToRemove;
    }

    /// @dev Verifies guardian + valid admin auth forwards to library and applies expected state transition.
    function test_modifyGroups_guardianWithValidAuth_forwardsAndAppliesStateTransition() public {
        uint256 groupId = 7901;

        // Setup: one-admin threshold-one auth configuration.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory modifications =
            _buildModificationsArray(_createModification(groupId, buildArray(admin1)));

        (AdminAuthParams memory auth,) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: 3101,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, auth);

        // Verify: base call reached library and mutated groups state.
        assertTrue(harness.isGroup(groupId), "group should be active");
        assertTrue(harness.isGroupMember(groupId, admin1), "member should be in group");
    }

    /// @dev Verifies non-guardian caller reverts via `onlyGuardian`.
    function test_modifyGroups_nonGuardianCaller_revertsOnlyGuardian() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory modifications = new GroupModification[](0);
        AdminAuthParams memory auth;

        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.modifyGroups(modifications, auth);
    }

    /// @dev Verifies insufficient signatures revert through admin-auth validation.
    function test_modifyGroups_insufficientSignatures_revertsViaAdminAuthValidation() public {
        uint256 groupId = 7902;

        // Setup: threshold=2 but provide one signature.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        GroupModification[] memory modifications =
            _buildModificationsArray(_createModification(groupId, buildArray(admin1)));

        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: 3102,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, auth);

        uint256 nonce = _computeModifyGroupsNonce(operationData, 3102);
        assertFalse(groupsStateHarness.getUsedNonce(nonce), "failed auth should not consume nonce");
    }

    /// @dev Verifies expired auth params revert through admin-auth validation.
    function test_modifyGroups_expiredAuthParams_revertsViaAdminAuthValidation() public {
        uint256 groupId = 7903;

        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory modifications =
            _buildModificationsArray(_createModification(groupId, buildArray(admin1)));

        uint256 expiration = block.timestamp - 1;
        (AdminAuthParams memory auth,) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: 3103,
            expiration: expiration,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expiration, block.timestamp)
        );
        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, auth);
    }

    /// @dev Verifies replaying the same salt/operation after success reverts with `NonceAlreadyUsed`.
    function test_modifyGroups_replaySameNonce_revertsAfterSuccessfulExecution() public {
        uint256 groupId = 7904;

        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory modifications =
            _buildModificationsArray(_createModification(groupId, buildArray(admin1)));

        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: 3104,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, auth);

        uint256 nonce = _computeModifyGroupsNonce(operationData, 3104);
        assertTrue(groupsStateHarness.getUsedNonce(nonce), "nonce should be consumed on success");

        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, auth);
    }

    /// @dev Verifies desired behavior that failed auth does not consume nonce and corrected signatures can succeed.
    function test_modifyGroups_failedAuth_doesNotConsumeNonceAndCanRetryWithCorrectedSignatures() public {
        uint256 groupId = 7905;

        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        GroupModification[] memory modifications =
            _buildModificationsArray(_createModification(groupId, buildArray(admin1)));

        // First attempt: insufficient signatures.
        (AdminAuthParams memory badAuth, bytes memory operationData) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: 3105,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, badAuth);

        uint256 nonce = _computeModifyGroupsNonce(operationData, 3105);
        assertFalse(groupsStateHarness.getUsedNonce(nonce), "failed auth must not consume nonce");

        // Retry with same payload/salt and corrected signatures.
        (AdminAuthParams memory goodAuth,) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: 3105,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, goodAuth);

        assertTrue(groupsStateHarness.getUsedNonce(nonce), "nonce should be consumed on successful retry");
        assertTrue(harness.isGroup(groupId), "group should be created after successful retry");
    }

    /// @dev Verifies signed payload tampering invalidates auth and reverts.
    function test_modifyGroups_modificationDataTamperingAfterSigning_invalidatesAuthAndReverts() public {
        uint256 signedGroupId = 7906;
        uint256 mutatedGroupId = 7907;

        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory signedModifications =
            _buildModificationsArray(_createModification(signedGroupId, buildArray(admin1)));
        GroupModification[] memory mutatedModifications =
            _buildModificationsArray(_createModification(mutatedGroupId, buildArray(admin1)));

        (AdminAuthParams memory auth,) = _buildModifyGroupsAuth({
            modifications: signedModifications,
            salt: 3106,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.modifyGroups(mutatedModifications, auth);

        bytes memory mutatedOperationData = _encodeOperationDataForModifyGroups(mutatedModifications);
        uint256 mutatedNonce = _computeModifyGroupsNonce(mutatedOperationData, 3106);
        assertFalse(groupsStateHarness.getUsedNonce(mutatedNonce), "failed tampered payload must not consume nonce");
        assertFalse(harness.isGroup(signedGroupId), "signed target group should remain unchanged");
        assertFalse(harness.isGroup(mutatedGroupId), "tampered target group should remain unchanged");
    }

    /// @dev Verifies empty modifications still require valid auth and consume nonce on success.
    function test_modifyGroups_emptyModifications_requireValidAuthAndConsumeNonce() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory modifications = new GroupModification[](0);

        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: 3107,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, auth);

        uint256 nonce = _computeModifyGroupsNonce(operationData, 3107);
        assertTrue(groupsStateHarness.getUsedNonce(nonce), "empty successful operation should consume nonce");
    }

    /// @dev Verifies library custom errors bubble through base unchanged.
    function test_modifyGroups_libraryCustomErrors_bubbleThroughBaseUnchanged() public {
        uint256 nonExistentGroupId = 7908;

        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory modifications = _buildModificationsArray(
            _updateModification(nonExistentGroupId, buildArray(admin1), buildEmptyAddressArray())
        );

        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: 3108,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, nonExistentGroupId));
        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, auth);

        // Library revert should rollback nonce consumption from prior auth step.
        uint256 nonce = _computeModifyGroupsNonce(operationData, 3108);
        assertFalse(groupsStateHarness.getUsedNonce(nonce), "nonce should rollback on downstream library revert");
    }

    /// @dev Verifies malformed enum payloads revert through base path and do not mutate state.
    function test_modifyGroups_malformedEnumPayload_revertsAndLeavesStateUnchanged() public {
        uint256 groupId = 7909;

        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        RawGroupModification[] memory rawModifications = new RawGroupModification[](1);
        rawModifications[0] = RawGroupModification({
            groupId: groupId,
            modificationType: 77,
            membersToAdd: buildArray(admin1),
            membersToRemove: buildEmptyAddressArray()
        });

        uint256 salt = 3109;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory operationData = abi.encode(keccak256(abi.encode(rawModifications)));
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyGroups,
            operationData: operationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        bytes memory malformedCallData = abi.encodeWithSelector(harness.modifyGroups.selector, rawModifications, auth);

        vm.prank(GUARDIAN);
        (bool success,) = address(harness).call(malformedCallData);
        assertFalse(success, "malformed enum payload should revert");

        uint256 nonce = _computeModifyGroupsNonce(operationData, salt);
        assertFalse(groupsStateHarness.getUsedNonce(nonce), "malformed-enum revert should not consume nonce");
        assertFalse(harness.isGroup(groupId), "state should remain unchanged on malformed enum revert");
    }

    /// @dev Verifies valid auth + library revert does not consume nonce and same salt/operation can be retried.
    function test_modifyGroups_libraryRevert_doesNotConsumeNonceAndCanRetrySameSaltAndOperation() public {
        uint256 groupId = 7910;

        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory modifications =
            _buildModificationsArray(_updateModification(groupId, buildArray(admin1), buildEmptyAddressArray()));

        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: 3110,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // First attempt reverts in library because group does not exist.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, groupId));
        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, auth);

        uint256 nonce = _computeModifyGroupsNonce(operationData, 3110);
        assertFalse(groupsStateHarness.getUsedNonce(nonce), "nonce should rollback on library revert");

        // Make payload valid without changing signed operation data.
        groupsStateHarness.setGroupStatus(groupId, true);

        vm.prank(GUARDIAN);
        harness.modifyGroups(modifications, auth);

        assertTrue(groupsStateHarness.getUsedNonce(nonce), "nonce should consume on successful retry");
        assertTrue(harness.isGroupMember(groupId, admin1), "retry should apply signed update successfully");
    }
}
