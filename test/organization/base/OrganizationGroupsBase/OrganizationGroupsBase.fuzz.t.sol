// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationGroupsBaseSuiteBase
} from "test/organization/base/OrganizationGroupsBase/OrganizationGroupsBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {GroupModification, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for `OrganizationGroupsBase`.
 */
contract OrganizationGroupsBaseFuzzTest is OrganizationGroupsBaseSuiteBase {
    /**
     * @dev Verifies `OrganizationGroupsBase.modifyGroups` remains guardian-only.
     * @param rawGroupId Raw group id used to derive a bounded group identifier
     * @param saltRaw Raw salt used to derive a bounded nonce salt
     */
    function testFuzz_FOGB_GROUP_54_modifyGroupsIsGuardianOnly(uint256 rawGroupId, uint256 saltRaw) public {
        uint256 groupId = bound(rawGroupId, 1, 50_000);

        // Setup: configure one valid admin/member signer and build one signed create-group batch.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory modifications =
            _buildModificationsArray(_createModification(groupId, buildArray(admin1)));
        uint256 salt = bound(saltRaw, 1, type(uint256).max);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: salt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeModifyGroupsNonce(operationData, salt);

        // Call: invoke `modifyGroups` from a non-guardian caller.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.modifyGroups(modifications, auth);

        // Verify: the caller gate should reject the batch before nonce or group state changes.
        assertFalse(groupsStateHarness.getUsedNonce(nonce), "guardian gate should leave nonce unused");
        assertFalse(harness.isGroup(groupId), "guardian gate should block group creation");
    }

    /**
     * @dev Verifies `OrganizationGroupsBase.modifyGroups` binds signatures to the exact hashed modification batch.
     * @param rawGroupId Raw group id used to derive a bounded group identifier
     * @param saltRaw Raw salt used to derive a bounded nonce salt
     * @param mutationSelector Chooses which batch component to mutate after signing
     */
    function testFuzz_FOGB_GROUP_54_modifyGroupsBindsSignaturesToExactModificationBatch(
        uint256 rawGroupId,
        uint256 saltRaw,
        uint8 mutationSelector
    ) public {
        uint256 groupId = bound(rawGroupId, 1, 50_000);
        address secondMember = address(0x5402);

        // Setup: configure one valid admin signer and a two-member create batch whose ordering is part of the signed
        // payload hash.
        _setMembersAndAdmins({members: buildArray(admin1, secondMember), admins: buildArray(admin1), threshold: 1});

        GroupModification[] memory signedModifications =
            _buildModificationsArray(_createModification(groupId, buildArray(admin1, secondMember)));
        uint256 salt = bound(saltRaw, 1, type(uint256).max);
        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildModifyGroupsAuth({
            modifications: signedModifications,
            salt: salt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint8 mode = uint8(mutationSelector % 2);
        GroupModification[] memory mutatedModifications = mode == 0
            ? _buildModificationsArray(_createModification(groupId + 1, buildArray(admin1, secondMember)))
            : _buildModificationsArray(_createModification(groupId, buildArray(secondMember, admin1)));

        bytes memory mutatedOperationData = _encodeOperationDataForModifyGroups(mutatedModifications);
        uint256 signedNonce = _computeModifyGroupsNonce(signedOperationData, salt);
        uint256 mutatedNonce = _computeModifyGroupsNonce(mutatedOperationData, salt);

        // Call: replay the signed auth against an altered group batch.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.modifyGroups(mutatedModifications, auth);

        // Verify: altered group batches should not consume either nonce domain.
        assertFalse(groupsStateHarness.getUsedNonce(mutatedNonce), "altered group batch should not consume its nonce");
        assertFalse(groupsStateHarness.getUsedNonce(signedNonce), "failed replay should preserve the signed nonce");

        // Call: execute the exact signed modification batch.
        vm.prank(GUARDIAN);
        harness.modifyGroups(signedModifications, auth);

        // Verify: only the exact signed batch should authorize group creation.
        assertTrue(groupsStateHarness.getUsedNonce(signedNonce), "exact group batch should consume the signed nonce");
        assertTrue(harness.isGroup(groupId), "exact group batch should create the signed group");
        assertTrue(harness.isGroupMember(groupId, admin1), "exact group batch should add the first member");
        assertTrue(harness.isGroupMember(groupId, secondMember), "exact group batch should add the second member");
    }
}
