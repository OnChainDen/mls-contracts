// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";
import {Policy, PolicyType} from "types/PolicyTypes.sol";

/**
 * @dev Invariant tests for `LibOrganizationAccountSignature` behavior.
 */
contract LibOrganizationAccountSignatureInvariants is LibOrganizationAccountSignatureTestBase {
    /// @dev Verifies that only recovery/policy type prefixes can produce ERC-1271 magic values.
    function invariant_typePrefixExclusivity_onlyRecoveryAndPolicyProduceMagic() public {
        // Setup: prepare valid recovery and valid policy payload fixtures.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory recoverySignature = _buildRecoverySignature(_signHash(GUARDIAN_PK, MESSAGE_HASH));

        (bytes memory policySignature,,,,,) =
            _buildValidPolicySignature(PolicyType.AutoApprove, DEFAULT_POLICY_ID, block.timestamp + 1 days);

        // Call: execute recovery and policy branches plus representative unknown-prefix branches.
        bytes4 recoveryResult = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, recoverySignature);
        bytes4 policyResult = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, policySignature);

        bytes4 unknown02 =
            harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, abi.encodePacked(uint8(0x02), hex"AA"));
        bytes4 unknown7F =
            harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, abi.encodePacked(uint8(0x7F), hex"BB"));
        bytes4 unknownFF =
            harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, abi.encodePacked(uint8(0xFF), hex"CC"));

        // Verify: only supported routing prefixes should return magic.
        assertEq(recoveryResult, SignatureUtils.ERC1271_MAGIC_VALUE, "recovery prefix should produce magic");
        assertEq(policyResult, SignatureUtils.ERC1271_MAGIC_VALUE, "policy prefix should produce magic");
        assertEq(unknown02, SignatureUtils.ERC1271_INVALID_VALUE, "unknown prefix should return invalid");
        assertEq(unknown7F, SignatureUtils.ERC1271_INVALID_VALUE, "unknown prefix should return invalid");
        assertEq(unknownFF, SignatureUtils.ERC1271_INVALID_VALUE, "unknown prefix should return invalid");
    }

    /// @dev Verifies non-policy payload classes return without revert, while malformed policy payloads revert.
    function invariant_isValidSignature_payloadClassRevertBehavior_isStable() public {
        // Setup: prepare representative non-policy payloads plus valid recovery/policy fixtures.
        _setTxRecoveryState(guardianSigner, true);

        (bytes memory validPolicySignature,,,,,) =
            _buildValidPolicySignature(PolicyType.AutoApprove, DEFAULT_POLICY_ID, block.timestamp + 1 days);
        bytes memory validRecoverySignature = _buildRecoverySignature(_signHash(GUARDIAN_PK, MESSAGE_HASH));

        bytes[] memory payloads = new bytes[](5);
        payloads[0] = bytes("");
        payloads[1] = hex"00";
        payloads[2] = abi.encodePacked(uint8(0x02), hex"ABCD");
        payloads[3] = validRecoverySignature;
        payloads[4] = validPolicySignature;

        // Call: execute low-level wrapper calls for non-policy-malformed representative payloads.
        for (uint256 i = 0; i < payloads.length; i++) {
            (bool success, bytes memory result) = address(harness)
                .staticcall(abi.encodeCall(harness.isValidSignatureViaLibrary, (ACCOUNT, MESSAGE_HASH, payloads[i])));

            // Verify: each payload should return a value (magic or invalid) rather than reverting.
            assertTrue(success, "representative non-policy payload should not revert");
            bytes4 value = abi.decode(result, (bytes4));
            assertTrue(
                value == SignatureUtils.ERC1271_MAGIC_VALUE || value == SignatureUtils.ERC1271_INVALID_VALUE,
                "isValidSignature should only return magic or invalid values"
            );
        }

        // Call: execute type-only policy payload expected to revert during decode.
        bytes memory typeOnlyPolicyPayload = abi.encodePacked(uint8(0x01));
        (bool typeOnlyPolicySuccess,) = address(harness)
            .staticcall(
                abi.encodeCall(harness.isValidSignatureViaLibrary, (ACCOUNT, MESSAGE_HASH, typeOnlyPolicyPayload))
            );

        // Verify: type-only policy payload class should revert.
        assertFalse(typeOnlyPolicySuccess, "type-only policy payload should revert");

        // Call: execute malformed policy payload expected to revert during decode.
        bytes memory malformedPolicyPayload = abi.encodePacked(uint8(0x01), hex"DEADBEEF");
        (bool malformedSuccess,) = address(harness)
            .staticcall(
                abi.encodeCall(harness.isValidSignatureViaLibrary, (ACCOUNT, MESSAGE_HASH, malformedPolicyPayload))
            );

        // Verify: malformed policy payload class should revert.
        assertFalse(malformedSuccess, "malformed policy payload should revert");
    }

    /// @dev Verifies that signatures valid in one organization are invalid in another organization.
    function invariant_crossOrganizationReplay_isRejected() public {
        // Setup: build valid signature on organization A and mirror policy/root/member config on organization B.
        LibOrganizationAccountSignatureHarness orgB = new LibOrganizationAccountSignatureHarness();
        _seedMembers(address(orgB));

        policyStateHarness.setGuardian(guardianSigner);
        orgB.setGuardian(guardianSigner);

        uint256 expiration = block.timestamp + 1 days;
        (bytes memory signature,,,,, Policy memory policy) =
            _buildValidPolicySignature(PolicyType.AutoApprove, DEFAULT_POLICY_ID, expiration);

        // Rebuild root + proofs on orgB with same policy leaf.
        bytes32 root = _computePolicyLeaf(DEFAULT_POLICY_ID, policy);
        orgB.setPoliciesRoot(root);

        // Call: execute validation on organization A and replay on organization B.
        bytes4 onOrgA = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        bytes4 onOrgB = orgB.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);

        // Verify: cross-org replay should fail on organization B.
        assertEq(onOrgA, SignatureUtils.ERC1271_MAGIC_VALUE, "sanity: signature should be valid in org A");
        assertEq(onOrgB, SignatureUtils.ERC1271_INVALID_VALUE, "cross-org replay should be invalid");
    }

    /// @dev Verifies that review hash changes whenever initiator signature bytes change.
    function invariant_reviewHashBindsInitiatorSignatureBytes() public view {
        // Setup: derive two different initiator signatures for the same request metadata.
        uint256 expiration = block.timestamp + 1 days;
        bytes32 initiatorHash =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);

        bytes memory initiatorSigA = _signHash(INITIATOR_PK_1, initiatorHash);
        bytes memory initiatorSigB = _signHash(INITIATOR_PK_2, initiatorHash);

        // Call: compute review hashes for each initiator signature variant.
        bytes32 reviewHashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSigA
        });
        bytes32 reviewHashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSigB
        });

        // Verify: review hash must change when initiator signature changes.
        assertTrue(reviewHashA != reviewHashB, "review hash should change with initiator signature bytes");
    }

    /// @dev Verifies that signature validation remains view-only and does not mutate storage usage state.
    function invariant_signatureValidation_isViewAndDoesNotMutateUsage() public {
        // Setup: restore signer membership assumptions and build valid policy signature fixture.
        _seedDefaultMembers();
        (bytes memory signature,,,,,) =
            _buildValidPolicySignature(PolicyType.AutoApprove, DEFAULT_POLICY_ID, block.timestamp + 1 days);

        // Setup: capture storage snapshots before the call under test.
        bytes32 usageKey = keccak256("account-signature-invariant-usage-key");
        uint256 timeWindow = 777;
        uint256 beforeUsage = policyStateHarness.getPolicyUsage(usageKey, timeWindow);
        bytes32 beforeRoot = policyStateHarness.getPoliciesRoot();

        // Call: execute signature validation.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);

        // Verify: validation result is correct and tracked storage remains unchanged.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "sanity: prepared signature should validate");
        assertEq(policyStateHarness.getPolicyUsage(usageKey, timeWindow), beforeUsage, "policy usage should not change");
        assertEq(policyStateHarness.getPoliciesRoot(), beforeRoot, "policies root should not change");
    }

    /// @dev Verifies that signatures valid for one account are invalid for other accounts in the same organization.
    function invariant_crossAccountReplay_isRejectedWithinSameOrganization() public {
        // Setup: build valid policy signature fixture for `ACCOUNT`.
        (bytes memory signature,,,,,) =
            _buildValidPolicySignature(PolicyType.AutoApprove, DEFAULT_POLICY_ID, block.timestamp + 1 days);

        // Call: validate signature for signed account and replay against a different account.
        bytes4 signedAccountResult = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        bytes4 replayAccountResult = harness.isValidSignatureViaLibrary(OTHER_ACCOUNT, MESSAGE_HASH, signature);

        // Verify: cross-account replay should fail within same organization.
        assertEq(signedAccountResult, SignatureUtils.ERC1271_MAGIC_VALUE, "sanity: signed account should validate");
        assertEq(replayAccountResult, SignatureUtils.ERC1271_INVALID_VALUE, "cross-account replay should be invalid");
    }

    /// @dev Verifies that repeated validation with fixed pre-expiration inputs is stable and stateless.
    function invariant_repeatedValidation_preExpiration_isStableAndStateless() public {
        // Setup: prepare valid pre-expiration policy signature fixture and snapshot storage.
        (bytes memory signature,,,,,) =
            _buildValidPolicySignature(PolicyType.AutoApprove, DEFAULT_POLICY_ID, block.timestamp + 1 days);

        bytes32 usageKey = keccak256("account-signature-repeatability-usage-key");
        uint256 timeWindow = 991;
        uint256 beforeUsage = policyStateHarness.getPolicyUsage(usageKey, timeWindow);

        // Call: execute identical validation twice.
        bytes4 first = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        bytes4 second = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);

        // Verify: repeated calls should produce stable results and no state consumption.
        assertEq(first, second, "repeated validations should return identical values");
        assertEq(first, SignatureUtils.ERC1271_MAGIC_VALUE, "prepared signature should remain valid pre-expiration");
        assertEq(
            policyStateHarness.getPolicyUsage(usageKey, timeWindow),
            beforeUsage,
            "validation should not consume usage state"
        );
    }
}
