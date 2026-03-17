// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MerkleUtils} from "libraries/MerkleUtils.sol";
import {BytesWordHelpers} from "test/helpers/BytesWordHelpers.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationGroupsTestBase} from "test/organization/shared/OrganizationGroupsTestBase.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {
    ApprovalConfig,
    ApproverType,
    DestinationType,
    InitiatorConfig,
    ParameterConstraint,
    Policy,
    PolicyConfig,
    PolicyRoots,
    PolicyType,
    RateLimitConfig,
    RateLimitScope,
    RateLimitType,
    TokenFilter,
    TransactionType
} from "types/PolicyTypes.sol";

import {Merkle} from "murky/Merkle.sol";

/**
 * @dev Shared setup/builders for policy-focused organization tests.
 *      Centralizes deterministic policy structs, merkle proof builders, and auth/signature fixtures.
 */
abstract contract OrganizationPolicyTestBase is OrganizationGroupsTestBase, BytesWordHelpers {
    /// @dev Additional deterministic private keys used by policy/signature suites.
    uint256 internal constant INITIATOR_PK_1 = 0x91A0;
    uint256 internal constant INITIATOR_PK_2 = 0x91A1;
    uint256 internal constant REVIEWER_PK_1 = 0xA001;
    uint256 internal constant REVIEWER_PK_2 = 0xA002;
    uint256 internal constant REVIEWER_PK_3 = 0xA003;
    uint256 internal constant GUARDIAN_PK = 0xBEEF01;

    /// @dev Typed state harness with policy/account/recovery storage helpers.
    OrganizationPolicyStateHarness internal policyStateHarness;

    /// @dev Merkle helper used to build deterministic roots/proofs in tests.
    Merkle internal merkle;

    /// @dev Frequently used deterministic signer addresses for policy approval tests.
    address internal initiator1;
    address internal initiator2;
    address internal reviewer1;
    address internal reviewer2;
    address internal reviewer3;
    address internal guardianSigner;

    /**
     * @dev Initializes policy harness references and deterministic signer addresses.
     */
    function setUp() public virtual override {
        super.setUp();
        policyStateHarness = OrganizationPolicyStateHarness(address(stateHarness));
        merkle = new Merkle();

        initiator1 = vm.addr(INITIATOR_PK_1);
        initiator2 = vm.addr(INITIATOR_PK_2);
        reviewer1 = vm.addr(REVIEWER_PK_1);
        reviewer2 = vm.addr(REVIEWER_PK_2);
        reviewer3 = vm.addr(REVIEWER_PK_3);
        guardianSigner = vm.addr(GUARDIAN_PK);
    }

    /**
     * @dev Deploys the concrete harness for the current policy-focused suite.
     */
    function _deployHarness() internal virtual override returns (OrganizationAdminStateHarness);

    /**
     * @dev Builds a baseline policy with permissive defaults and disabled rate limit.
     */
    function _buildBasePolicy() internal view returns (Policy memory policy) {
        policy = Policy({
            config: PolicyConfig({
                transactionType: TransactionType.Any,
                anySourceAccount: true,
                anyFunction: true,
                destinationType: DestinationType.Any,
                approval: ApprovalConfig({
                    policyType: PolicyType.AutoApprove,
                    approverType: ApproverType.Member,
                    approverMember: reviewer1,
                    approverGroupId: 0,
                    approvalThreshold: 1
                }),
                initiator: InitiatorConfig({
                    anyInitiator: true,
                    initiatorType: ApproverType.Member,
                    initiatorMember: initiator1,
                    initiatorGroupId: 0
                }),
                token: TokenFilter({
                    anyToken: true, tokenAddress: address(0), hasAmountThreshold: false, amountThreshold: 0
                }),
                rateLimit: RateLimitConfig({
                    limitType: RateLimitType.None,
                    timeIntervalHours: 0,
                    timeIntervalLimit: 0,
                    anchorTimestamp: 0,
                    initiatorScope: RateLimitScope.AcrossAll,
                    sourceScope: RateLimitScope.AcrossAll,
                    destinationScope: RateLimitScope.AcrossAll
                })
            }),
            roots: PolicyRoots({
                sourceAccountsRoot: bytes32(0), customDestinationsRoot: bytes32(0), allowedFunctionsRoot: bytes32(0)
            })
        });
    }

    /**
     * @dev Computes policy leaf using required double-hash construction.
     */
    function _computePolicyLeaf(uint256 policyId, Policy memory policy) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
    }

    /**
     * @dev Computes function leaf using required double-hash construction.
     */
    function _computeFunctionLeaf(bytes4 selector, bytes32 constraintsHash) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(selector, constraintsHash))));
    }

    /**
     * @dev Builds `(root, proof)` for a policy at `targetIndex`.
     */
    function _buildPolicyRootAndProof(uint256[] memory policyIds, Policy[] memory policies, uint256 targetIndex)
        internal
        returns (bytes32 root, bytes32[] memory proof)
    {
        bytes32[] memory leaves = new bytes32[](policies.length);
        for (uint256 i = 0; i < policies.length; i++) {
            leaves[i] = _computePolicyLeaf(policyIds[i], policies[i]);
        }
        if (leaves.length == 1) {
            root = leaves[0];
            proof = new bytes32[](0);
            return (root, proof);
        }

        root = merkle.getRoot(leaves);
        proof = merkle.getProof(leaves, targetIndex);
    }

    /**
     * @dev Builds `(root, proof)` for an address tree at `targetIndex`.
     */
    function _buildAddressRootAndProof(address[] memory values, uint256 targetIndex)
        internal
        returns (bytes32 root, bytes32[] memory proof)
    {
        bytes32[] memory leaves = new bytes32[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            leaves[i] = MerkleUtils.computeAddressLeaf(values[i]);
        }
        if (leaves.length == 1) {
            root = leaves[0];
            proof = new bytes32[](0);
            return (root, proof);
        }

        root = merkle.getRoot(leaves);
        proof = merkle.getProof(leaves, targetIndex);
    }

    /**
     * @dev Builds `(root, proof)` for function-selector+constraints entries.
     */
    function _buildFunctionRootAndProof(bytes4[] memory selectors, bytes[] memory constraintsList, uint256 targetIndex)
        internal
        returns (bytes32 root, bytes32[] memory proof)
    {
        bytes32[] memory leaves = new bytes32[](selectors.length);
        for (uint256 i = 0; i < selectors.length; i++) {
            leaves[i] = _computeFunctionLeaf(selectors[i], keccak256(constraintsList[i]));
        }
        if (leaves.length == 1) {
            root = leaves[0];
            proof = new bytes32[](0);
            return (root, proof);
        }

        root = merkle.getRoot(leaves);
        proof = merkle.getProof(leaves, targetIndex);
    }

    /**
     * @dev Builds admin auth params for `OrganizationPolicyBase.setPolicies`.
     */
    function _buildSetPoliciesAuth(
        bytes32 newPoliciesRoot,
        string memory ipfsCid,
        uint256 salt,
        uint256 expirationTimestamp,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = abi.encode(newPoliciesRoot, keccak256(bytes(ipfsCid)));
        auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyPolicies,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Computes nonce for `setPolicies` operation-data payload.
     */
    function _computeSetPoliciesNonce(bytes memory operationData, uint256 salt) internal view returns (uint256) {
        return policyStateHarness.computeNonce(OperationType.ModifyPolicies, operationData, salt);
    }

    /**
     * @dev Encodes ERC-20 `transfer(address,uint256)` calldata.
     */
    function _encodeErc20Transfer(address to, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
    }

    /**
     * @dev Encodes ERC-20 `approve(address,uint256)` calldata.
     */
    function _encodeErc20Approve(address spender, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IERC20.approve.selector, spender, amount);
    }

    /**
     * @dev Encodes ERC-20 `transferFrom(address,address,uint256)` calldata.
     */
    function _encodeErc20TransferFrom(address from, address to, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount);
    }

    /**
     * @dev Encodes a one-element `ParameterConstraint[]` payload.
     */
    function _encodeSingleConstraint(ParameterConstraint memory constraint) internal pure returns (bytes memory) {
        ParameterConstraint[] memory constraints = new ParameterConstraint[](1);
        constraints[0] = constraint;
        return abi.encode(constraints);
    }
}
