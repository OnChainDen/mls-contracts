// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MerkleUtils} from "libraries/MerkleUtils.sol";
import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {
    LibOrganizationAccountSignatureSuiteBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureSuiteBase.sol";
import {ApproverType, Policy, PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";
import {PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Shared setup/builders for `LibOrganizationAccountSignature` test suites.
 */
abstract contract LibOrganizationAccountSignatureTestBase is LibOrganizationAccountSignatureSuiteBase {
    uint256 internal constant DEFAULT_POLICY_ID = 177;
    uint256 internal constant DEFAULT_GROUP_ID = 9151;

    address internal constant ACCOUNT = address(0xAA7701);
    address internal constant OTHER_ACCOUNT = address(0xAA7702);

    bytes32 internal constant MESSAGE_HASH = keccak256("policy-signature-message");
    bytes32 internal constant OTHER_MESSAGE_HASH = keccak256("policy-signature-message-2");

    /**
     * @dev Seeds default organization members used by signature policy tests.
     */
    function setUp() public virtual override {
        super.setUp();
        _seedDefaultMembers();
    }

    /**
     * @dev Marks deterministic initiators/reviewers as members.
     */
    function _seedDefaultMembers() internal {
        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(initiator2, true);
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setMemberStatus(reviewer2, true);
        policyStateHarness.setMemberStatus(reviewer3, true);
    }

    /**
     * @dev Builds a deterministic signature policy with configurable approval mode.
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
     * @dev Builds an empty proofs payload for a provided policy.
     */
    function _emptyProofsForPolicy(Policy memory policy) internal pure returns (ValidationProofs memory proofs) {
        bytes32[] memory empty = new bytes32[](0);
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
     * @dev Sets a single-policy root and returns the matching empty-proof payload.
     */
    function _setSinglePolicyRootAndBuildProofs(uint256 policyId, Policy memory policy)
        internal
        returns (ValidationProofs memory proofs)
    {
        policyStateHarness.setPoliciesRoot(_computePolicyLeaf(policyId, policy));
        proofs = _emptyProofsForPolicy(policy);
    }

    /**
     * @dev ABI-encodes policy-signature payload data (without type prefix).
     */
    function _buildPolicySignatureData(
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory initiatorSignature,
        bytes memory reviewSignatures,
        bytes memory guardianSignature,
        ValidationProofs memory proofs
    ) internal pure returns (bytes memory) {
        return abi.encode(
            policyId, expirationTimestamp, initiatorSignature, reviewSignatures, guardianSignature, proofs
        );
    }

    /**
     * @dev Builds a type-prefixed policy signature payload (`0x01`).
     */
    function _buildPolicySignature(
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory initiatorSignature,
        bytes memory reviewSignatures,
        bytes memory guardianSignature,
        ValidationProofs memory proofs
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(0x01),
            _buildPolicySignatureData(
                policyId, expirationTimestamp, initiatorSignature, reviewSignatures, guardianSignature, proofs
            )
        );
    }

    /**
     * @dev Builds a type-prefixed recovery signature payload (`0x00`).
     *      ABI-encodes the expiration timestamp alongside the inner recovery signature.
     */
    function _buildRecoverySignature(uint256 expirationTimestamp, bytes memory recoverySignature)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(0x00), abi.encode(expirationTimestamp, recoverySignature));
    }

    /**
     * @dev Signs the EIP-712 recovery hash for a given account, message hash, and expiration.
     */
    function _signRecoverySignature(uint256 privateKey, address account, bytes32 hash, uint256 expirationTimestamp)
        internal
        view
        returns (bytes memory)
    {
        bytes32 recoveryHash = harness.getRecoverySignatureHashViaLibrary(account, hash, expirationTimestamp);
        return _signHash(privateKey, recoveryHash);
    }

    /**
     * @dev Signs the EIP-712 recovery hash using the specified harness.
     */
    function _signRecoverySignatureWithHarness(
        LibOrganizationAccountSignatureHarness sigHarness,
        uint256 privateKey,
        address account,
        bytes32 hash,
        uint256 expirationTimestamp
    ) internal view returns (bytes memory) {
        bytes32 recoveryHash = sigHarness.getRecoverySignatureHashViaLibrary(account, hash, expirationTimestamp);
        return _signHash(privateKey, recoveryHash);
    }

    /**
     * @dev Signs the initiator hash using the provided harness + signer key.
     */
    function _signInitiatorSignature(
        LibOrganizationAccountSignatureHarness sigHarness,
        uint256 privateKey,
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp
    ) internal view returns (bytes memory) {
        bytes32 initiatorHash = sigHarness.getInitiatorSignatureHashViaLibrary(
            account, hash, policyId, expirationTimestamp
        );
        return _signHash(privateKey, initiatorHash);
    }

    /**
     * @dev Signs the review hash using the provided harness + signer key.
     */
    function _signReviewSignature(
        LibOrganizationAccountSignatureHarness sigHarness,
        uint256 privateKey,
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory initiatorSignature
    ) internal view returns (bytes memory) {
        bytes32 reviewHash = sigHarness.getReviewSignatureHashViaLibrary(
            account, hash, policyId, expirationTimestamp, initiatorSignature
        );
        return _signHash(privateKey, reviewHash);
    }

    /**
     * @dev Signs guardian approval hash for policy-signature validation.
     */
    function _signGuardianReviewHash(
        LibOrganizationAccountSignatureHarness sigHarness,
        uint256 privateKey,
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory initiatorSignature
    ) internal view returns (bytes memory) {
        bytes32 reviewHash = sigHarness.getReviewSignatureHashViaLibrary(
            account, hash, policyId, expirationTimestamp, initiatorSignature
        );
        return _signHash(privateKey, reviewHash);
    }

    /**
     * @dev Configures tx/ERC-1271 recovery storage with a compact deterministic state.
     */
    function _setTxRecoveryState(address recoveryAddress, bool isEnabled) internal {
        policyStateHarness.setTxRecoveryState(
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
     * @dev Builds a valid policy signature for the default account/hash fixture.
     */
    function _buildValidPolicySignature(PolicyType approvalType, uint256 policyId, uint256 expirationTimestamp)
        internal
        returns (
            bytes memory signature,
            ValidationProofs memory proofs,
            bytes memory initiatorSignature,
            bytes memory reviewSignatures,
            bytes memory guardianSignature,
            Policy memory policy
        )
    {
        policyStateHarness.setGuardian(guardianSigner);

        policy = _buildSignaturePolicy(approvalType);
        proofs = _setSinglePolicyRootAndBuildProofs(policyId, policy);

        initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: policyId,
            expirationTimestamp: expirationTimestamp
        });

        if (approvalType == PolicyType.RequireManualApproval) {
            reviewSignatures = _signReviewSignature({
                sigHarness: harness,
                privateKey: REVIEWER_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: initiatorSignature
            });
        }

        guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: policyId,
            expirationTimestamp: expirationTimestamp,
            initiatorSignature: initiatorSignature
        });

        signature = _buildPolicySignature({
            policyId: policyId,
            expirationTimestamp: expirationTimestamp,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignatures,
            guardianSignature: guardianSignature,
            proofs: proofs
        });
    }

    /**
     * @dev Unsafely sets `Policy.config.approval.policyType` in a memory struct.
     */
    function _unsafeSetApprovalPolicyTypeRaw(Policy memory policy, uint256 rawValue) internal pure {
        assembly {
            mstore(add(policy, 0x80), rawValue)
        }
    }

    /**
     * @dev Mutates encoded policy-signature payload to set raw policy-type enum value.
     */
    function _setPolicyTypeInPolicySignature(bytes memory signature, uint256 rawValue) internal pure {
        uint256 proofsOffset = _readWord(signature, 1 + 5 * 32);
        _setWord(signature, 1 + proofsOffset + 4 * 32, rawValue);
    }

    /**
     * @dev Seeds deterministic initiator/reviewer members into another harness.
     */
    function _seedMembers(address target) internal {
        LibOrganizationAccountSignatureHarness targetHarness = LibOrganizationAccountSignatureHarness(target);
        targetHarness.setMemberStatus(initiator1, true);
        targetHarness.setMemberStatus(initiator2, true);
        targetHarness.setMemberStatus(reviewer1, true);
        targetHarness.setMemberStatus(reviewer2, true);
        targetHarness.setMemberStatus(reviewer3, true);
    }

    /**
     * @dev Builds a source-account-constrained proof fixture that allows one specific account.
     */
    function _buildSpecificSourceProofs(Policy memory policy, address allowedAccount)
        internal
        returns (ValidationProofs memory proofs)
    {
        policy.config.anySourceAccount = false;
        policy.roots.sourceAccountsRoot = MerkleUtils.computeAddressLeaf(allowedAccount);
        proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
    }
}
