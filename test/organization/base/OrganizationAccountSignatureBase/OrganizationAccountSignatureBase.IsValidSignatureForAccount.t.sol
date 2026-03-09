// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountSignature} from "interfaces/organization/IOrganizationAccountSignature.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {
    OrganizationAccountSignatureBaseSuiteBase
} from "test/organization/base/OrganizationAccountSignatureBase/OrganizationAccountSignatureBaseSuiteBase.sol";
import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";
import {Policy, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";
import {PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for `OrganizationAccountSignatureBase.isValidSignatureForAccount` behavior.
 */
contract OrganizationAccountSignatureBaseIsValidSignatureForAccountTest is OrganizationAccountSignatureBaseSuiteBase {
    uint256 internal constant DEFAULT_POLICY_ID = 311;

    address internal constant ACCOUNT = address(0xAA7701);
    address internal constant OTHER_CALLER = address(0xAA7702);

    bytes32 internal constant MESSAGE_HASH = keccak256("base-signature-message");

    /// @dev Secondary harness used to compare delegated library outcomes.
    LibOrganizationAccountSignatureHarness internal libHarness;

    /**
     * @dev Deploys secondary library harness and seeds deterministic member fixtures.
     */
    function setUp() public override {
        super.setUp();

        libHarness = new LibOrganizationAccountSignatureHarness();
        libHarness.setMemberStatus(initiator1, true);
        libHarness.setMemberStatus(reviewer1, true);
    }

    /// @dev Verifies that calls where `msg.sender != account` revert with `SenderIsNotAccount`.
    function test_OASB_ISFA_1__OAS_VSFA_1_isValidSignatureForAccount_senderNotAccount_revertsSenderIsNotAccount()
        public
    {
        // Setup: mark the account as deployed to isolate the sender gate.
        harness.setDeployedAccount(ACCOUNT, true);

        // Verify: expect sender/account mismatch to revert with the sender-gate error.
        vm.expectRevert(IOrganizationAccountSignature.SenderIsNotAccount.selector);
        vm.prank(OTHER_CALLER);
        // Call: execute `isValidSignatureForAccount` through the base-contract entry point.
        harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, bytes(""));
    }

    /// @dev Verifies that undeployed accounts revert even when `msg.sender == account`.
    function test_OASB_ISFA_2__OAS_VSFA_1_isValidSignatureForAccount_accountNotDeployed_revertsAccountNotDeployedByOrganization()
        public
    {
        // Setup: leave deployed-account mapping unset for the target account.

        // Verify: expect undeployed-account validation to revert.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, ACCOUNT)
        );
        vm.prank(ACCOUNT);
        // Call: execute `isValidSignatureForAccount` through the base-contract entry point.
        harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, bytes(""));
    }

    /// @dev Verifies that policy `anySourceAccount=true` does not bypass org-account deployment gating.
    function test_OASB_ISFA_3_isValidSignatureForAccount_anySourceAccountPolicyStillRequiresOrgDeployedAccount()
        public
    {
        // Setup: build a policy payload with `anySourceAccount=true` but do not mark the account as deployed.
        bytes memory policySignature = _buildAnySourcePolicySignature();

        // Verify: expect undeployed-account validation to revert before any policy logic runs.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, ACCOUNT)
        );
        vm.prank(ACCOUNT);
        // Call: execute `isValidSignatureForAccount` through the base-contract entry point.
        harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, policySignature);
    }

    /// @dev Verifies that valid account callers receive the same result as direct library validation.
    function test_OASB_ISFA_4_isValidSignatureForAccount_deployedAccountDelegatesToLibraryResult() public {
        // Setup: align storage fixtures for both harnesses and build a valid recovery payload.
        harness.setDeployedAccount(ACCOUNT, true);
        _setRecoveryState(harness, guardianSigner, true);
        _setRecoveryState(libHarness, guardianSigner, true);

        bytes memory recoverySignature = abi.encodePacked(uint8(0x00), _signHash(GUARDIAN_PK, MESSAGE_HASH));

        // Call: execute base entry-point and direct-library wrapper with the same payload.
        vm.prank(ACCOUNT);
        bytes4 viaBase = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, recoverySignature);
        bytes4 viaLibrary = libHarness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, recoverySignature);

        // Verify: delegated result should match direct-library output exactly.
        assertEq(viaBase, viaLibrary, "base entrypoint should delegate to library result");
    }

    /// @dev Verifies that the base entry point returns the ERC-1271 magic value when validation succeeds.
    function test_OASB_ISFA_5_isValidSignatureForAccount_libraryMagicResult_returnsMagicValue() public {
        // Setup: configure deployed-account + enabled recovery signer and build a valid recovery payload.
        harness.setDeployedAccount(ACCOUNT, true);
        _setRecoveryState(harness, guardianSigner, true);
        bytes memory recoverySignature = abi.encodePacked(uint8(0x00), _signHash(GUARDIAN_PK, MESSAGE_HASH));

        // Call: execute `isValidSignatureForAccount` through the base-contract entry point.
        vm.prank(ACCOUNT);
        bytes4 actual = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, recoverySignature);

        // Verify: successful delegated validation should return ERC-1271 magic value.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid delegated signature should return magic");
    }

    /// @dev Verifies that the base entry point returns the ERC-1271 invalid value when validation fails.
    function test_OASB_ISFA_6_isValidSignatureForAccount_libraryInvalidResult_returnsInvalidValue() public {
        // Setup: mark account as deployed and pass a payload that the library rejects.
        harness.setDeployedAccount(ACCOUNT, true);

        // Call: execute `isValidSignatureForAccount` through the base-contract entry point.
        vm.prank(ACCOUNT);
        bytes4 actual = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, bytes(""));

        // Verify: failed delegated validation should return ERC-1271 invalid value.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "invalid delegated signature should return invalid");
    }

    /// @dev Verifies that `isValidSignatureForAccount` is view-only and does not mutate organization state.
    function test_OASB_ISFA_7__OAS_VSFA_8_isValidSignatureForAccount_isView_noStateMutation() public {
        // Setup: configure deterministic state snapshots and a valid recovery signature payload.
        harness.setDeployedAccount(ACCOUNT, true);
        _setRecoveryState(harness, guardianSigner, true);
        harness.setPoliciesRoot(keccak256("base-view-root"));

        TxRecoveryState memory beforeRecovery = harness.getTxRecoveryState();
        bool beforeDeployed = harness.isDeployedAccount(ACCOUNT);
        bytes32 beforeRoot = harness.getPoliciesRoot();

        bytes memory recoverySignature = abi.encodePacked(uint8(0x00), _signHash(GUARDIAN_PK, MESSAGE_HASH));

        // Call: execute `isValidSignatureForAccount` through the base-contract entry point.
        vm.prank(ACCOUNT);
        bytes4 actual = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, recoverySignature);

        // Verify: state snapshots remain unchanged across the view call.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "sanity: pre-state fixture should validate");
        assertEq(harness.isDeployedAccount(ACCOUNT), beforeDeployed, "deployed-account flag must not change");
        assertEq(harness.getPoliciesRoot(), beforeRoot, "policies root must not change");

        TxRecoveryState memory afterRecovery = harness.getTxRecoveryState();
        assertEq(afterRecovery.recoveryAddress, beforeRecovery.recoveryAddress, "recovery address must not change");
        assertEq(afterRecovery.isEnabled, beforeRecovery.isEnabled, "recovery enabled flag must not change");
        assertEq(
            afterRecovery.timelockDurationSeconds,
            beforeRecovery.timelockDurationSeconds,
            "recovery timelock must not change"
        );
        assertEq(
            afterRecovery.pendingEnableTimestamp,
            beforeRecovery.pendingEnableTimestamp,
            "pending enable timestamp must not change"
        );
    }

    /**
     * @dev Configures tx recovery state on a target harness.
     */
    function _setRecoveryState(OrganizationPolicyStateHarness target, address recoveryAddress, bool isEnabled)
        internal
    {
        target.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: isEnabled,
                timelockDurationSeconds: 1,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
    }

    /**
     * @dev Builds a type-prefixed policy payload with `anySourceAccount=true`.
     */
    function _buildAnySourcePolicySignature() internal view returns (bytes memory) {
        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.Signatures;
        policy.config.anySourceAccount = true;

        bytes32[] memory empty = new bytes32[](0);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: empty,
            sourceAccountProof: empty,
            destinationProof: empty,
            functionProof: empty,
            constraints: bytes("")
        });

        bytes memory signatureData =
            abi.encode(DEFAULT_POLICY_ID, block.timestamp + 1 days, bytes(""), bytes(""), bytes(""), proofs);

        return abi.encodePacked(uint8(0x01), signatureData);
    }
}
