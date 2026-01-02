// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationPolicyStorage } from "./storage/LibOrganizationPolicyStorage.sol";
import { LibOrganizationMembersStorage } from "./storage/LibOrganizationMembersStorage.sol";
import { LibOrganizationGroupsStorage } from "./storage/LibOrganizationGroupsStorage.sol";
import { LibOrganizationWhitelistStorage } from "./storage/LibOrganizationWhitelistStorage.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Organization Policy
 * @notice Library for merkle-based policy operations
 * @author Den Technologies Inc
 */
library LibOrganizationPolicy {
    event PoliciesUpdated(bytes32 indexed newRoot, string ipfsCid);

    error MalformedTokenTransfer();
    error PolicyVerificationFailed();

    // ================================
    // MERKLE HELPERS
    // ================================

    function _computePolicyLeaf(uint256 policyId, Policies.Policy calldata policy) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
    }

    function _computeAddressLeaf(address addr) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(addr))));
    }

    function _computeFunctionLeaf(bytes4 selector, bytes32 constraintsHash) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(selector, constraintsHash))));
    }

    // ================================
    // POLICY VERIFICATION
    // ================================

    function policyExists(
        uint256 policyId,
        Policies.Policy calldata policy,
        bytes32[] calldata proof
    )
        internal
        view
        returns (bool)
    {
        bytes32 root = LibOrganizationPolicyStorage.layout().policiesRoot;
        bytes32 leaf = _computePolicyLeaf(policyId, policy);
        return MerkleProof.verify(proof, root, leaf);
    }

    function policyExistsMemory(
        uint256 policyId,
        Policies.Policy memory policy,
        bytes32[] memory proof
    )
        internal
        view
        returns (bool)
    {
        bytes32 root = LibOrganizationPolicyStorage.layout().policiesRoot;
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
        return MerkleProof.verify(proof, root, leaf);
    }

    // ================================
    // MODIFY POLICIES
    // ================================

    function modifyPolicies(bytes32 newPoliciesRoot, string calldata ipfsCid) internal {
        LibOrganizationPolicyStorage.layout().policiesRoot = newPoliciesRoot;
        emit PoliciesUpdated(newPoliciesRoot, ipfsCid);
    }

    // ================================
    // POLICY VALIDATION
    // ================================

    function doesPolicyApplyToTransaction(
        uint256 policyId,
        address sourceAccount,
        address to,
        uint256 value,
        bytes calldata data,
        address initiator,
        Policies.ValidationProofs calldata proofs
    )
        internal
        view
        returns (bool)
    {
        bytes32 policyLeaf = _computePolicyLeaf(policyId, proofs.policy);
        bytes32 root = LibOrganizationPolicyStorage.layout().policiesRoot;
        if (!MerkleProof.verify(proofs.policyProof, root, policyLeaf)) {
            return false;
        }

        if (!_doesMatchSourceAccount(proofs.policy, sourceAccount, proofs.sourceAccountProof)) {
            return false;
        }

        if (!_doesMatchInitiator(proofs.policy, initiator)) {
            return false;
        }

        if (!_doesMatchTransactionType(proofs.policy, to, value, data, proofs.functionProof, proofs.constraints)) {
            return false;
        }

        if (!_doesMatchDestination(proofs.policy, to, value, data, proofs.destinationProof)) {
            return false;
        }

        return true;
    }

    // ================================
    // FILTER MATCHING
    // ================================

    function _doesMatchSourceAccount(
        Policies.Policy calldata policy,
        address sourceAccount,
        bytes32[] calldata sourceAccountProof
    )
        private
        pure
        returns (bool)
    {
        if (Policies.anySourceAccountCalldata(policy)) return true;

        bytes32 accountLeaf = _computeAddressLeaf(sourceAccount);
        return MerkleProof.verify(sourceAccountProof, policy.roots.sourceAccountsRoot, accountLeaf);
    }

    function _doesMatchInitiator(
        Policies.Policy calldata policy,
        address initiatorAddress
    )
        private
        view
        returns (bool)
    {
        if (Policies.anyInitiatorCalldata(policy)) return true;

        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[initiatorAddress];

        if (memberId == 0) return false;

        Policies.ApproverType initType = Policies.initiatorTypeCalldata(policy);
        uint8 initId = Policies.initiatorIdCalldata(policy);

        if (initType == Policies.ApproverType.Member) {
            return memberId == initId;
        }

        if (initType == Policies.ApproverType.Group) {
            return _isMemberInGroup(initiatorAddress, initId);
        }

        return false;
    }

    function _doesMatchInitiatorMemory(
        Policies.Policy memory policy,
        address initiatorAddress
    )
        private
        view
        returns (bool)
    {
        if (Policies.anyInitiator(policy)) return true;

        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[initiatorAddress];

        if (memberId == 0) return false;

        Policies.ApproverType initType = Policies.initiatorType(policy);
        uint8 initId = Policies.initiatorId(policy);

        if (initType == Policies.ApproverType.Member) {
            return memberId == initId;
        }

        if (initType == Policies.ApproverType.Group) {
            return _isMemberInGroup(initiatorAddress, initId);
        }

        return false;
    }

    function _doesMatchTransactionType(
        Policies.Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints
    )
        private
        pure
        returns (bool)
    {
        Policies.TransactionType txType = Policies.transactionTypeCalldata(policy);

        if (txType == Policies.TransactionType.Any) return true;

        if (txType == Policies.TransactionType.TokenTransfers) {
            if (!isTransactionTokenTransfer(data, value)) return false;

            if (!Policies.anyTokenCalldata(policy)) {
                address transferToken = extractTokenAddress(to, data);
                if (transferToken != policy.config.tokenAddress) return false;
            }

            if (Policies.hasAmountThresholdCalldata(policy)) {
                uint256 amount = extractTransferAmount(data, value);
                if (amount >= policy.config.amountThreshold) return false;
            }

            return true;
        }

        if (txType == Policies.TransactionType.ContractInteractions) {
            if (isTransactionTokenTransfer(data, value)) return false;

            if (!_doesMatchFunction(policy, data, functionProof, constraints)) {
                return false;
            }

            return true;
        }

        return true;
    }

    function _doesMatchDestination(
        Policies.Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata destinationProof
    )
        private
        view
        returns (bool)
    {
        Policies.DestinationType destType = Policies.destinationTypeCalldata(policy);

        if (destType == Policies.DestinationType.Any) return true;

        address actualDestination = getActualDestination(to, data, value);

        if (destType == Policies.DestinationType.WhitelistedOnly) {
            return _isAddressWhitelisted(actualDestination);
        }

        if (destType == Policies.DestinationType.NonWhitelistedOnly) {
            return !_isAddressWhitelisted(actualDestination);
        }

        if (destType == Policies.DestinationType.CustomList) {
            bytes32 destLeaf = _computeAddressLeaf(actualDestination);
            return MerkleProof.verify(destinationProof, policy.roots.customDestinationsRoot, destLeaf);
        }

        return false;
    }

    function _doesMatchFunction(
        Policies.Policy calldata policy,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints
    )
        private
        pure
        returns (bool)
    {
        if (Policies.anyFunctionCalldata(policy)) return true;
        if (data.length < 4) return false;

        bytes4 selector = bytes4(data[:4]);
        bytes32 constraintsHash = keccak256(constraints);

        bytes32 funcLeaf = _computeFunctionLeaf(selector, constraintsHash);
        if (!MerkleProof.verify(functionProof, policy.roots.allowedFunctionsRoot, funcLeaf)) {
            return false;
        }

        return doParametersMatchConstraints(constraints, data);
    }

    // ================================
    // APPROVER HELPERS
    // ================================

    function getRequiredApprovals(Policies.Policy calldata policy) internal pure returns (uint256) {
        if (Policies.approverTypeCalldata(policy) == Policies.ApproverType.Member) {
            return 1;
        }
        return Policies.approvalThresholdCalldata(policy);
    }

    function getRequiredApprovalsMemory(Policies.Policy memory policy) internal pure returns (uint256) {
        if (Policies.approverType(policy) == Policies.ApproverType.Member) {
            return 1;
        }
        return Policies.approvalThreshold(policy);
    }

    function isSignerAuthorizedForPolicy(
        Policies.Policy calldata policy,
        address signer
    )
        internal
        view
        returns (bool)
    {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[signer];

        if (memberId == 0) return false;

        Policies.ApproverType appType = Policies.approverTypeCalldata(policy);
        uint8 appId = Policies.approverIdCalldata(policy);

        if (appType == Policies.ApproverType.Member) {
            return memberId == appId;
        }

        if (appType == Policies.ApproverType.Group) {
            return _isMemberInGroup(memberId, appId);
        }

        return false;
    }

    function isSignerAuthorizedForPolicyMemory(
        Policies.Policy memory policy,
        address signer
    )
        internal
        view
        returns (bool)
    {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[signer];

        if (memberId == 0) return false;

        Policies.ApproverType appType = Policies.approverType(policy);
        uint8 appId = Policies.approverId(policy);

        if (appType == Policies.ApproverType.Member) {
            return memberId == appId;
        }

        if (appType == Policies.ApproverType.Group) {
            return _isMemberInGroup(memberId, appId);
        }

        return false;
    }

    function doesTransactionMatchPolicyInitiator(
        Policies.Policy calldata policy,
        address initiatorAddress
    )
        internal
        view
        returns (bool)
    {
        return _doesMatchInitiator(policy, initiatorAddress);
    }

    function doesTransactionMatchPolicyInitiatorMemory(
        Policies.Policy memory policy,
        address initiatorAddress
    )
        internal
        view
        returns (bool)
    {
        return _doesMatchInitiatorMemory(policy, initiatorAddress);
    }

    function getValidApprovals(
        Policies.Policy calldata policy,
        bytes memory signatures,
        bytes32 messageHash
    )
        internal
        view
        returns (uint8)
    {
        if (signatures.length == 0) return 0;

        uint8 signatureCount = uint8(signatures.length / 65);
        uint8 validApprovals = 0;
        address lastSigner = address(0);

        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);
            address signer = LibOrganizationSignatures.extractSigner(signature);

            if (signer == address(0)) continue;
            if (signer <= lastSigner) continue;

            lastSigner = signer;

            if (!SignatureChecker.isValidSignatureNow(signer, messageHash, signature)) {
                continue;
            }

            if (isSignerAuthorizedForPolicy(policy, signer)) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    function getValidApprovalsMemory(
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 messageHash
    )
        internal
        view
        returns (uint8)
    {
        if (signatures.length == 0) return 0;

        uint8 signatureCount = uint8(signatures.length / 65);
        uint8 validApprovals = 0;
        address lastSigner = address(0);

        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);
            address signer = LibOrganizationSignatures.extractSigner(signature);

            if (signer == address(0)) continue;
            if (signer <= lastSigner) continue;

            lastSigner = signer;

            if (!SignatureChecker.isValidSignatureNow(signer, messageHash, signature)) {
                continue;
            }

            if (isSignerAuthorizedForPolicyMemory(policy, signer)) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    // ================================
    // TRANSACTION HELPERS
    // ================================

    function getActualDestination(address to, bytes calldata data, uint256 value) internal pure returns (address) {
        if (data.length == 0) return to;
        if (!isTransactionTokenTransfer(data, value)) return to;
        return extractTokenRecipient(data);
    }

    function extractTokenRecipient(bytes calldata data) internal pure returns (address) {
        if (data.length < 36) return address(0);

        bytes4 selector = bytes4(data[:4]);

        if (selector == bytes4(keccak256("transfer(address,uint256)"))) {
            return address(bytes20(data[16:36]));
        }

        if (selector == bytes4(keccak256("transferFrom(address,address,uint256)"))) {
            if (data.length < 68) return address(0);
            return address(bytes20(data[48:68]));
        }

        return address(0);
    }

    function isTransactionTokenTransfer(bytes calldata data, uint256 value) internal pure returns (bool) {
        if (data.length == 0 && value > 0) return true;
        if (data.length < 4) return false;
        if (value > 0) return false;

        bytes4 selector = bytes4(data[:4]);

        return selector == bytes4(keccak256("transfer(address,uint256)"))
            || selector == bytes4(keccak256("transferFrom(address,address,uint256)"));
    }

    function extractTokenAddress(address to, bytes calldata data) internal pure returns (address) {
        if (data.length == 0) return address(0);
        return to;
    }

    function extractTransferAmount(bytes calldata data, uint256 value) internal pure returns (uint256) {
        if (data.length == 0) return value;
        if (data.length < 68) revert MalformedTokenTransfer();
        return uint256(bytes32(data[36:68]));
    }

    // ================================
    // PARAMETER CONSTRAINTS
    // ================================

    function doParametersMatchConstraints(
        bytes calldata parameterConstraints,
        bytes calldata data
    )
        internal
        pure
        returns (bool)
    {
        if (parameterConstraints.length == 0) return true;

        Policies.ParameterConstraint[] memory constraints =
            abi.decode(parameterConstraints, (Policies.ParameterConstraint[]));

        if (constraints.length == 0) return true;

        uint256 paramOffset = 4;

        for (uint256 i = 0; i < constraints.length; ++i) {
            Policies.ParameterConstraint memory constraint = constraints[i];

            uint256 slotsToSkip = uint256(constraint.slotsToSkip);
            if (slotsToSkip == 0) return false;
            uint256 bytesToSkip = slotsToSkip * 32;

            if (constraint.constraintType == Policies.ConstraintType.Any) {
                paramOffset += bytesToSkip;
                continue;
            }

            if (slotsToSkip > 1) return false;
            if (data.length < paramOffset + 32) return false;

            bytes32 paramHeadValue = bytes32(data[paramOffset:paramOffset + 32]);

            if (!_validateParameter(constraint, paramHeadValue, data)) {
                return false;
            }

            paramOffset += bytesToSkip;
        }

        return true;
    }

    function _validateParameter(
        Policies.ParameterConstraint memory constraint,
        bytes32 paramHeadValue,
        bytes calldata data
    )
        private
        pure
        returns (bool)
    {
        Policies.ParamType pType = constraint.paramType;
        Policies.ConstraintType cType = constraint.constraintType;
        bytes memory comparisonData = constraint.comparisonData;

        if (pType == Policies.ParamType.Bool) {
            if (cType != Policies.ConstraintType.Exact) return false;
            return (uint256(paramHeadValue) != 0) == abi.decode(comparisonData, (bool));
        }

        if (pType == Policies.ParamType.Uint) {
            uint256 actualValue = uint256(paramHeadValue);
            if (cType == Policies.ConstraintType.Exact) {
                return actualValue == abi.decode(comparisonData, (uint256));
            }
            if (cType == Policies.ConstraintType.Range) {
                (uint256 minValue, uint256 maxValue) = abi.decode(comparisonData, (uint256, uint256));
                return actualValue >= minValue && actualValue <= maxValue;
            }
            return false;
        }

        if (pType == Policies.ParamType.Int) {
            int256 actualValue = int256(uint256(paramHeadValue));
            if (cType == Policies.ConstraintType.Exact) {
                return actualValue == abi.decode(comparisonData, (int256));
            }
            if (cType == Policies.ConstraintType.Range) {
                (int256 minValue, int256 maxValue) = abi.decode(comparisonData, (int256, int256));
                return actualValue >= minValue && actualValue <= maxValue;
            }
            return false;
        }

        if (pType == Policies.ParamType.Address) {
            address actualValue = address(uint160(uint256(paramHeadValue)));
            if (cType == Policies.ConstraintType.Exact) {
                return actualValue == abi.decode(comparisonData, (address));
            }
            if (cType == Policies.ConstraintType.List) {
                address[] memory allowedAddresses = abi.decode(comparisonData, (address[]));
                for (uint256 i = 0; i < allowedAddresses.length; ++i) {
                    if (actualValue == allowedAddresses[i]) return true;
                }
                return false;
            }
            return false;
        }

        if (pType == Policies.ParamType.FixedBytes) {
            if (cType != Policies.ConstraintType.Exact) return false;
            return paramHeadValue == abi.decode(comparisonData, (bytes32));
        }

        if (pType == Policies.ParamType.Bytes || pType == Policies.ParamType.String) {
            if (cType != Policies.ConstraintType.Exact) return false;
            uint256 offset = uint256(paramHeadValue);
            uint256 dataPosition = 4 + offset;
            if (data.length < dataPosition + 32) return false;
            uint256 bytesLength = uint256(bytes32(data[dataPosition:dataPosition + 32]));
            if (data.length < dataPosition + 32 + bytesLength) return false;
            bytes32 actualHash = keccak256(data[dataPosition + 32:dataPosition + 32 + bytesLength]);
            return actualHash == abi.decode(comparisonData, (bytes32));
        }

        return false;
    }

    // ================================
    // PRIVATE HELPERS
    // ================================

    function _isMemberInGroup(uint8 memberId, uint8 groupId) private view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();

        if (membersLayout.memberIdToAddress[memberId] == address(0)) return false;

        return groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    function _isMemberInGroup(address memberAddress, uint8 groupId) private view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[memberAddress];

        if (memberId == 0) return false;

        return groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    function _isAddressWhitelisted(address addressToCheck) private view returns (bool) {
        return LibOrganizationWhitelistStorage.layout().whitelistedAddresses[addressToCheck];
    }

    // ================================
    // TIME-BASED LIMITS
    // ================================

    function computeUsageKey(
        uint256 policyId,
        Policies.Policy calldata policy,
        address account,
        address destination,
        address initiator
    )
        internal
        pure
        returns (bytes32)
    {
        address scopedAccount = Policies.timeIntervalSourceScopeCalldata(policy) == Policies.TimeIntervalScope.PerEntity
            ? account
            : address(0);
        address scopedDestination = Policies.timeIntervalDestinationScopeCalldata(policy)
            == Policies.TimeIntervalScope.PerEntity ? destination : address(0);
        address scopedInitiator = Policies.timeIntervalInitiatorScopeCalldata(policy)
            == Policies.TimeIntervalScope.PerEntity ? initiator : address(0);

        return keccak256(abi.encode(policyId, scopedAccount, scopedDestination, scopedInitiator));
    }

    function computeTimeWindow(Policies.Policy calldata policy) internal view returns (uint256) {
        uint16 hours_ = Policies.timeIntervalHoursCalldata(policy);
        if (hours_ == 0) return 0;
        return block.timestamp / (uint256(hours_) * 3600);
    }

    function checkAndUpdateTimeBasedLimit(
        uint256 policyId,
        Policies.Policy calldata policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    )
        internal
        returns (bool withinLimit)
    {
        if (Policies.limitationCalldata(policy) != Policies.PolicyLimitation.TimeInterval) return true;
        if (Policies.timeIntervalHoursCalldata(policy) == 0) return true;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindow(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        if (currentUsage + usageAmount > policy.config.timeIntervalLimit) return false;

        policyLayout.policyUsage[usageKey][timeWindow] = currentUsage + usageAmount;

        return true;
    }

    function getCurrentUsage(
        uint256 policyId,
        Policies.Policy calldata policy,
        address account,
        address destination,
        address initiator
    )
        internal
        view
        returns (uint256)
    {
        if (Policies.limitationCalldata(policy) != Policies.PolicyLimitation.TimeInterval) return 0;
        if (Policies.timeIntervalHoursCalldata(policy) == 0) return 0;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindow(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }

    // ================================
    // MEMORY VERSIONS FOR TESTS
    // ================================

    function computeUsageKeyMemory(
        uint256 policyId,
        Policies.Policy memory policy,
        address account,
        address destination,
        address initiator
    )
        internal
        pure
        returns (bytes32)
    {
        address scopedAccount =
            Policies.timeIntervalSourceScope(policy) == Policies.TimeIntervalScope.PerEntity ? account : address(0);
        address scopedDestination = Policies.timeIntervalDestinationScope(policy)
            == Policies.TimeIntervalScope.PerEntity ? destination : address(0);
        address scopedInitiator =
            Policies.timeIntervalInitiatorScope(policy) == Policies.TimeIntervalScope.PerEntity ? initiator : address(0);

        return keccak256(abi.encode(policyId, scopedAccount, scopedDestination, scopedInitiator));
    }

    function computeTimeWindowMemory(Policies.Policy memory policy) internal view returns (uint256) {
        uint16 hours_ = Policies.timeIntervalHours(policy);
        if (hours_ == 0) return 0;
        return block.timestamp / (uint256(hours_) * 3600);
    }

    function checkAndUpdateTimeBasedLimitMemory(
        uint256 policyId,
        Policies.Policy memory policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    )
        internal
        returns (bool withinLimit)
    {
        if (Policies.limitation(policy) != Policies.PolicyLimitation.TimeInterval) return true;
        if (Policies.timeIntervalHours(policy) == 0) return true;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKeyMemory(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindowMemory(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        if (currentUsage + usageAmount > policy.config.timeIntervalLimit) return false;

        policyLayout.policyUsage[usageKey][timeWindow] = currentUsage + usageAmount;

        return true;
    }

    function getCurrentUsageMemory(
        uint256 policyId,
        Policies.Policy memory policy,
        address account,
        address destination,
        address initiator
    )
        internal
        view
        returns (uint256)
    {
        if (Policies.limitation(policy) != Policies.PolicyLimitation.TimeInterval) return 0;
        if (Policies.timeIntervalHours(policy) == 0) return 0;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKeyMemory(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindowMemory(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }
}
