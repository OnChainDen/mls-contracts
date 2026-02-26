// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {
    ApproverType,
    ConstraintType,
    DestinationType,
    ParamType,
    ParameterConstraint,
    Policy,
    RateLimitScope,
    TransactionType
} from "types/PolicyTypes.sol";

/**
 * @dev Cross-file fuzz tests for organization policy behaviors.
 *      Covers Section 11.1 IDs `POL-F-1` through `POL-F-7`.
 */
contract OrganizationPolicyCrossFileFuzzTest is LibOrganizationPolicySuiteBase {
    uint256 internal constant DEFAULT_POLICY_ID = 5001;

    // POL-F-1
    function testFuzz_POL_F_1_policyFieldMutationInvalidatesOriginalProof(uint256 policyIdSeed, uint8 mutationSelector)
        public
    {
        uint256 policyId = bound(policyIdSeed, 1, type(uint96).max);

        Policy memory policy = _buildBasePolicy();
        policy.config.anySourceAccount = false;
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.transactionType = TransactionType.ContractInteractions;
        policy.config.approval.approvalThreshold = 2;

        policy.roots.sourceAccountsRoot = keccak256("src-root");
        policy.roots.customDestinationsRoot = keccak256("dest-root");
        policy.roots.allowedFunctionsRoot = keccak256("fn-root");

        bytes32 root = _computePolicyLeaf(policyId, policy);
        policyStateHarness.setPoliciesRoot(root);

        bytes32[] memory empty = new bytes32[](0);
        assertTrue(harness.isPolicyInOrgViaLibrary(policyId, policy, empty), "baseline proof should validate");

        Policy memory mutated = policy;
        uint8 selector = uint8(mutationSelector % 8);

        if (selector == 0) {
            mutated.config.transactionType = TransactionType.TokenTransfers;
        } else if (selector == 1) {
            mutated.config.anySourceAccount = !policy.config.anySourceAccount;
        } else if (selector == 2) {
            mutated.config.destinationType = DestinationType.Any;
        } else if (selector == 3) {
            mutated.config.approval.approvalThreshold = policy.config.approval.approvalThreshold + 1;
        } else if (selector == 4) {
            mutated.config.initiator.initiatorMember = reviewer1;
        } else if (selector == 5) {
            mutated.config.token.amountThreshold = policy.config.token.amountThreshold + 1;
        } else if (selector == 6) {
            mutated.roots.sourceAccountsRoot = keccak256("mut-src-root");
        } else {
            mutated.roots.allowedFunctionsRoot = keccak256("mut-fn-root");
        }

        assertFalse(harness.isPolicyInOrgViaLibrary(policyId, mutated, empty), "single-field mutation must break proof");
    }

    // POL-F-2
    function testFuzz_POL_F_2_sourceAccountProofsOnlyPassForExactTuple(
        address accountA,
        address accountB,
        bool useFirst
    ) public {
        vm.assume(accountA != address(0));
        vm.assume(accountB != address(0));
        vm.assume(accountA != accountB);

        address[] memory sourceAccounts = buildArray(accountA, accountB);
        uint256 targetIndex = useFirst ? 0 : 1;
        uint256 otherIndex = useFirst ? 1 : 0;

        (bytes32 sourceRoot, bytes32[] memory proof) = _buildAddressRootAndProof(sourceAccounts, targetIndex);

        Policy memory policy = _buildBasePolicy();
        policy.config.anySourceAccount = false;
        policy.roots.sourceAccountsRoot = sourceRoot;

        assertTrue(
            harness.isSourceAccountAllowedByPolicyViaLibrary(policy, sourceAccounts[targetIndex], proof),
            "exact account/root/proof tuple should pass"
        );

        assertFalse(
            harness.isSourceAccountAllowedByPolicyViaLibrary(policy, sourceAccounts[otherIndex], proof),
            "wrong account with same proof should fail"
        );
    }

    // POL-F-3
    function testFuzz_POL_F_3_destinationProofsValidateOnlyActualDestination(
        uint8 shape,
        address allowedDestination,
        address otherDestination,
        address tokenContract,
        uint256 amount
    ) public {
        vm.assume(allowedDestination != address(0));
        vm.assume(otherDestination != address(0));
        vm.assume(tokenContract != address(0));
        vm.assume(allowedDestination != otherDestination);

        amount = bound(amount, 1, type(uint96).max);

        Policy memory policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.CustomList;

        address[] memory destinations = buildArray(allowedDestination);
        (bytes32 root, bytes32[] memory destinationProof) = _buildAddressRootAndProof(destinations, 0);
        policy.roots.customDestinationsRoot = root;

        uint8 mode = uint8(shape % 3);
        bool allowedResult;
        bool deniedResult;

        if (mode == 0) {
            // Native transfer destination is `to`.
            allowedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, allowedDestination, amount, bytes(""), destinationProof
            );
            deniedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, otherDestination, amount, bytes(""), destinationProof
            );
        } else if (mode == 1) {
            // ERC-20 transfer destination is encoded recipient.
            bytes memory allowedData = _encodeERC20Transfer(allowedDestination, amount);
            bytes memory deniedData = _encodeERC20Transfer(otherDestination, amount);

            allowedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, tokenContract, 0, allowedData, destinationProof
            );
            deniedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, tokenContract, 0, deniedData, destinationProof
            );
        } else {
            // Contract interaction destination is `to`.
            bytes memory callData = abi.encodeWithSelector(bytes4(0x11223344), uint256(1));
            allowedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, allowedDestination, 0, callData, destinationProof
            );
            deniedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, otherDestination, 0, callData, destinationProof
            );
        }

        assertTrue(allowedResult, "exact actual destination should pass");
        assertFalse(deniedResult, "different actual destination should fail");
    }

    // POL-F-4
    function testFuzz_POL_F_4_functionProofsBindSelectorAndConstraints(
        bytes4 selector,
        uint256 callArg,
        bytes32 constraintsSeed,
        bytes32 alternateConstraintsSeed
    ) public {
        vm.assume(constraintsSeed != alternateConstraintsSeed);

        bytes memory constraints = abi.encode(constraintsSeed);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;

        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;

        (bytes32 functionRoot, bytes32[] memory functionProof) =
            _buildFunctionRootAndProof(selectors, constraintsList, 0);

        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = false;
        policy.roots.allowedFunctionsRoot = functionRoot;

        bytes memory data = abi.encodeWithSelector(selector, callArg);
        bool exactPairAllowed =
            harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, data, functionProof, constraints);
        assertTrue(exactPairAllowed, "exact selector+constraints tuple should pass");

        bytes4 mutatedSelector = selector ^ bytes4(uint32(1));
        bytes memory mutatedSelectorData = abi.encodeWithSelector(mutatedSelector, callArg);
        bool mutatedSelectorAllowed =
            harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, mutatedSelectorData, functionProof, constraints);
        assertFalse(mutatedSelectorAllowed, "selector mutation should fail proof");

        bytes memory alternateConstraints = abi.encode(alternateConstraintsSeed);
        bool mutatedConstraintsAllowed =
            harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, data, functionProof, alternateConstraints);
        assertFalse(mutatedConstraintsAllowed, "constraints mutation should fail proof");
    }

    // POL-F-5
    function testFuzz_POL_F_5_duplicateOrOutOfOrderSignersAlwaysRevert(bool useDuplicate, bytes32 hashSeed) public {
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setMemberStatus(reviewer2, true);
        policyStateHarness.setGroupStatus(55, true);
        policyStateHarness.setGroupMemberStatus(55, reviewer1, true);
        policyStateHarness.setGroupMemberStatus(55, reviewer2, true);

        Policy memory policy = _buildBasePolicy();
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = 55;
        policy.config.approval.approvalThreshold = 2;

        bytes32 messageHash = keccak256(abi.encode(hashSeed));
        bytes memory sig1 = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory sig2 = _signHash(REVIEWER_PK_2, messageHash);

        bytes memory packed;
        if (useDuplicate) {
            packed = abi.encodePacked(sig1, sig1);
        } else {
            // Deliberately construct descending order.
            packed = reviewer1 < reviewer2 ? abi.encodePacked(sig2, sig1) : abi.encodePacked(sig1, sig2);
        }

        vm.expectRevert();
        harness.areApprovalsValidViaPolicyLibrary(policy, packed, messageHash);
    }

    // POL-F-6
    function testFuzz_POL_F_6_rateLimitScopeCollisionMatchesScopeModel(
        uint8 sourceScopeSeed,
        uint8 destinationScopeSeed,
        uint8 initiatorScopeSeed,
        bool sameAccount,
        bool sameDestination,
        bool sameInitiator
    ) public {
        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.sourceScope = RateLimitScope(sourceScopeSeed % 2);
        policy.config.rateLimit.destinationScope = RateLimitScope(destinationScopeSeed % 2);
        policy.config.rateLimit.initiatorScope = RateLimitScope(initiatorScopeSeed % 2);

        address account1 = address(0xA101);
        address account2 = sameAccount ? account1 : address(0xA202);
        address destination1 = address(0xB101);
        address destination2 = sameDestination ? destination1 : address(0xB202);
        address initiatorA = address(0xC101);
        address initiatorB = sameInitiator ? initiatorA : address(0xC202);

        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(DEFAULT_POLICY_ID, policy, account1, destination1, initiatorA);
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(DEFAULT_POLICY_ID, policy, account2, destination2, initiatorB);

        bool expectCollision = (policy.config.rateLimit.sourceScope != RateLimitScope.PerEntity || account1 == account2)
            && (policy.config.rateLimit.destinationScope != RateLimitScope.PerEntity || destination1 == destination2)
            && (policy.config.rateLimit.initiatorScope != RateLimitScope.PerEntity || initiatorA == initiatorB);

        assertEq(keyA == keyB, expectCollision, "observed key collision should match scope model");
    }

    // POL-F-7
    function testFuzz_POL_F_7_dynamicBytesStringOutOfBoundsFailClosed(uint256 offsetSeed, uint256 lengthSeed) public {
        uint256 badOffset = bound(offsetSeed, 64, 10_000);
        uint256 badLength = bound(lengthSeed, 1, 10_000);

        bytes32 expectedHash = keccak256("expected-dynamic-value");
        bytes32[] memory noProof = new bytes32[](0);

        ParameterConstraint memory bytesConstraint = _buildConstraint({
            paramType: ParamType.Bytes,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(expectedHash),
            paramValueInListProof: noProof
        });
        bytes memory bytesConstraints = _encodeSingleConstraint(bytesConstraint);

        ParameterConstraint memory stringConstraint = _buildConstraint({
            paramType: ParamType.String,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(expectedHash),
            paramValueInListProof: noProof
        });
        bytes memory stringConstraints = _encodeSingleConstraint(stringConstraint);

        // Case 1: Offset points beyond available calldata.
        bytes memory badOffsetData = abi.encodePacked(bytes4(0xABCD0001), bytes32(badOffset));

        bool bytesOffsetResult =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(bytesConstraints, badOffsetData);
        bool stringOffsetResult =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(stringConstraints, badOffsetData);

        assertFalse(bytesOffsetResult, "bytes offset OOB should fail closed");
        assertFalse(stringOffsetResult, "string offset OOB should fail closed");

        // Case 2: Offset is in-bounds, but declared length exceeds calldata.
        bytes memory badLengthData = abi.encodePacked(bytes4(0xABCD0002), bytes32(uint256(32)), bytes32(badLength));

        bool bytesLengthResult =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(bytesConstraints, badLengthData);
        bool stringLengthResult =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(stringConstraints, badLengthData);

        assertFalse(bytesLengthResult, "bytes length OOB should fail closed");
        assertFalse(stringLengthResult, "string length OOB should fail closed");
    }
}
