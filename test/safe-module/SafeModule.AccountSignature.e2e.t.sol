// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import {BatchedTransaction} from "../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";
import {IOrganizationAccountSignature} from "interfaces/organization/IOrganizationAccountSignature.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {AccountImplementationHarness} from "test/account/AccountImplementationHarness.sol";
import {MockGuardianSafe} from "test/helpers/MockGuardianSafe.sol";
import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {Policy, PolicyType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Beacon-backed organization harness used to exercise the real `AccountImplementation` path.
 */
contract AccountSignatureOrganizationBeacon is
    LibOrganizationAccountSignatureHarness,
    IBeacon,
    IOrganizationAccountSignature
{
    address internal immutable BEACON_IMPLEMENTATION;

    /**
     * @dev Stores the account implementation returned from `implementation()`.
     * @param initialImplementation Account implementation used by the `BeaconProxy`.
     */
    constructor(address initialImplementation) {
        BEACON_IMPLEMENTATION = initialImplementation;
    }

    /**
     * @dev Returns the implementation used by the proxy account under test.
     * @return implementationAddress Account implementation address for the `BeaconProxy`.
     */
    function implementation() external view returns (address implementationAddress) {
        implementationAddress = BEACON_IMPLEMENTATION;
    }

    /**
     * @dev Validates signatures for `AccountImplementation` through the real organization entry point.
     * @param account Account whose signature is being checked.
     * @param hash Message hash under validation.
     * @param signature Type-prefixed signature payload.
     * @return magicValue ERC-1271 magic value on success, invalid value otherwise.
     */
    function isValidSignatureForAccount(address account, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4 magicValue)
    {
        if (msg.sender != account) {
            revert IOrganizationAccountSignature.SenderIsNotAccount();
        }

        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);
        magicValue = LibOrganizationAccountSignature.isValidSignature(account, hash, signature);
    }
}

/**
 * @dev End-to-end account-signature tests covering the Safe-module guardian path.
 */
contract SafeModuleAccountSignatureE2ETest is LibOrganizationAccountSignatureTestBase {
    uint256 internal constant AUTHORIZED_EXECUTOR_PK = 0xA11CE;
    uint256 internal constant NEW_AUTHORIZED_EXECUTOR_PK = 0xB0B;

    AccountImplementationHarness internal accountImplementation;
    AccountImplementationHarness internal account;
    AccountSignatureOrganizationBeacon internal organization;
    BatchedTransaction internal batchedTransaction;

    /**
     * @dev Deploys the organization harness as the proxy beacon for the account under test.
     * @return deployedHarness Shared admin-state harness surface for the suite base.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness deployedHarness) {
        accountImplementation = new AccountImplementationHarness();
        organization = new AccountSignatureOrganizationBeacon(address(accountImplementation));
        harness = LibOrganizationAccountSignatureHarness(address(organization));
        deployedHarness = OrganizationAdminStateHarness(address(organization));
    }

    /**
     * @dev Deploys the proxy account and marks it as organization-owned.
     */
    function setUp() public override {
        super.setUp();
        account = AccountImplementationHarness(payable(address(new BeaconProxy(address(organization), bytes("")))));
        policyStateHarness.setDeployedAccount(address(account), true);
        batchedTransaction = new BatchedTransaction();
    }

    /// @dev Verifies `Account.isValidSignature` accepts enabled-module guardian signatures from the authorized
    /// executor.
    function test_accountIsValidSignature_acceptsEnabledModuleGuardianSignature()
        public
    {
        // Setup: configure a valid auto-approve policy signature backed by an enabled SafeExecutorModule guardian.
        (, bytes memory signature,,,) =
            _buildAccountPolicySignatureWithModuleGuardian(AUTHORIZED_EXECUTOR_PK, true, AUTHORIZED_EXECUTOR_PK);

        // Call: validate the policy signature through the full Account -> Organization path.
        bytes4 actual = account.isValidSignature(MESSAGE_HASH, signature);

        // Verify: the account returns the ERC-1271 magic value for the enabled module guardian path.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "enabled module guardian signature should validate");
    }

    /// @dev Verifies disabling the guardian module invalidates equivalent account signatures without org changes.
    function test_accountIsValidSignature_rejectsDisabledModuleGuardianSignature()
        public
    {
        // Setup: build a valid signature, then disable the module on the guardian Safe before validation.
        (MockGuardianSafe guardianSafe, bytes memory signature, SafeExecutorModule module,,) =
            _buildAccountPolicySignatureWithModuleGuardian(AUTHORIZED_EXECUTOR_PK, true, AUTHORIZED_EXECUTOR_PK);
        guardianSafe.setModuleEnabled(address(module), false);

        // Call: validate the previously valid module-style signature after disablement.
        bytes4 actual = account.isValidSignature(MESSAGE_HASH, signature);

        // Verify: disabling the module invalidates the account signature immediately.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "disabled module signature should be invalid");
    }

    /// @dev Verifies guardian-module rotation invalidates old signatures immediately and activates new ones
    /// immediately through the full account path.
    /// @param oldExecutorPkRaw Raw private key used for the original module executor.
    /// @param newExecutorPkRaw Raw private key used for the replacement module executor.
    function testFuzz_accountIsValidSignature_moduleRotationOldFailsNewPasses(
        uint256 oldExecutorPkRaw,
        uint256 newExecutorPkRaw
    ) public {
        uint256 oldExecutorPk = bound(oldExecutorPkRaw, 1, SECP256K1_CURVE_ORDER - 1);
        uint256 newExecutorPk = bound(newExecutorPkRaw, 1, SECP256K1_CURVE_ORDER - 1);
        vm.assume(oldExecutorPk != newExecutorPk);

        // Setup: deploy old and new modules on the same guardian Safe; enable the old module first.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule oldModule =
            new SafeExecutorModule(address(guardianSafe), vm.addr(oldExecutorPk), address(batchedTransaction));
        SafeExecutorModule newModule =
            new SafeExecutorModule(address(guardianSafe), vm.addr(newExecutorPk), address(batchedTransaction));
        guardianSafe.setModuleEnabled(address(oldModule), true);
        policyStateHarness.setGuardian(address(guardianSafe));

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes32 policiesRootBefore = policyStateHarness.getPoliciesRoot();
        bool accountDeploymentBefore = policyStateHarness.isDeployedAccount(address(account));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: address(account),
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        bytes memory oldGuardianSignature = _buildContractSignature(
            address(oldModule),
            _signReviewSignature({
                sigHarness: harness,
                privateKey: oldExecutorPk,
                account: address(account),
                hash: MESSAGE_HASH,
                policyId: DEFAULT_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: initiatorSignature
            })
        );
        bytes memory oldSignature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: oldGuardianSignature,
            proofs: proofs
        });

        // Verify: old module signature is valid before rotation.
        bytes4 preRotationResult = account.isValidSignature(MESSAGE_HASH, oldSignature);
        assertEq(preRotationResult, SignatureUtils.ERC1271_MAGIC_VALUE, "old module should be valid before rotation");

        // Setup: rotate — disable old module, enable new module.
        guardianSafe.setModuleEnabled(address(oldModule), false);
        guardianSafe.setModuleEnabled(address(newModule), true);

        bytes memory newGuardianSignature = _buildContractSignature(
            address(newModule),
            _signReviewSignature({
                sigHarness: harness,
                privateKey: newExecutorPk,
                account: address(account),
                hash: MESSAGE_HASH,
                policyId: DEFAULT_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: initiatorSignature
            })
        );
        bytes memory newSignature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: newGuardianSignature,
            proofs: proofs
        });

        // Call: validate signatures from the disabled old module and the enabled replacement module.
        bytes4 oldResult = account.isValidSignature(MESSAGE_HASH, oldSignature);
        bytes4 newResult = account.isValidSignature(MESSAGE_HASH, newSignature);

        // Verify: rotation takes effect immediately for the account's ERC-1271 path.
        assertEq(oldResult, SignatureUtils.ERC1271_INVALID_VALUE, "disabled old module should be invalid");
        assertEq(newResult, SignatureUtils.ERC1271_MAGIC_VALUE, "enabled new module should be valid");
        assertEq(policyStateHarness.getPoliciesRoot(), policiesRootBefore, "rotation should not mutate policy root");
        assertEq(
            policyStateHarness.isDeployedAccount(address(account)),
            accountDeploymentBefore,
            "rotation should not mutate deployed-account tracking"
        );
    }

    /// @dev Verifies the direct guardian signature path still works when the module path is unavailable.
    function test_accountIsValidSignature_directGuardianPathStillWorksWithoutModule()
        public
    {
        // Setup: configure a valid direct-guardian auto-approve signature without any module path.
        policyStateHarness.setGuardian(guardianSigner);
        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: address(account),
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: address(account),
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: validate the direct guardian signature through the full account path.
        bytes4 actual = account.isValidSignature(MESSAGE_HASH, signature);

        // Verify: direct guardian signatures still validate when no module is involved.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "direct guardian signature should remain valid");
    }

    /**
     * @dev Builds a valid policy signature for `account` using a module-style guardian signature.
     * @param moduleExecutorPk Private key configured as the module's authorized executor.
     * @param enableModule Whether the guardian Safe enables the module before validation.
     * @param innerSignerPk Private key used to sign the module's inner review-hash payload.
     * @return guardianSafe Guardian Safe mock used for module enablement.
     * @return signature Full top-level policy signature passed to `Account.isValidSignature`.
     * @return module SafeExecutorModule that validates the inner signature.
     * @return initiatorSignature Initiator signature bound into the request.
     * @return proofs Policy proofs included in `signature`.
     */
    function _buildAccountPolicySignatureWithModuleGuardian(
        uint256 moduleExecutorPk,
        bool enableModule,
        uint256 innerSignerPk
    )
        internal
        returns (
            MockGuardianSafe guardianSafe,
            bytes memory signature,
            SafeExecutorModule module,
            bytes memory initiatorSignature,
            ValidationProofs memory proofs
        )
    {
        guardianSafe = new MockGuardianSafe();
        module = new SafeExecutorModule(address(guardianSafe), vm.addr(moduleExecutorPk), address(batchedTransaction));
        guardianSafe.setModuleEnabled(address(module), enableModule);
        policyStateHarness.setGuardian(address(guardianSafe));

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: address(account),
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        bytes memory guardianInnerSignature = _signReviewSignature({
            sigHarness: harness,
            privateKey: innerSignerPk,
            account: address(account),
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory guardianSignature = _buildContractSignature(address(module), guardianInnerSignature);

        signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });
    }
}
