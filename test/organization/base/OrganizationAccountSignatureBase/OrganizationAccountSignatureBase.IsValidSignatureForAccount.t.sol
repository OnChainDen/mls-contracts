// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountSignature} from "interfaces/organization/IOrganizationAccountSignature.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {
    OrganizationAccountSignatureBaseSuiteBase
} from "test/organization/base/OrganizationAccountSignatureBase/OrganizationAccountSignatureBaseSuiteBase.sol";
import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";
import {ApproverType, Policy, PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";
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

        harness.setMemberStatus(initiator1, true);
        harness.setMemberStatus(reviewer1, true);
        libHarness = new LibOrganizationAccountSignatureHarness();
        libHarness.setMemberStatus(initiator1, true);
        libHarness.setMemberStatus(reviewer1, true);
    }

    /// @dev Verifies that calls where `msg.sender != account` revert with `SenderIsNotAccount`.
    function test_isValidSignatureForAccount_senderNotAccount_revertsSenderIsNotAccount() public {
        // Setup: mark the account as deployed to isolate the sender gate.
        harness.setDeployedAccount(ACCOUNT, true);

        // Verify: expect sender/account mismatch to revert with the sender-gate error.
        vm.expectRevert(IOrganizationAccountSignature.SenderIsNotAccount.selector);
        vm.prank(OTHER_CALLER);
        // Call: execute `isValidSignatureForAccount` through the base-contract entry point.
        harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, bytes(""));
    }

    /// @dev Verifies that undeployed accounts revert even when `msg.sender == account`.
    function test_isValidSignatureForAccount_accountNotDeployed_revertsAccountNotDeployedByOrganization() public {
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
    function test_isValidSignatureForAccount_anySourceAccountPolicyStillRequiresOrgDeployedAccount() public {
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
    function test_isValidSignatureForAccount_deployedAccountDelegatesToLibraryResult() public {
        // Setup: align storage fixtures for both harnesses and build valid recovery payloads.
        // Each harness has a different address (different EIP-712 domain), so each needs its own signature.
        harness.setDeployedAccount(ACCOUNT, true);
        _setRecoveryState(harness, guardianSigner, true);
        _setRecoveryState(libHarness, guardianSigner, true);

        uint256 expiration = block.timestamp + 1 days;
        bytes32 baseRecoveryHash = harness.getRecoverySignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, expiration);
        // forgefmt: disable-next-item
        bytes memory baseRecoverySignature = abi.encodePacked(
            uint8(0x00), abi.encode(expiration, _signHash(GUARDIAN_PK, baseRecoveryHash))
        );

        bytes32 libRecoveryHash = libHarness.getRecoverySignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, expiration);
        // forgefmt: disable-next-item
        bytes memory libRecoverySignature = abi.encodePacked(
            uint8(0x00), abi.encode(expiration, _signHash(GUARDIAN_PK, libRecoveryHash))
        );

        // Call: execute base entry-point and direct-library wrapper with domain-matched payloads.
        vm.prank(ACCOUNT);
        bytes4 viaBase = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, baseRecoverySignature);
        bytes4 viaLibrary = libHarness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, libRecoverySignature);

        // Verify: both paths should return the same magic value when given valid recovery signatures.
        assertEq(viaBase, viaLibrary, "base entrypoint should delegate to library result");
    }

    /// @dev Verifies that the base entry point returns the ERC-1271 magic value when validation succeeds.
    function test_isValidSignatureForAccount_libraryMagicResult_returnsMagicValue() public {
        // Setup: configure deployed-account + enabled recovery signer and build a valid recovery payload.
        harness.setDeployedAccount(ACCOUNT, true);
        _setRecoveryState(harness, guardianSigner, true);
        uint256 expiration = block.timestamp + 1 days;
        bytes32 recoveryHash = harness.getRecoverySignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, expiration);
        // forgefmt: disable-next-item
        bytes memory recoverySignature = abi.encodePacked(
            uint8(0x00), abi.encode(expiration, _signHash(GUARDIAN_PK, recoveryHash))
        );

        // Call: execute `isValidSignatureForAccount` through the base-contract entry point.
        vm.prank(ACCOUNT);
        bytes4 actual = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, recoverySignature);

        // Verify: successful delegated validation should return ERC-1271 magic value.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid delegated signature should return magic");
    }

    /// @dev Verifies `isValidSignatureForAccount` accepts valid ERC-1271 recovery encodings through the base entry
    /// point.
    function test_isValidSignatureForAccount_validERC1271RecoveryEncoding_returnsMagicValue() public {
        // Setup: mark the account as deployed and configure a contract-based recovery signer.
        harness.setDeployedAccount(ACCOUNT, true);
        MockERC1271ValidSigner contractRecovery = new MockERC1271ValidSigner();
        _setRecoveryState(harness, address(contractRecovery), true);

        bytes memory contractSignature =
            abi.encodePacked(uint8(0x00), uint8(0), address(contractRecovery), uint16(2), hex"CAFE");

        // Call: validate the contract-signature recovery payload through the base entry point.
        vm.prank(ACCOUNT);
        bytes4 actual = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, contractSignature);

        // Verify: valid ERC-1271 recovery encodings return the standard magic value.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid ERC-1271 recovery encoding should be accepted");
    }

    /// @dev Verifies that the base entry point returns the ERC-1271 invalid value when validation fails.
    function test_isValidSignatureForAccount_libraryInvalidResult_returnsInvalidValue() public {
        // Setup: mark account as deployed and pass a payload that the library rejects.
        harness.setDeployedAccount(ACCOUNT, true);

        // Call: execute `isValidSignatureForAccount` through the base-contract entry point.
        vm.prank(ACCOUNT);
        bytes4 actual = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, bytes(""));

        // Verify: failed delegated validation should return ERC-1271 invalid value.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "invalid delegated signature should return invalid");
    }

    /// @dev Verifies `isValidSignatureForAccount` rejects malformed EOA recovery encodings and high-`s` signatures.
    function test_isValidSignatureForAccount_malformedOrHighSRecoveryEOA_returnsInvalidValue() public {
        // Setup: configure a deployed account with enabled EOA recovery.
        harness.setDeployedAccount(ACCOUNT, true);
        _setRecoveryState(harness, guardianSigner, true);

        uint256 expiration = block.timestamp + 1 days;
        bytes32 recoveryHash = harness.getRecoverySignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, expiration);
        // forgefmt: disable-next-item
        bytes memory validSignature = abi.encodePacked(
            uint8(0x00), abi.encode(expiration, _signHash(GUARDIAN_PK, recoveryHash))
        );
        bytes memory malformedSignature = hex"001b";
        // forgefmt: disable-next-item
        bytes memory highSSignature = abi.encodePacked(
            uint8(0x00), abi.encode(expiration, _makeHighSSignature(GUARDIAN_PK, recoveryHash))
        );

        // Call: validate malformed and malleable recovery signatures through the base entry point.
        vm.startPrank(ACCOUNT);
        bytes4 malformedResult = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, malformedSignature);
        bytes4 highSResult = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, highSSignature);
        bytes4 validResult = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, validSignature);
        vm.stopPrank();

        // Verify: malformed/high-`s` EOAs fail closed while the canonical signature remains valid.
        assertEq(validResult, SignatureUtils.ERC1271_MAGIC_VALUE, "canonical recovery signature should stay valid");
        assertEq(
            malformedResult, SignatureUtils.ERC1271_INVALID_VALUE, "malformed recovery EOA bytes should fail closed"
        );
        assertEq(highSResult, SignatureUtils.ERC1271_INVALID_VALUE, "high-s recovery EOA signatures should fail closed");
    }

    /// @dev Verifies `isValidSignatureForAccount` rejects malformed ERC-1271 recovery headers and oversized declared
    ///  inner lengths.
    function test_isValidSignatureForAccount_malformedERC1271RecoveryEncoding_returnsInvalidValue() public {
        // Setup: configure a deployed account with a valid ERC-1271 recovery signer.
        harness.setDeployedAccount(ACCOUNT, true);
        MockERC1271ValidSigner contractRecovery = new MockERC1271ValidSigner();
        _setRecoveryState(harness, address(contractRecovery), true);

        bytes memory truncatedHeader = abi.encodePacked(uint8(0x00), bytes10(0x0102030405060708090A));
        bytes memory oversizedInnerLength = abi.encodePacked(uint8(0), address(contractRecovery), uint16(32), hex"CAFE");

        // Call: validate malformed ERC-1271 recovery encodings through the base entry point.
        vm.startPrank(ACCOUNT);
        bytes4 truncatedResult = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, truncatedHeader);
        bytes4 oversizedResult = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, oversizedInnerLength);
        vm.stopPrank();

        // Verify: malformed contract-signature encodings fail closed without mutating state.
        assertEq(truncatedResult, SignatureUtils.ERC1271_INVALID_VALUE, "truncated contract header should fail closed");
        assertEq(
            oversizedResult, SignatureUtils.ERC1271_INVALID_VALUE, "oversized inner-length encoding should fail closed"
        );
    }

    /// @dev Verifies that `isValidSignatureForAccount` is view-only and does not mutate organization state.
    function test_isValidSignatureForAccount_isView_noStateMutation() public {
        // Setup: configure deterministic state snapshots and a valid recovery signature payload.
        harness.setDeployedAccount(ACCOUNT, true);
        _setRecoveryState(harness, guardianSigner, true);
        harness.setPoliciesRoot(keccak256("base-view-root"));

        TxRecoveryState memory beforeRecovery = harness.getTxRecoveryState();
        bool beforeDeployed = harness.isDeployedAccount(ACCOUNT);
        bytes32 beforeRoot = harness.getPoliciesRoot();

        uint256 expiration = block.timestamp + 1 days;
        bytes32 recoveryHash = harness.getRecoverySignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, expiration);
        // forgefmt: disable-next-item
        bytes memory recoverySignature = abi.encodePacked(
            uint8(0x00), abi.encode(expiration, _signHash(GUARDIAN_PK, recoveryHash))
        );

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

    /// @dev Verifies a policy with a specific source-account Merkle subtree accepts the listed account and rejects a
    ///  different deployed account.
    function test_isValidSignatureForAccount_specificSourceAccountPolicyAcceptsOnlyListedAccount() public {
        // Setup: mark two deployed accounts, constrain the policy to `ACCOUNT`, and build a valid policy signature.
        address otherAccount = address(0xAA7703);
        harness.setDeployedAccount(ACCOUNT, true);
        harness.setDeployedAccount(otherAccount, true);
        harness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        policy.config.anySourceAccount = false;

        address[] memory allowedAccounts = new address[](1);
        allowedAccounts[0] = ACCOUNT;
        (policy.roots.sourceAccountsRoot,) = _buildAddressRootAndProof(allowedAccounts, 0);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        (, proofs.sourceAccountProof) = _buildAddressRootAndProof(allowedAccounts, 0);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory listedSignature =
            _buildPolicySignatureForAccount(ACCOUNT, INITIATOR_PK_1, DEFAULT_POLICY_ID, expiration, proofs);
        bytes memory unlistedSignature =
            _buildPolicySignatureForAccount(otherAccount, INITIATOR_PK_1, DEFAULT_POLICY_ID, expiration, proofs);

        // Call: validate the same specific-source policy from the listed and unlisted deployed accounts.
        vm.startPrank(ACCOUNT);
        bytes4 listedResult = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, listedSignature);
        vm.stopPrank();

        vm.startPrank(otherAccount);
        bytes4 unlistedResult = harness.isValidSignatureForAccount(otherAccount, MESSAGE_HASH, unlistedSignature);
        vm.stopPrank();

        // Verify: the listed account returns magic and the unlisted account returns invalid.
        assertEq(listedResult, SignatureUtils.ERC1271_MAGIC_VALUE, "listed source account should validate");
        assertEq(unlistedResult, SignatureUtils.ERC1271_INVALID_VALUE, "unlisted source account should fail closed");
    }

    /// @dev Verifies `anyInitiator=true` still rejects a non-member initiator on the external signature path.
    function test_isValidSignatureForAccount_anyInitiatorStillRejectsNonMemberInitiator() public {
        // Setup: deploy the account, configure guardian-backed policy validation, and leave the chosen initiator
        // outside organization membership.
        harness.setDeployedAccount(ACCOUNT, true);
        harness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        policy.config.initiator.anyInitiator = true;
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory nonMemberSignature =
            _buildPolicySignatureForAccount(ACCOUNT, uint256(0xC0DE01), DEFAULT_POLICY_ID, expiration, proofs);

        // Call: validate the non-member initiator payload through the external base entry point.
        vm.prank(ACCOUNT);
        bytes4 actual = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, nonMemberSignature);

        // Verify: `anyInitiator=true` still requires org membership and therefore returns invalid here.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "non-member initiator should fail closed");
    }

    /// @dev Verifies disabling tx/ERC-1271 recovery immediately invalidates recovery signatures on the external
    ///  account-signature path.
    function test_isValidSignatureForAccount_disabledRecoveryImmediatelyRejectsOldRecoverySignature() public {
        // Setup: deploy the account, enable EOA recovery, and confirm the current recovery signature is valid.
        harness.setDeployedAccount(ACCOUNT, true);
        _setRecoveryState(harness, guardianSigner, true);
        uint256 expiration = block.timestamp + 1 days;
        bytes32 recoveryHash = harness.getRecoverySignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, expiration);
        // forgefmt: disable-next-item
        bytes memory recoverySignature = abi.encodePacked(
            uint8(0x00), abi.encode(expiration, _signHash(GUARDIAN_PK, recoveryHash))
        );

        vm.prank(ACCOUNT);
        bytes4 enabledResult = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, recoverySignature);

        // Call: disable tx/ERC-1271 recovery and revalidate the same signature immediately.
        _setRecoveryState(harness, guardianSigner, false);
        vm.prank(ACCOUNT);
        bytes4 disabledResult = harness.isValidSignatureForAccount(ACCOUNT, MESSAGE_HASH, recoverySignature);

        // Verify: disabling recovery invalidates the previously-valid signature without any grace period.
        assertEq(enabledResult, SignatureUtils.ERC1271_MAGIC_VALUE, "enabled recovery should accept valid signatures");
        assertEq(disabledResult, SignatureUtils.ERC1271_INVALID_VALUE, "disabled recovery should reject immediately");
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
                }),
                initAttemptId: 0
            })
        );
    }

    /**
     * @dev Builds a signature-policy fixture matching the account-signature integration suites.
     * @param approvalType The approval mode for the policy.
     * @return policy The configured signature policy.
     */
    function _buildSignaturePolicy(PolicyType approvalType) internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.Signatures;
        policy.config.approval.policyType = approvalType;
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = reviewer1;
        policy.config.approval.approvalThreshold = 1;
    }

    /**
     * @dev Stores a single policy leaf in the harness and returns the matching proofs payload.
     * @param policyId The policy id.
     * @param policy The policy data.
     * @return proofs The initialized proofs payload.
     */
    function _setSinglePolicyRootAndBuildProofs(uint256 policyId, Policy memory policy)
        internal
        returns (ValidationProofs memory proofs)
    {
        bytes32[] memory empty = new bytes32[](0);
        harness.setPoliciesRoot(_computePolicyLeaf(policyId, policy));
        proofs = ValidationProofs({
            policy: policy,
            policyProof: empty,
            sourceAccountProof: empty,
            destinationProof: empty,
            functionProof: empty,
            constraints: bytes("")
        });
    }

    /**
     * @dev Builds one complete policy-signature payload for `isValidSignatureForAccount`.
     * @param account The account bound into the signature hashes.
     * @param initiatorPrivateKey The initiator private key.
     * @param policyId The policy id.
     * @param expirationTimestamp The expiration timestamp.
     * @param proofs The validation proofs payload.
     * @return signature The full type-prefixed policy signature bytes.
     */
    function _buildPolicySignatureForAccount(
        address account,
        uint256 initiatorPrivateKey,
        uint256 policyId,
        uint256 expirationTimestamp,
        ValidationProofs memory proofs
    ) internal view returns (bytes memory signature) {
        bytes32 initiatorHash = harness.getInitiatorSignatureHashViaLibrary(
            account, MESSAGE_HASH, policyId, expirationTimestamp
        );
        bytes memory initiatorSignature = _signHash(initiatorPrivateKey, initiatorHash);

        bytes32 reviewHash = harness.getReviewSignatureHashViaLibrary(
            account, MESSAGE_HASH, policyId, expirationTimestamp, initiatorSignature
        );
        bytes memory guardianSignature = _signHash(GUARDIAN_PK, reviewHash);

        bytes memory signatureData =
            abi.encode(policyId, expirationTimestamp, initiatorSignature, bytes(""), guardianSignature, proofs);
        signature = abi.encodePacked(uint8(0x01), signatureData);
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
