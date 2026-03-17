// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {LibOrganizationAdminOperationTimelock} from "organization/libraries/LibOrganizationAdminOperationTimelock.sol";

/**
 * @dev Library-focused harness exposing `LibOrganizationAdminOperationTimelock` helpers.
 */
contract LibOrganizationAdminOperationTimelockHarness {
    /**
     * @dev Exposes `LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock`.
     * @param durationSeconds Timelock duration to validate and persist.
     */
    function initializeViaLibrary(uint256 durationSeconds) external {
        LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock(durationSeconds);
    }

    /**
     * @dev Exposes `LibOrganizationAdminOperationTimelock.getAdminOperationTimelockDurationSeconds`.
     * @return durationSeconds The persisted admin-operation timelock duration.
     */
    function getDurationViaLibrary() external view returns (uint256 durationSeconds) {
        return LibOrganizationAdminOperationTimelock.getAdminOperationTimelockDurationSeconds();
    }

    /**
     * @dev Exposes `LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert`.
     * @param canFinalizeAtTimestamp Timestamp being checked against `block.timestamp`.
     */
    function validateExpiredOrRevertViaLibrary(uint256 canFinalizeAtTimestamp) external view {
        LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert(canFinalizeAtTimestamp);
    }

    /**
     * @dev Exposes `LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp`.
     * @return canFinalizeAtTimestamp Current `block.timestamp + configuredDuration`.
     */
    function computeCanFinalizeAtTimestampViaLibrary() external view returns (uint256 canFinalizeAtTimestamp) {
        return LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp();
    }
}

/**
 * @dev Fuzz tests for `LibOrganizationAdminOperationTimelock`.
 */
contract LibOrganizationAdminOperationTimelockFuzzTest is Test {
    /// @dev Library harness under test.
    LibOrganizationAdminOperationTimelockHarness internal harness;

    /**
     * @dev Deploys a fresh library harness before each test.
     */
    function setUp() public {
        harness = new LibOrganizationAdminOperationTimelockHarness();
    }

    /**
     * @dev Configures the exact invalid-timelock revert expected from `TimelockUtils`.
     * @param durationSeconds Timelock duration that should be rejected.
     */
    function _expectInvalidTimelockDuration(uint256 durationSeconds) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                durationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock` accepts the minimum
    /// boundary and persists it exactly.
    function test_initializeAdminOperationTimelock_minBoundaryAcceptedAndStoredExactly() public {
        // Setup: start from a fresh harness with zeroed timelock storage.

        // Call: initialize the library harness with the minimum valid admin-operation timelock.
        harness.initializeViaLibrary(TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);

        // Verify: the persisted duration matches the minimum boundary exactly with no rounding.
        assertEq(
            harness.getDurationViaLibrary(),
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            "min-boundary duration should persist exactly"
        );
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock` accepts the maximum
    /// boundary and persists it exactly.
    function test_initializeAdminOperationTimelock_maxBoundaryAcceptedAndStoredExactly() public {
        // Setup: start from a fresh harness with zeroed timelock storage.

        // Call: initialize the library harness with the maximum valid admin-operation timelock.
        harness.initializeViaLibrary(TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);

        // Verify: the persisted duration matches the maximum boundary exactly.
        assertEq(
            harness.getDurationViaLibrary(),
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
            "max-boundary duration should persist exactly"
        );
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock` rejects durations below
    /// the minimum boundary.
    function test_initializeAdminOperationTimelock_belowMinimumRevertsInvalidTimelockDuration() public {
        // Setup: choose a duration one second below the allowed minimum.
        uint256 invalidDuration = TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1;

        // Call: initialize the library harness with the below-minimum duration.
        _expectInvalidTimelockDuration(invalidDuration);
        harness.initializeViaLibrary(invalidDuration);

        // Verify: failed initialization leaves storage unchanged at zero.
        assertEq(harness.getDurationViaLibrary(), 0, "below-minimum init should not persist a value");
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock` rejects durations above
    /// the maximum boundary.
    function test_initializeAdminOperationTimelock_aboveMaximumRevertsInvalidTimelockDuration() public {
        // Setup: choose a duration one second above the allowed maximum.
        uint256 invalidDuration = TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1;

        // Call: initialize the library harness with the above-maximum duration.
        _expectInvalidTimelockDuration(invalidDuration);
        harness.initializeViaLibrary(invalidDuration);

        // Verify: failed initialization leaves storage unchanged at zero.
        assertEq(harness.getDurationViaLibrary(), 0, "above-maximum init should not persist a value");
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock` overwrites the stored
    /// duration on repeated harness calls.
    function test_initializeAdminOperationTimelock_repeatedCallsOverwriteStoredDuration() public {
        // Setup: seed one valid duration before exercising the raw repeated-initialize behavior.
        harness.initializeViaLibrary(TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);

        // Call: initialize the same harness again with a different valid duration.
        harness.initializeViaLibrary(TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);

        // Verify: the latest duration overwrites the earlier value and the getter returns the new value.
        assertEq(
            harness.getDurationViaLibrary(),
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
            "repeated initialize should overwrite the stored duration"
        );
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.getAdminOperationTimelockDurationSeconds` returns zero in
    /// uninitialized harness storage.
    function test_getAdminOperationTimelockDurationSeconds_uninitializedStateReturnsZero() public view {
        // Setup: use a fresh harness with zeroed timelock storage.

        // Call: read the admin-operation timelock duration before initialization.
        uint256 durationSeconds = harness.getDurationViaLibrary();

        // Verify: the getter reports zero from uninitialized storage.
        assertEq(durationSeconds, 0, "uninitialized getter should return zero");
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.getAdminOperationTimelockDurationSeconds` returns the
    /// configured duration after initialization.
    function test_getAdminOperationTimelockDurationSeconds_returnsConfiguredDuration() public {
        // Setup: initialize the harness with a valid non-boundary duration.
        uint256 configuredDuration = 7 days;
        harness.initializeViaLibrary(configuredDuration);

        // Call: read the configured admin-operation timelock duration.
        uint256 durationSeconds = harness.getDurationViaLibrary();

        // Verify: the getter returns the persisted configured duration exactly.
        assertEq(durationSeconds, configuredDuration, "getter should return the configured duration");
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert` reverts before expiry
    /// with the expected revert payload values.
    function test_validateTimelockExpiredOrRevert_beforeExpiryRevertsWithExactPayload() public {
        // Setup: choose a future finalize timestamp one second ahead of the current block timestamp.
        uint256 canFinalizeAtTimestamp = block.timestamp + 1;

        // Call: validate the still-pending finalize timestamp against the current block.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAtTimestamp, block.timestamp
            )
        );
        harness.validateExpiredOrRevertViaLibrary(canFinalizeAtTimestamp);

        // Verify: the helper reverts only with the exact expected timestamp payload.
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert` succeeds when
    /// `block.timestamp` equals the pending finalize timestamp.
    function test_validateTimelockExpiredOrRevert_exactExpirySucceeds() public {
        // Setup: choose a finalize timestamp equal to the current block timestamp.
        uint256 canFinalizeAtTimestamp = block.timestamp;

        // Call: validate the exact-boundary finalize timestamp.
        harness.validateExpiredOrRevertViaLibrary(canFinalizeAtTimestamp);

        // Verify: the helper returns successfully at the exact expiry boundary.
        assertTrue(true, "exact-expiry validation should succeed");
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert` succeeds after expiry.
    function test_validateTimelockExpiredOrRevert_afterExpirySucceeds() public {
        // Setup: choose a finalize timestamp strictly before the current block timestamp.
        uint256 canFinalizeAtTimestamp = block.timestamp - 1;

        // Call: validate the already-expired finalize timestamp.
        harness.validateExpiredOrRevertViaLibrary(canFinalizeAtTimestamp);

        // Verify: the helper returns successfully after expiry.
        assertTrue(true, "post-expiry validation should succeed");
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert` treats a zero timestamp
    /// as already expired.
    function test_validateTimelockExpiredOrRevert_zeroTimestampSucceeds() public {
        // Setup: use the documented zero-timestamp helper case.

        // Call: validate a zero finalize timestamp.
        harness.validateExpiredOrRevertViaLibrary(0);

        // Verify: the helper succeeds because zero is never greater than the current block timestamp.
        assertTrue(true, "zero finalize timestamp should be treated as already expired");
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp` returns `block.timestamp +
    /// duration` for a configured non-boundary timelock.
    function test_computeCanFinalizeAtTimestamp_returnsBlockTimestampPlusConfiguredDuration() public {
        // Setup: configure a valid non-boundary duration and precompute the expected finalize timestamp.
        uint256 configuredDuration = 9 days;
        uint256 expectedCanFinalizeAtTimestamp = block.timestamp + configuredDuration;
        harness.initializeViaLibrary(configuredDuration);

        // Call: compute the finalize timestamp through the library harness.
        uint256 canFinalizeAtTimestamp = harness.computeCanFinalizeAtTimestampViaLibrary();

        // Verify: the computed finalize timestamp equals the current block timestamp plus the configured duration.
        assertEq(
            canFinalizeAtTimestamp,
            expectedCanFinalizeAtTimestamp,
            "computed finalize timestamp should match block.timestamp + configured duration"
        );
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp` uses the minimum boundary
    /// duration exactly.
    function test_computeCanFinalizeAtTimestamp_minBoundaryReturnsExactTimestamp() public {
        // Setup: configure the minimum valid timelock duration and precompute the expected finalize timestamp.
        uint256 expectedCanFinalizeAtTimestamp = block.timestamp + TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS;
        harness.initializeViaLibrary(TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);

        // Call: compute the finalize timestamp at the minimum boundary.
        uint256 canFinalizeAtTimestamp = harness.computeCanFinalizeAtTimestampViaLibrary();

        // Verify: the computed timestamp matches the exact minimum-boundary offset.
        assertEq(
            canFinalizeAtTimestamp,
            expectedCanFinalizeAtTimestamp,
            "minimum-boundary finalize timestamp should be exact"
        );
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp` uses the maximum boundary
    /// duration exactly.
    function test_computeCanFinalizeAtTimestamp_maxBoundaryReturnsExactTimestamp() public {
        // Setup: configure the maximum valid timelock duration and precompute the expected finalize timestamp.
        uint256 expectedCanFinalizeAtTimestamp = block.timestamp + TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS;
        harness.initializeViaLibrary(TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);

        // Call: compute the finalize timestamp at the maximum boundary.
        uint256 canFinalizeAtTimestamp = harness.computeCanFinalizeAtTimestampViaLibrary();

        // Verify: the computed timestamp matches the exact maximum-boundary offset.
        assertEq(
            canFinalizeAtTimestamp,
            expectedCanFinalizeAtTimestamp,
            "maximum-boundary finalize timestamp should be exact"
        );
    }

    /// @dev Verifies `LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp` returns the current block
    /// timestamp when the stored duration is zero.
    function test_computeCanFinalizeAtTimestamp_uninitializedStateReturnsCurrentTimestamp() public {
        // Setup: use a fresh harness where the stored admin-operation timelock remains zero.

        // Call: compute the finalize timestamp without prior initialization.
        uint256 canFinalizeAtTimestamp = harness.computeCanFinalizeAtTimestampViaLibrary();

        // Verify: zero stored duration produces the current block timestamp exactly.
        assertEq(canFinalizeAtTimestamp, block.timestamp, "zero-duration compute should return block.timestamp");
    }
}
