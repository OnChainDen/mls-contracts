// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationMembersStorage} from "organization/libraries/storage/LibOrganizationMembersStorage.sol";
import {LibOrganizationSignaturesStorage} from "organization/libraries/storage/LibOrganizationSignaturesStorage.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Shared admin test harness state surface.
 *      Contains storage setters/getters and hashing/nonce helpers used by multiple test suites.
 */
contract OrganizationAdminStateHarness {
    /**
     * @dev Sets guardian storage for `onlyGuardian` modifier tests.
     */
    function setGuardian(address guardianAddress) external {
        LibOrganizationGuardianStorage.layout().guardian = guardianAddress;
    }

    /**
     * @dev Sets member status for an address.
     */
    function setMemberStatus(address member, bool isMember) external {
        LibOrganizationMembersStorage.layout().isMember[member] = isMember;
    }

    /**
     * @dev Reads member status for an address.
     */
    function getMemberStatus(address member) external view returns (bool) {
        return LibOrganizationMembersStorage.layout().isMember[member];
    }

    /**
     * @dev Sets admin status for an address.
     */
    function setAdminStatus(address admin, bool isAdmin) external {
        LibOrganizationAdminStorage.layout().isAdmin[admin] = isAdmin;
    }

    /**
     * @dev Reads admin status for an address.
     */
    function getAdminStatus(address admin) external view returns (bool) {
        return LibOrganizationAdminStorage.layout().isAdmin[admin];
    }

    /**
     * @dev Sets admin count storage directly.
     */
    function setAdminCount(uint256 count) external {
        LibOrganizationAdminStorage.layout().adminCount = count;
    }

    /**
     * @dev Sets voting threshold storage directly.
     */
    function setVotingThreshold(uint256 threshold) external {
        LibOrganizationAdminStorage.layout().votingThreshold = threshold;
    }

    /**
     * @dev Sets used nonce storage directly.
     */
    function setUsedNonce(uint256 nonce, bool isUsed) external {
        LibOrganizationSignaturesStorage.layout().usedNonces[nonce] = isUsed;
    }

    /**
     * @dev Reads used nonce status from storage.
     */
    function getUsedNonce(uint256 nonce) external view returns (bool) {
        return LibOrganizationSignaturesStorage.layout().usedNonces[nonce];
    }

    /**
     * @dev Wrapper around nonce computation library.
     */
    function computeNonce(OperationType operationType, bytes calldata operationData, uint256 salt)
        external
        view
        returns (uint256)
    {
        return LibOrganizationSignatures.computeNonce(operationType, operationData, salt);
    }

    /**
     * @dev Exposes internal helper used to compute EIP-712 operation hashes.
     */
    function getAdminOperationHash(
        OperationType operationType,
        bytes calldata operationData,
        uint256 salt,
        uint256 expirationTimestamp,
        bool isApproval
    ) external view returns (bytes32) {
        return LibOrganizationAdmin._getAdminOperationHash(
            operationType, operationData, salt, expirationTimestamp, isApproval
        );
    }

    /**
     * @dev Encodes admin-modification payload exactly as OrganizationAdminBase does.
     */
    function encodeModifyAdminsOperationData(
        address[] calldata adminsToAdd,
        address[] calldata adminsToRemove,
        uint256 newVotingThreshold
    ) external pure returns (bytes memory) {
        return abi.encode(keccak256(abi.encode(adminsToAdd)), keccak256(abi.encode(adminsToRemove)), newVotingThreshold);
    }
}
