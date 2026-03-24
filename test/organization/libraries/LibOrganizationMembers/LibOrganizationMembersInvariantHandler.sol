// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ArrayBuilders} from "test/helpers/ArrayBuilders.sol";
import {BitmaskHelpers} from "test/helpers/BitmaskHelpers.sol";
import {
    LibOrganizationMembersHarness
} from "test/organization/libraries/LibOrganizationMembers/LibOrganizationMembersHarness.sol";

/**
 * @dev Stateful invariant handler for `LibOrganizationMembers` invariants.
 *      Mutations are executed through library entry points and invariant-specific probes set violation flags.
 */
contract LibOrganizationMembersInvariantHandler is ArrayBuilders, BitmaskHelpers {
    /// @dev Harness under test.
    LibOrganizationMembersHarness public immutable HARNESS;

    /// @dev Tracked addresses used by stateful mutation methods.
    address[] internal trackedAddresses;

    /// @dev Deterministic sentinel that should remain a non-member throughout stateful execution.
    address public immutable SENTINEL_NON_MEMBER;

    /// @dev Set to true if an idempotent add-existing probe reverts or mutates state unexpectedly.
    bool public addExistingViolation;

    /// @dev Set to true if an idempotent remove-non-member probe reverts or mutates state unexpectedly.
    bool public removeNonMemberViolation;

    /**
     * @dev Initializes harness state with two admins and one extra member candidate.
     */
    constructor(
        LibOrganizationMembersHarness harness_,
        address admin1_,
        address admin2_,
        address member3_,
        address member4_
    ) {
        HARNESS = harness_;
        SENTINEL_NON_MEMBER = address(0xE4E4);

        trackedAddresses.push(admin1_);
        trackedAddresses.push(admin2_);
        trackedAddresses.push(member3_);
        trackedAddresses.push(member4_);

        // Baseline: two admins that are also members, plus one non-admin member candidate.
        HARNESS.setMemberStatus(admin1_, true);
        HARNESS.setMemberStatus(admin2_, true);
        HARNESS.setMemberStatus(member3_, true);
        HARNESS.setMemberStatus(member4_, false);

        HARNESS.setAdminStatus(admin1_, true);
        HARNESS.setAdminStatus(admin2_, true);
        HARNESS.setAdminCount(2);
        HARNESS.setVotingThreshold(1);
    }

    /**
     * @dev Stateful operation: fuzzed add/remove member mutation through library path.
     */
    function mutateMembers(uint8 addMask, uint8 removeMask) external {
        uint256 addLength = _popcountLowerBits(addMask, 4);
        uint256 removeLength = _popcountLowerBits(removeMask, 4);

        address[] memory membersToAdd = new address[](addLength);
        address[] memory membersToRemove = new address[](removeLength);

        uint256 addIndex;
        uint256 removeIndex;
        for (uint256 i = 0; i < trackedAddresses.length; i++) {
            if (((addMask >> i) & 1) == 1) {
                membersToAdd[addIndex] = trackedAddresses[i];
                addIndex++;
            }
            if (((removeMask >> i) & 1) == 1) {
                membersToRemove[removeIndex] = trackedAddresses[i];
                removeIndex++;
            }
        }

        // Use low-level call so expected reverts do not halt invariant exploration.
        (bool success,) =
            address(HARNESS).call(abi.encodeCall(HARNESS.modifyMembersViaLibrary, (membersToAdd, membersToRemove)));
        if (success) {
            // Intentionally no-op: handler absorbs revert/success to keep invariant exploration running.
        }
    }

    /**
     * @dev Stateful operation: fuzzed add/remove admin mutation through library path.
     */
    function mutateAdmins(uint8 addMask, uint8 removeMask, uint8 thresholdSeed) external {
        uint256 addLength = _popcountLowerBits(addMask, 4);
        uint256 removeLength = _popcountLowerBits(removeMask, 4);

        address[] memory adminsToAdd = new address[](addLength);
        address[] memory adminsToRemove = new address[](removeLength);

        uint256 addIndex;
        uint256 removeIndex;
        for (uint256 i = 0; i < trackedAddresses.length; i++) {
            if (((addMask >> i) & 1) == 1) {
                adminsToAdd[addIndex] = trackedAddresses[i];
                addIndex++;
            }
            if (((removeMask >> i) & 1) == 1) {
                adminsToRemove[removeIndex] = trackedAddresses[i];
                removeIndex++;
            }
        }

        uint256 newVotingThreshold = thresholdSeed % 6;
        // Use low-level call so expected reverts do not halt invariant exploration.
        (bool success,) = address(HARNESS)
            .call(abi.encodeCall(HARNESS.modifyAdminsViaLibrary, (adminsToAdd, adminsToRemove, newVotingThreshold)));
        if (success) {
            // Intentionally no-op: handler absorbs revert/success to keep invariant exploration running.
        }
    }

    /**
     * @dev Probe operation: add an existing member and record any violation.
     */
    function exerciseIdempotentAddExisting() external {
        // admin1 is initialized as a member and member-removal guards prevent demotion while admin.
        address existingMember = trackedAddresses[0];
        bool beforeIsMember = HARNESS.isMember(existingMember);
        if (!beforeIsMember) return;

        (bool success,) = address(HARNESS)
            .call(
                abi.encodeCall(HARNESS.modifyMembersViaLibrary, (buildArray(existingMember), buildEmptyAddressArray()))
            );
        bool afterIsMember = HARNESS.isMember(existingMember);

        if (!success || beforeIsMember != afterIsMember) {
            addExistingViolation = true;
        }
    }

    /**
     * @dev Probe operation: remove a deterministic non-member and record any violation.
     */
    function exerciseIdempotentRemoveNonMember() external {
        bool beforeIsMember = HARNESS.isMember(SENTINEL_NON_MEMBER);

        (bool success,) = address(HARNESS)
            .call(
                abi.encodeCall(
                    HARNESS.modifyMembersViaLibrary, (buildEmptyAddressArray(), buildArray(SENTINEL_NON_MEMBER))
                )
            );
        bool afterIsMember = HARNESS.isMember(SENTINEL_NON_MEMBER);

        if (!success || beforeIsMember != afterIsMember) {
            removeNonMemberViolation = true;
        }
    }

    /**
     * @dev Returns tracked address count.
     */
    function trackedAddressCount() external view returns (uint256) {
        return trackedAddresses.length;
    }

    /**
     * @dev Returns tracked address at index.
     */
    function trackedAddressAt(uint256 index) external view returns (address) {
        return trackedAddresses[index];
    }
}
