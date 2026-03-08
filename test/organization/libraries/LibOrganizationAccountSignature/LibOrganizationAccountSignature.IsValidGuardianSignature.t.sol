// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BatchedTransaction} from "../../../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../../../src/safe-module/SafeExecutorModule.sol";
import {MockGuardianSafe} from "test/helpers/MockGuardianSafe.sol";
import {MockGuardianModuleReverter} from "test/helpers/MockGuardianSignatureValidation.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountSignature._isValidGuardianSignature`.
 */
contract LibOrganizationAccountSignatureIsValidGuardianSignatureTest is LibOrganizationAccountSignatureTestBase {
    uint256 internal constant AUTHORIZED_EXECUTOR_PK = 0xA11CE5;
    uint256 internal constant OLD_EXECUTOR_PK = 0x0D100;
    uint256 internal constant NEW_EXECUTOR_PK = 0x0E100;

    BatchedTransaction internal batchedTransaction;

    /// @dev Seeds the batched helper required by `SafeExecutorModule`.
    function setUp() public override {
        super.setUp();
        batchedTransaction = new BatchedTransaction();
    }

    /// @dev Verifies `_isValidGuardianSignature` returns true for a direct guardian EOA signature.
    function test_LOAS_IVGS_1_LOACS_IVGS_1_isValidGuardianSignature_directGuardianSignature_returnsTrue() public {
        // Setup: configure the guardian as a deterministic EOA and sign the tracked message hash.
        policyStateHarness.setGuardian(guardianSigner);
        bytes memory guardianSignature = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: validate the direct guardian signature.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: the direct guardian signer is accepted.
        assertTrue(actual, "direct guardian signature should be valid");
    }

    /// @dev Verifies `_isValidGuardianSignature` accepts an enabled `SafeExecutorModule` contract signature.
    function test_LOAS_IVGS_2_LOACS_IVGS_2_isValidGuardianSignature_enabledModuleContractSignature_returnsTrue()
        public
    {
        // Setup: configure a guardian Safe with an enabled executor module and sign through the authorized executor.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule module = _deployModule(address(guardianSafe), AUTHORIZED_EXECUTOR_PK);
        guardianSafe.setModuleEnabled(address(module), true);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory guardianSignature = _buildModuleGuardianSignature(module, AUTHORIZED_EXECUTOR_PK, MESSAGE_HASH);

        // Call: validate the module-backed guardian signature.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: enabled module signatures are accepted.
        assertTrue(actual, "enabled module contract signature should be valid");
    }

    /// @dev Verifies `_isValidGuardianSignature` rejects valid module signatures from non-enabled modules.
    function test_LOAS_IVGS_3_isValidGuardianSignature_disabledModuleContractSignature_returnsFalse() public {
        // Setup: configure a guardian Safe without enabling the module that produced the contract signature.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule module = _deployModule(address(guardianSafe), AUTHORIZED_EXECUTOR_PK);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory guardianSignature = _buildModuleGuardianSignature(module, AUTHORIZED_EXECUTOR_PK, MESSAGE_HASH);

        // Call: validate the disabled-module signature.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: non-enabled module signatures fail closed.
        assertFalse(actual, "disabled module contract signature should be invalid");
    }

    /// @dev Verifies a previously valid enabled-module guardian signature becomes invalid immediately after disable.
    function test_LOACS_IVGS_3_isValidGuardianSignature_enabledThenDisabledModuleSignature_returnsFalse() public {
        // Setup: configure a guardian Safe, validate one enabled-module signature, then disable that same module.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule module = _deployModule(address(guardianSafe), AUTHORIZED_EXECUTOR_PK);
        guardianSafe.setModuleEnabled(address(module), true);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory guardianSignature = _buildModuleGuardianSignature(module, AUTHORIZED_EXECUTOR_PK, MESSAGE_HASH);

        // Call: validate once while enabled, then again after disabling the module.
        bool enabledAccepted = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);
        guardianSafe.setModuleEnabled(address(module), false);
        bool disabledAccepted = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: the exact same module signature stops authorizing immediately after disable.
        assertTrue(enabledAccepted, "enabled module signature should be valid before disable");
        assertFalse(disabledAccepted, "disabled module signature should be invalid after disable");
    }

    /// @dev Verifies `_isValidGuardianSignature` rejects modules enabled on a different Safe.
    function test_LOAS_IVGS_4_isValidGuardianSignature_moduleEnabledOnDifferentSafe_returnsFalse() public {
        // Setup: enable a module on one Safe while configuring a different Safe as the guardian.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        MockGuardianSafe otherSafe = new MockGuardianSafe();
        SafeExecutorModule module = _deployModule(address(otherSafe), AUTHORIZED_EXECUTOR_PK);
        otherSafe.setModuleEnabled(address(module), true);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory guardianSignature = _buildModuleGuardianSignature(module, AUTHORIZED_EXECUTOR_PK, MESSAGE_HASH);

        // Call: validate the signature against the actual guardian Safe.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: module enablement on another Safe does not authorize the guardian path.
        assertFalse(actual, "module enabled on a different Safe should be invalid");
    }

    /// @dev Verifies `_isValidGuardianSignature` rejects module signatures whose inner signer is not authorized.
    function test_LOAS_IVGS_5_isValidGuardianSignature_wrongExecutorModuleSignature_returnsFalse() public {
        // Setup: enable a module on the guardian Safe but sign the inner payload with the wrong executor key.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule module = _deployModule(address(guardianSafe), AUTHORIZED_EXECUTOR_PK);
        guardianSafe.setModuleEnabled(address(module), true);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory guardianSignature = _buildModuleGuardianSignature(module, REVIEWER_PK_1, MESSAGE_HASH);

        // Call: validate the malformed inner-authorizer combination.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: module signatures signed by the wrong executor fail closed.
        assertFalse(actual, "wrong executor module signature should be invalid");
    }

    /// @dev Verifies `_isValidGuardianSignature` returns false for malformed module inner signatures.
    function test_LOAS_IVGS_6_isValidGuardianSignature_malformedModuleInnerSignature_returnsFalse() public {
        // Setup: enable a module on the guardian Safe and provide malformed inner signature bytes.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule module = _deployModule(address(guardianSafe), AUTHORIZED_EXECUTOR_PK);
        guardianSafe.setModuleEnabled(address(module), true);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory guardianSignature = _buildContractSignature(address(module), hex"1b");

        // Call: validate the malformed module signature payload.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: malformed inner signatures fail closed without revert.
        assertFalse(actual, "malformed module inner signature should be invalid");
    }

    /// @dev Verifies guardian signatures over a different message hash are rejected even when the signer is otherwise
    /// authorized.
    function test_LOACS_IVGS_4_A_isValidGuardianSignature_directGuardianWrongMessageHash_returnsFalse() public {
        // Setup: configure the guardian as a deterministic EOA and sign a different tracked message hash.
        policyStateHarness.setGuardian(guardianSigner);
        bytes memory guardianSignature = _signHash(GUARDIAN_PK, OTHER_MESSAGE_HASH);

        // Call: validate the guardian signature against the original tracked message hash.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: guardian signatures must bind the exact message hash under review.
        assertFalse(actual, "guardian signature over a different message hash should be invalid");
    }

    /// @dev Verifies `_isValidGuardianSignature` fails closed when guardian module checks revert.
    function test_LOAS_IVGS_7_isValidGuardianSignature_revertingGuardianModuleCheck_returnsFalse() public {
        // Setup: configure a reverting guardian contract and sign through a module that points at it.
        MockGuardianModuleReverter guardian = new MockGuardianModuleReverter();
        SafeExecutorModule module = _deployModule(address(guardian), AUTHORIZED_EXECUTOR_PK);
        policyStateHarness.setGuardian(address(guardian));

        bytes memory guardianSignature = _buildModuleGuardianSignature(module, AUTHORIZED_EXECUTOR_PK, MESSAGE_HASH);

        // Call: validate the signature that requires a reverting module lookup.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: reverting module lookups fail closed.
        assertFalse(actual, "reverting guardian module checks should be invalid");
    }

    /// @dev Verifies `_isValidGuardianSignature` fails gracefully when the guardian is an EOA and signer mismatches.
    function test_LOAS_IVGS_9_isValidGuardianSignature_eoaGuardianMismatchedSigner_returnsFalse() public {
        // Setup: configure an EOA guardian that does not match the recovered signer.
        policyStateHarness.setGuardian(makeAddr("guardianEoa"));
        bytes memory guardianSignature = _signHash(REVIEWER_PK_1, MESSAGE_HASH);

        // Call: validate the mismatched EOA signature.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: EOA guardians without a matching signer fail closed.
        assertFalse(actual, "mismatched EOA guardian signature should be invalid");
    }

    /// @dev Verifies `_isValidGuardianSignature` reflects module rotation immediately.
    function test_LOAS_IVGS_10_LOACS_IVGS_3_isValidGuardianSignature_moduleRotation_oldFalseNewTrueImmediately()
        public
    {
        // Setup: configure old and new modules on the same guardian Safe and rotate enablement between them.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule oldModule = _deployModule(address(guardianSafe), OLD_EXECUTOR_PK);
        SafeExecutorModule newModule = _deployModule(address(guardianSafe), NEW_EXECUTOR_PK);
        guardianSafe.setModuleEnabled(address(oldModule), true);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory oldSignature = _buildModuleGuardianSignature(oldModule, OLD_EXECUTOR_PK, MESSAGE_HASH);
        bytes memory newSignature = _buildModuleGuardianSignature(newModule, NEW_EXECUTOR_PK, MESSAGE_HASH);

        // Call: validate both signatures before rotation.
        bool oldBeforeRotation = harness.isValidGuardianSignatureViaLibrary(oldSignature, MESSAGE_HASH);
        bool newBeforeRotation = harness.isValidGuardianSignatureViaLibrary(newSignature, MESSAGE_HASH);

        // Verify: only the old module is accepted before rotation.
        assertTrue(oldBeforeRotation, "old module should be valid before rotation");
        assertFalse(newBeforeRotation, "new module should be invalid before rotation");

        // Setup: rotate by disabling the old module and enabling the new one.
        guardianSafe.setModuleEnabled(address(oldModule), false);
        guardianSafe.setModuleEnabled(address(newModule), true);

        // Call: validate both signatures after rotation.
        bool oldAfterRotation = harness.isValidGuardianSignatureViaLibrary(oldSignature, MESSAGE_HASH);
        bool newAfterRotation = harness.isValidGuardianSignatureViaLibrary(newSignature, MESSAGE_HASH);

        // Verify: rotation takes effect immediately for signature acceptance.
        assertFalse(oldAfterRotation, "old module should be invalid after rotation");
        assertTrue(newAfterRotation, "new module should be valid immediately after rotation");
    }

    /// @dev Verifies otherwise-valid guardian module signatures are rejected when validated against a different message
    /// hash.
    function test_LOACS_IVGS_4_B_isValidGuardianSignature_moduleWrongMessageHash_returnsFalse() public {
        // Setup: configure a guardian Safe with one enabled executor module and sign one message hash.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule module = _deployModule(address(guardianSafe), AUTHORIZED_EXECUTOR_PK);
        guardianSafe.setModuleEnabled(address(module), true);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory guardianSignature = _buildModuleGuardianSignature(module, AUTHORIZED_EXECUTOR_PK, MESSAGE_HASH);

        // Call: validate the otherwise-valid module signature against a different message hash.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, OTHER_MESSAGE_HASH);

        // Verify: guardian signatures stay bound to the exact message hash they signed.
        assertFalse(actual, "guardian signature should fail for a different message hash");
    }

    /// @dev Deploys a `SafeExecutorModule` against the provided Safe-compatible guardian contract.
    /// @param safe The Safe-compatible guardian address that owns module enablement.
    /// @param executorPk The private key whose address becomes the module's authorized executor.
    /// @return module The deployed Safe executor module.
    function _deployModule(address safe, uint256 executorPk) internal returns (SafeExecutorModule module) {
        module = new SafeExecutorModule(safe, vm.addr(executorPk), address(batchedTransaction));
    }

    /// @dev Builds a module-backed guardian signature using the module contract wrapper format.
    /// @param module The `SafeExecutorModule` contract that should recover as the signer.
    /// @param executorPk The executor private key that signs the module's inner payload.
    /// @param messageHash The review hash being signed by the authorized executor.
    /// @return guardianSignature The nested ERC-1271 contract signature accepted by the module path.
    function _buildModuleGuardianSignature(SafeExecutorModule module, uint256 executorPk, bytes32 messageHash)
        internal
        view
        returns (bytes memory guardianSignature)
    {
        guardianSignature = _buildContractSignature(address(module), _signHash(executorPk, messageHash));
    }
}
