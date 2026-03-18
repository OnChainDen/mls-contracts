// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BatchedTransaction} from "../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";
import {ISafeExecutorModule} from "interfaces/ISafeExecutorModule.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationGroupsTestBase} from "test/organization/shared/OrganizationGroupsTestBase.sol";
import {OrganizationImplementationHarness} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {GroupModification, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Safe mock that enforces module enablement and executes real call/delegatecall paths.
 */
contract OrganizationBatchE2EMockSafe {
    mapping(address module => bool enabled) public enabledModules;
    bool public executeDelegatecalls = true;

    /**
     * @dev Updates module enablement used by `execTransactionFromModule`.
     * @param module Module address whose enablement is being changed.
     * @param enabled Whether `module` should be authorized.
     */
    function setModuleEnabled(address module, bool enabled) external {
        enabledModules[module] = enabled;
    }

    /**
     * @dev Executes the module transaction after checking that the caller is enabled.
     * @param to Target address forwarded by the module.
     * @param value ETH value forwarded by the module.
     * @param data Calldata forwarded by the module.
     * @param operation Safe module operation type.
     * @return success Whether the forwarded execution succeeded.
     */
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success)
    {
        require(enabledModules[msg.sender], "GS104");

        if (operation == 0) {
            (success,) = to.call{value: value}(data);
        } else if (executeDelegatecalls) {
            (success,) = to.delegatecall(data);
        } else {
            success = true;
        }
    }

    /**
     * @dev Exposes Safe-compatible module enablement checks for guardian-signature flows.
     * @param module Module address to query.
     * @return enabled Whether `module` is enabled.
     */
    function isModuleEnabled(address module) external view returns (bool enabled) {
        enabled = enabledModules[module];
    }
}

/**
 * @dev End-to-end organization batch tests for `SafeExecutorModule -> BatchedTransaction`.
 */
contract SafeModuleOrganizationBatchE2ETest is OrganizationGroupsTestBase {
    uint256 internal constant AUTHORIZED_EXECUTOR_PK = 0xA11CE;
    uint256 internal constant GROUP_ID = 77;

    OrganizationImplementationHarness internal organization;
    OrganizationBatchE2EMockSafe internal safe;
    BatchedTransaction internal batchedTransaction;
    SafeExecutorModule internal module;

    address internal authorizedExecutor;
    address internal unauthorizedCaller;
    address internal memberToAddA;
    address internal memberToAddB;
    address internal memberToAddC;

    /**
     * @dev Deploys the organization harness used for the real member/group mutation calls.
     * @return deployedHarness Shared admin-state harness surface for the inherited helpers.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness deployedHarness) {
        organization = new OrganizationImplementationHarness();
        deployedHarness = OrganizationAdminStateHarness(address(organization));
    }

    /**
     * @dev Configures the Safe/module fixture and seeds a one-admin organization.
     */
    function setUp() public override {
        super.setUp();

        authorizedExecutor = vm.addr(AUTHORIZED_EXECUTOR_PK);
        unauthorizedCaller = makeAddr("unauthorizedSafeModuleCaller");
        memberToAddA = makeAddr("memberToAddA");
        memberToAddB = makeAddr("memberToAddB");
        memberToAddC = makeAddr("memberToAddC");

        safe = new OrganizationBatchE2EMockSafe();
        batchedTransaction = new BatchedTransaction();
        module = new SafeExecutorModule(address(safe), authorizedExecutor, address(batchedTransaction));

        safe.setModuleEnabled(address(module), true);
        organization.setGuardianStorage(address(safe));
        _setMembersAndAdmins(buildArray(admin1), buildArray(admin1), 1);
    }

    /// @dev Verifies the authorized executor can call a guardian-only organization function through the module.
    function test_authorizedExecutorCanExecuteGuardianOnlyOrganizationFunctionViaModule() public {
        // Setup: build a signed `modifyMembers` call that adds one new member.
        bytes memory modifyMembersCall = _buildModifyMembersCall(buildArray(memberToAddA), 101);

        // Call: execute the guardian-only organization function through the Safe module path.
        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(organization), modifyMembersCall);

        // Verify: the call succeeds and the new member is persisted.
        assertTrue(success, "authorized executor should execute guardian-only function");
        assertTrue(organization.getMemberStatus(memberToAddA), "member should be added by the organization call");
    }

    /// @dev Verifies non-authorized callers cannot execute guardian-only organization functions through the module.
    function test_unauthorizedCallerCannotExecuteGuardianOnlyOrganizationFunctionViaModule() public {
        // Setup: build a signed `modifyMembers` call that would add one new member.
        bytes memory modifyMembersCall = _buildModifyMembersCall(buildArray(memberToAddA), 102);

        // Call: execute through the module from an unauthorized caller and expect the auth revert.
        vm.prank(unauthorizedCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISafeExecutorModule.UnauthorizedCaller.selector, unauthorizedCaller, authorizedExecutor
            )
        );
        module.executeOnBehalf(address(organization), modifyMembersCall);

        // Verify: no organization state changes are applied.
        assertFalse(organization.getMemberStatus(memberToAddA), "member state should remain unchanged");
    }

    /// @dev Verifies a batched `modifyMembers` then `modifyGroups` flow succeeds with consistent final state.
    function test_batchedModifyMembersThenGroups_succeedsWithConsistentState() public {
        // Setup: encode member additions first, then a group creation that uses those newly added members.
        bytes memory modifyMembersCall = _buildModifyMembersCall(buildArray(memberToAddA, memberToAddB), 201);
        bytes memory modifyGroupsCall = _buildCreateGroupCall(GROUP_ID, buildArray(memberToAddA, memberToAddB), 202);
        bytes memory batchData = abi.encodeWithSelector(
            BatchedTransaction.execute.selector, _encodeBatch(modifyMembersCall, modifyGroupsCall)
        );

        // Call: execute the ordered admin batch through SafeExecutorModule -> BatchedTransaction.
        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(batchedTransaction), batchData);

        // Verify: both members are added, the group exists, and both members are immediately usable by that group.
        assertTrue(success, "ordered member/group batch should succeed");
        assertTrue(organization.getMemberStatus(memberToAddA), "first member should be added");
        assertTrue(organization.getMemberStatus(memberToAddB), "second member should be added");
        assertTrue(organization.getGroupStatus(GROUP_ID), "group should be created");
        assertTrue(organization.getGroupMemberStatus(GROUP_ID, memberToAddA), "first member should belong to group");
        assertTrue(organization.getGroupMemberStatus(GROUP_ID, memberToAddB), "second member should belong to group");
    }

    /// @dev Verifies reversing the member/group order partially reverts the group sub-call while the member sub-call
    ///      succeeds, because admin operations with post-validation execution failures no longer revert the outer call.
    function test_batchedModifyGroupsBeforeMembers_partiallyRevertsGroupCreation() public {
        // Setup: encode the same logical work in the unsafe order, creating the group before members exist.
        bytes memory modifyGroupsCall = _buildCreateGroupCall(GROUP_ID, buildArray(memberToAddA, memberToAddB), 301);
        bytes memory modifyMembersCall = _buildModifyMembersCall(buildArray(memberToAddA, memberToAddB), 302);
        bytes memory batchData = abi.encodeWithSelector(
            BatchedTransaction.execute.selector, _encodeBatch(modifyGroupsCall, modifyMembersCall)
        );

        // Call: execute the malformed ordering. The modifyGroups sub-call partially reverts (group creation fails
        // because members don't exist yet), while the modifyMembers sub-call succeeds.
        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(batchedTransaction), batchData);

        // Verify: batch succeeds overall. Members are added (from modifyMembers), but the group is not created
        // (from modifyGroups partial revert).
        assertTrue(success, "batch should succeed with partial revert on group sub-call");
        assertTrue(organization.getMemberStatus(memberToAddA), "first member should be added by modifyMembers");
        assertTrue(organization.getMemberStatus(memberToAddB), "second member should be added by modifyMembers");
        assertFalse(organization.getGroupStatus(GROUP_ID), "group should not be created due to partial revert");
        assertFalse(organization.getGroupMemberStatus(GROUP_ID, memberToAddA), "group membership should not exist");
        assertFalse(organization.getGroupMemberStatus(GROUP_ID, memberToAddB), "group membership should not exist");
    }

    /// @dev Verifies replaying a batch with a consumed first sub-call nonce fails without additional state changes.
    function test_replayingBatchWithConsumedFirstNonce_revertsWithoutStateChange() public {
        // Setup: execute a successful member/group batch once to consume both nonces.
        bytes memory modifyMembersCall = _buildModifyMembersCall(buildArray(memberToAddA, memberToAddB), 401);
        bytes memory modifyGroupsCall = _buildCreateGroupCall(GROUP_ID, buildArray(memberToAddA, memberToAddB), 402);
        bytes memory batchData = abi.encodeWithSelector(
            BatchedTransaction.execute.selector, _encodeBatch(modifyMembersCall, modifyGroupsCall)
        );

        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(batchedTransaction), batchData);

        // Call: replay the exact same batch after the first execution consumed both nonces.
        vm.prank(authorizedExecutor);
        vm.expectRevert(ISafeExecutorModule.ExecutionFailed.selector);
        module.executeOnBehalf(address(batchedTransaction), batchData);

        // Verify: the already-applied state remains stable and no duplicate or partial effects are introduced.
        assertTrue(organization.getMemberStatus(memberToAddA), "first member should remain added once");
        assertTrue(organization.getMemberStatus(memberToAddB), "second member should remain added once");
        assertTrue(organization.getGroupStatus(GROUP_ID), "group should remain created once");
        assertTrue(organization.getGroupMemberStatus(GROUP_ID, memberToAddA), "first group membership should persist");
        assertTrue(organization.getGroupMemberStatus(GROUP_ID, memberToAddB), "second group membership should persist");
    }

    /// @dev Verifies a consumed second sub-call nonce rolls back a fresh first sub-call in the same batch.
    function test_consumedSecondNonce_rollsBackFreshFirstSubcall() public {
        // Setup: execute an initial successful batch whose group-call nonce will be replayed later.
        bytes memory initialModifyMembersCall = _buildModifyMembersCall(buildArray(memberToAddA, memberToAddB), 501);
        bytes memory staleModifyGroupsCall =
            _buildCreateGroupCall(GROUP_ID, buildArray(memberToAddA, memberToAddB), 502);
        bytes memory initialBatchData = abi.encodeWithSelector(
            BatchedTransaction.execute.selector, _encodeBatch(initialModifyMembersCall, staleModifyGroupsCall)
        );

        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(batchedTransaction), initialBatchData);

        bytes memory freshModifyMembersCall = _buildModifyMembersCall(buildArray(memberToAddC), 503);
        bytes memory replayBatchData = abi.encodeWithSelector(
            BatchedTransaction.execute.selector, _encodeBatch(freshModifyMembersCall, staleModifyGroupsCall)
        );

        // Call: execute a new batch whose second sub-call reuses the consumed group nonce from the initial batch.
        vm.prank(authorizedExecutor);
        vm.expectRevert(ISafeExecutorModule.ExecutionFailed.selector);
        module.executeOnBehalf(address(batchedTransaction), replayBatchData);

        // Verify: the fresh member addition is rolled back when the stale second sub-call fails.
        assertTrue(organization.getMemberStatus(memberToAddA), "existing first member should remain added");
        assertTrue(organization.getMemberStatus(memberToAddB), "existing second member should remain added");
        assertFalse(organization.getMemberStatus(memberToAddC), "fresh first sub-call should be rolled back");
        assertFalse(
            organization.getGroupMemberStatus(GROUP_ID, memberToAddC), "replayed batch must not partially update group"
        );
    }

    /// @dev Verifies disabled-module and wrong-executor gating both block batched admin execution with no state change.
    function test_disabledModuleOrWrongExecutor_blockBatchAndPreserveOrganizationState() public {
        // Setup: build a valid member/group batch that would otherwise succeed.
        bytes memory modifyMembersCall = _buildModifyMembersCall(buildArray(memberToAddA, memberToAddB), 601);
        bytes memory modifyGroupsCall = _buildCreateGroupCall(GROUP_ID, buildArray(memberToAddA, memberToAddB), 602);
        bytes memory batchData = abi.encodeWithSelector(
            BatchedTransaction.execute.selector, _encodeBatch(modifyMembersCall, modifyGroupsCall)
        );

        safe.setModuleEnabled(address(module), false);

        // Call: execute with the module disabled on the Safe and expect Safe module auth to reject it.
        vm.prank(authorizedExecutor);
        vm.expectRevert("GS104");
        module.executeOnBehalf(address(batchedTransaction), batchData);

        safe.setModuleEnabled(address(module), true);

        // Call: execute with the wrong executor and expect module caller auth to reject it.
        vm.prank(unauthorizedCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISafeExecutorModule.UnauthorizedCaller.selector, unauthorizedCaller, authorizedExecutor
            )
        );
        module.executeOnBehalf(address(batchedTransaction), batchData);

        // Verify: neither gating failure mutates organization member or group state.
        assertFalse(organization.getMemberStatus(memberToAddA), "first member should remain absent");
        assertFalse(organization.getMemberStatus(memberToAddB), "second member should remain absent");
        assertFalse(organization.getGroupStatus(GROUP_ID), "group should remain absent");
    }

    /// @dev Verifies that batching two identical admin operations in a single batch reverts atomically because the
    ///      second sub-call encounters a nonce already consumed by the first sub-call.
    function test_duplicateAdminOperationsInSameBatch_revertsNonceAlreadyUsed() public {
        // Setup: build the same modifyMembers call twice so both sub-calls derive the same nonce.
        bytes memory modifyMembersCall = _buildModifyMembersCall(buildArray(memberToAddA, memberToAddB), 701);
        bytes memory batchData = abi.encodeWithSelector(
            BatchedTransaction.execute.selector, _encodeBatch(modifyMembersCall, modifyMembersCall)
        );

        // Call: execute a batch where both sub-calls share the same nonce; the second triggers NonceAlreadyUsed.
        vm.prank(authorizedExecutor);
        vm.expectRevert(ISafeExecutorModule.ExecutionFailed.selector);
        module.executeOnBehalf(address(batchedTransaction), batchData);

        // Verify: the batch rolls back atomically—no member state from either sub-call persists.
        assertFalse(organization.getMemberStatus(memberToAddA), "first member should not be added");
        assertFalse(organization.getMemberStatus(memberToAddB), "second member should not be added");
    }

    /**
     * @dev Builds the direct-call calldata for `OrganizationImplementation.modifyMembers`.
     * @param membersToAdd Members added by the call.
     * @param salt Salt used for admin-auth nonce derivation.
     * @return callData ABI-encoded calldata for the organization contract.
     */
    function _buildModifyMembersCall(address[] memory membersToAdd, uint256 salt)
        internal
        view
        returns (bytes memory callData)
    {
        (AdminAuthParams memory auth,) = _buildModifyMembersAuth(membersToAdd, buildEmptyAddressArray(), salt);
        callData =
            abi.encodeWithSelector(organization.modifyMembers.selector, membersToAdd, buildEmptyAddressArray(), auth);
    }

    /**
     * @dev Builds the direct-call calldata for `OrganizationImplementation.modifyGroups`.
     * @param groupId Group id created by the call.
     * @param groupMembers Members seeded into the new group.
     * @param salt Salt used for admin-auth nonce derivation.
     * @return callData ABI-encoded calldata for the organization contract.
     */
    function _buildCreateGroupCall(uint256 groupId, address[] memory groupMembers, uint256 salt)
        internal
        view
        returns (bytes memory callData)
    {
        GroupModification[] memory modifications = _buildModificationsArray(_createModification(groupId, groupMembers));
        (AdminAuthParams memory auth,) = _buildModifyGroupsAuth({
            modifications: modifications,
            salt: salt,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        callData = abi.encodeWithSelector(organization.modifyGroups.selector, modifications, auth);
    }

    /**
     * @dev Builds the signed admin-auth payload for `modifyMembers`.
     * @param membersToAdd Members added by the operation.
     * @param membersToRemove Members removed by the operation.
     * @param salt Salt used for admin-auth nonce derivation.
     * @return auth Signed admin-auth payload for the organization call.
     * @return operationData Encoded operation data bound into the signatures.
     */
    function _buildModifyMembersAuth(address[] memory membersToAdd, address[] memory membersToRemove, uint256 salt)
        internal
        view
        returns (AdminAuthParams memory auth, bytes memory operationData)
    {
        operationData = _encodeOperationDataForModifyMembers(membersToAdd, membersToRemove);
        auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyMembers,
            operationData: operationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
    }

    /**
     * @dev Encodes a single batched sub-transaction.
     * @param to Target address for the sub-transaction.
     * @param data Calldata executed against `to`.
     * @return encoded Packed sub-transaction bytes.
     */
    function _encodeTx(address to, bytes memory data) internal pure returns (bytes memory encoded) {
        encoded = abi.encodePacked(to, uint64(data.length), data);
    }

    /**
     * @dev Encodes a two-call batch for `BatchedTransaction.execute`.
     * @param firstCall First sub-transaction calldata.
     * @param secondCall Second sub-transaction calldata.
     * @return batch Concatenated packed batch bytes.
     */
    function _encodeBatch(bytes memory firstCall, bytes memory secondCall) internal view returns (bytes memory batch) {
        batch =
            abi.encodePacked(_encodeTx(address(organization), firstCall), _encodeTx(address(organization), secondCall));
    }
}
