// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {
    LibOrganizationAdminOperationTimelockStorage
} from "organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {AccountImplementationHarness} from "test/account/AccountImplementationHarness.sol";
import {ImplementationWhitelistMock} from "test/organization/shared/OrganizationAccountFactoryMocks.sol";
import {ContractType, GroupModification, InitializationParams} from "types/CommonTypes.sol";
import {TxRecoveryState} from "types/RecoveryTypes.sol";

contract LibOrganizationInitializationTxRecoveryHarness {
    function initialize(InitializationParams calldata params) external {
        LibOrganizationInitialization.initialize(params);
    }

    function setWhitelistAddress(address whitelistAddress) external {
        LibOrganizationUpgradeStorage.layout().whitelistAddress = whitelistAddress;
    }

    function getTxRecoveryState() external view returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }

    function getAdminOperationTimelockDurationSeconds() external view returns (uint256) {
        return LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds;
    }
}

contract LibOrganizationInitializationTxRecoveryBranchTest is Test {
    address internal constant MEMBER = address(0xA1101);
    address internal constant GUARDIAN = address(0xA1102);
    address internal constant TX_RECOVERY = address(0xA1103);

    ImplementationWhitelistMock internal whitelist;
    AccountImplementationHarness internal accountImplementation;
    LibOrganizationInitializationTxRecoveryHarness internal harness;

    function setUp() public {
        whitelist = new ImplementationWhitelistMock();
        accountImplementation = new AccountImplementationHarness();
        whitelist.setImplementationWhitelisted(ContractType.Account, address(accountImplementation), true);

        harness = _deployHarness();
    }

    function _deployHarness() internal returns (LibOrganizationInitializationTxRecoveryHarness deployedHarness) {
        deployedHarness = new LibOrganizationInitializationTxRecoveryHarness();
        deployedHarness.setWhitelistAddress(address(whitelist));
    }

    function _buildParams(address recoveryAddress, uint256 txRecoveryTimelock, uint256 adminOpTimelock)
        internal
        view
        returns (InitializationParams memory params)
    {
        address[] memory members = new address[](1);
        members[0] = MEMBER;

        address[] memory admins = new address[](1);
        admins[0] = MEMBER;

        GroupModification[] memory groups = new GroupModification[](0);

        params = InitializationParams({
            members: members,
            admins: admins,
            votingThreshold: 1,
            groups: groups,
            guardian: GUARDIAN,
            accountImplementation: address(accountImplementation),
            adminOperationTimelockDurationSeconds: adminOpTimelock,
            transactionAndERC1271RecoveryAddress: recoveryAddress,
            txRecoveryTimelockDurationSeconds: txRecoveryTimelock,
            guardianRecoveryAddress: address(0),
            guardianRecoveryTimelockDurationSeconds: 0
        });
    }

    /// @dev Verifies LOI-REC-2 and LOI-REC-3: non-zero tx recovery address + valid timelock configures tx recovery
    /// and keeps it disabled at init.
    function test_LOI_REC_2__LOI_REC_3_initialize_nonZeroRecoveryAndValidTimelock_configuresTxRecovery() public {
        // Setup
        InitializationParams memory params =
            _buildParams(TX_RECOVERY, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS + 1, 3 days);

        // Call
        harness.initialize(params);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, TX_RECOVERY, "recovery address should be configured");
        assertEq(
            state.timelockDurationSeconds,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS + 1,
            "timelock should match initialization params"
        );
        assertFalse(state.isEnabled, "init should not auto-enable tx recovery");
    }

    /// @dev Verifies LOI-REC-7: tx recovery timelock min boundary is accepted at initialization and remains disabled.
    function test_INIT_STATE_7_A_LOI_REC_7_initialize_nonZeroRecoveryAndMinBoundaryTimelock_configuresTxRecovery()
        public
    {
        // Setup
        InitializationParams memory params =
            _buildParams(TX_RECOVERY, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, 3 days);

        // Call
        harness.initialize(params);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(
            state.timelockDurationSeconds,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            "min boundary timelock should be accepted"
        );
        assertFalse(state.isEnabled, "tx recovery should remain disabled at min timelock boundary");
    }

    /// @dev Verifies LOI-REC-8: tx recovery timelock max boundary is accepted at initialization and remains disabled.
    function test_INIT_STATE_7_B_LOI_REC_8_initialize_nonZeroRecoveryAndMaxBoundaryTimelock_configuresTxRecovery()
        public
    {
        // Setup
        InitializationParams memory params =
            _buildParams(TX_RECOVERY, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS, 3 days);

        // Call
        harness.initialize(params);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(
            state.timelockDurationSeconds,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
            "max boundary timelock should be accepted"
        );
        assertFalse(state.isEnabled, "tx recovery should remain disabled at max timelock boundary");
    }

    /// @dev Verifies LOI-REC-10: zero tx recovery address keeps tx recovery deferred and disabled.
    function test_LOI_REC_10_initialize_zeroRecoveryAddress_keepsTxRecoveryDeferredAndDisabled() public {
        // Setup
        InitializationParams memory params =
            _buildParams(address(0), TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, 3 days);

        // Call
        harness.initialize(params);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, address(0), "deferred init should keep recovery address unset");
        assertEq(state.timelockDurationSeconds, 0, "deferred init should keep timelock unset");
        assertFalse(state.isEnabled, "deferred init must not auto-enable tx recovery");
    }

    /// @dev Verifies LOI-VAL-14: non-zero tx recovery address with invalid tx-recovery timelock reverts init.
    function test_LOI_VAL_14_initialize_nonZeroRecoveryAddress_invalidTxRecoveryTimelock_reverts() public {
        // Setup
        InitializationParams memory params =
            _buildParams(TX_RECOVERY, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1, 3 days);

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initialize(params);

        // Verify
    }

    /// @dev Verifies LOI-VAL-11 and LOI-VAL-12: invalid admin-op timelock always reverts init, preventing a
    /// same-window deferred tx-recovery finalize path.
    function test_INIT_STATE_7_C_LOI_VAL_11__LOI_VAL_12_initialize_invalidAdminOperationTimelock_revertsAndPreventsDeferredFinalizeWindow()
        public
    {
        // Setup
        LibOrganizationInitializationTxRecoveryHarness harnessZero = _deployHarness();
        LibOrganizationInitializationTxRecoveryHarness harnessBelowMin = _deployHarness();
        LibOrganizationInitializationTxRecoveryHarness harnessAboveMax = _deployHarness();

        // Call
        InitializationParams memory zeroParams =
            _buildParams(address(0), TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harnessZero.initialize(zeroParams);

        InitializationParams memory belowMinParams = _buildParams(
            address(0), TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harnessBelowMin.initialize(belowMinParams);

        InitializationParams memory aboveMaxParams = _buildParams(
            address(0), TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harnessAboveMax.initialize(aboveMaxParams);

        // Verify
        assertEq(
            harnessZero.getTxRecoveryState().pendingInit.pendingTimestamp,
            0,
            "failed init should not stage deferred tx recovery"
        );
        assertEq(
            harnessBelowMin.getTxRecoveryState().pendingInit.pendingTimestamp,
            0,
            "failed init should not open deferred-finalize window"
        );
        assertEq(
            harnessAboveMax.getTxRecoveryState().pendingInit.pendingTimestamp,
            0,
            "failed init should not stage deferred tx recovery"
        );
    }

    /// @dev Verifies LOI-REC-10: when recovery address is zero, tx-recovery timelock is not validated at init-time.
    function test_LOI_REC_10_initialize_zeroRecoveryAddress_doesNotValidateTxRecoveryTimelock() public {
        // Setup
        InitializationParams memory params = _buildParams(address(0), 0, 3 days);

        // Call
        harness.initialize(params);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, address(0), "tx recovery should remain deferred");
        assertEq(state.timelockDurationSeconds, 0, "deferred tx recovery should keep zero timelock in storage");
        assertEq(
            harness.getAdminOperationTimelockDurationSeconds(),
            3 days,
            "admin-op timelock should still initialize successfully"
        );
    }
}
