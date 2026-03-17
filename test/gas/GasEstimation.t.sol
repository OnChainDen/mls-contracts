// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AccountImplementation} from "account/AccountImplementation.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {OrganizationImplementationHarness} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {
    ContractType,
    GroupModification,
    GroupModificationType,
    InitializationParams,
    OperationType
} from "types/CommonTypes.sol";
import {
    ApprovalConfig,
    ApproverType,
    DestinationType,
    InitiatorConfig,
    Policy,
    PolicyConfig,
    PolicyRoots,
    PolicyType,
    RateLimitConfig,
    RateLimitScope,
    RateLimitType,
    TokenFilter,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

import {Merkle} from "murky/Merkle.sol";

/// @dev Minimal ERC-20 mock that always succeeds for gas estimation of token transfer calldata paths.
contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

/// @dev Minimal target contract for contract-interaction gas estimation.
contract MockTarget {
    uint256 public value;

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}

/**
 * @dev Gas estimation test suite for MLS Wallet operations.
 *      Each test measures gas for exactly one operation or condition using vm.startSnapshotGas / vm.stopSnapshotGas.
 *      Run with: forge snapshot --mt _gas --isolate
 */
contract GasEstimationTest is InitializationSuiteBase, SignatureTestHelpers {
    // ──────────────────────────────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────────────────────────────

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant INITIATE_ACCOUNT_TRANSACTION_TYPEHASH = keccak256(
        "InitiateAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId)"
    );
    bytes32 internal constant REVIEW_ACCOUNT_TRANSACTION_TYPEHASH = keccak256(
        "ReviewAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId,bytes initiatorSignature)"
    );
    bytes32 internal constant ORGANIZATION_NAME_HASH = keccak256("MLSWalletOrganization");
    bytes32 internal constant ORGANIZATION_VERSION_HASH = keccak256("1");

    uint256 internal constant POLICY_ID = 42;
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 2 days;
    uint256 internal constant RECOVERY_TIMELOCK = 2 days;

    uint256 internal constant ADMIN_PK_1 = 0xA11CE;
    uint256 internal constant ADMIN_PK_2 = 0xB0B;
    uint256 internal constant ADMIN_PK_3 = 0xC0C;
    uint256 internal constant ADMIN_PK_4 = 0xD0D;
    uint256 internal constant ADMIN_PK_5 = 0xE0E;

    uint256 internal constant INITIATOR_PK = 0x91A0;

    address internal constant RECIPIENT = address(0xD201);

    // ──────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────

    OrganizationImplementationHarness internal gasImplementation;
    AccountImplementation internal gasAccountImplementation;

    Merkle internal merkle;
    MockERC20 internal mockToken;
    MockTarget internal mockTarget;

    address internal admin1;
    address internal admin2;
    address internal admin3;
    address internal admin4;
    address internal admin5;
    address internal initiator;

    // ──────────────────────────────────────────────────────────────────────
    // Setup
    // ──────────────────────────────────────────────────────────────────────

    function setUp() public override {
        super.setUp();

        gasImplementation = new OrganizationImplementationHarness();
        gasAccountImplementation = new AccountImplementation();
        whitelist.setImplementationWhitelisted(ContractType.Organization, address(gasImplementation), true);
        whitelist.setImplementationWhitelisted(ContractType.Account, address(gasAccountImplementation), true);

        merkle = new Merkle();
        mockToken = new MockERC20();
        mockTarget = new MockTarget();

        admin1 = vm.addr(ADMIN_PK_1);
        admin2 = vm.addr(ADMIN_PK_2);
        admin3 = vm.addr(ADMIN_PK_3);
        admin4 = vm.addr(ADMIN_PK_4);
        admin5 = vm.addr(ADMIN_PK_5);
        initiator = vm.addr(INITIATOR_PK);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 1. OrganizationFactory -- Deploy + Initialize
    // ══════════════════════════════════════════════════════════════════════

    function test_deployOrganization_minimalSetup_gas() public {
        InitializationParams memory params = _buildGasInitParams(2, 1, 0);
        bytes32 salt = bytes32(uint256(100_001));

        vm.prank(AUTHORIZED_DEPLOYER);
        vm.startSnapshotGas("deployOrganization_minimalSetup");
        factory.deployOrganization(salt, address(gasImplementation), address(whitelist), params);
        vm.stopSnapshotGas("deployOrganization_minimalSetup");
    }

    function test_deployOrganization_typicalSetup_gas() public {
        InitializationParams memory params = _buildGasInitParams(10, 3, 2);
        bytes32 salt = bytes32(uint256(100_002));

        vm.prank(AUTHORIZED_DEPLOYER);
        vm.startSnapshotGas("deployOrganization_typicalSetup");
        factory.deployOrganization(salt, address(gasImplementation), address(whitelist), params);
        vm.stopSnapshotGas("deployOrganization_typicalSetup");
    }

    function test_deployOrganization_largeSetup_gas() public {
        InitializationParams memory params = _buildGasInitParams(100, 5, 5);
        bytes32 salt = bytes32(uint256(100_003));

        vm.prank(AUTHORIZED_DEPLOYER);
        vm.startSnapshotGas("deployOrganization_largeSetup");
        factory.deployOrganization(salt, address(gasImplementation), address(whitelist), params);
        vm.stopSnapshotGas("deployOrganization_largeSetup");
    }

    function test_deployOrganization_veryLargeSetup_gas() public {
        InitializationParams memory params = _buildGasInitParams(1000, 10, 10);
        bytes32 salt = bytes32(uint256(100_004));

        vm.prank(AUTHORIZED_DEPLOYER);
        vm.startSnapshotGas("deployOrganization_veryLargeSetup");
        factory.deployOrganization(salt, address(gasImplementation), address(whitelist), params);
        vm.stopSnapshotGas("deployOrganization_veryLargeSetup");
    }

    // ══════════════════════════════════════════════════════════════════════
    // 2. Admin Operations (5 admins, threshold 4)
    // ══════════════════════════════════════════════════════════════════════

    function test_modifyMembers_addOne_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_001);
        address[] memory toAdd = _generateAddresses(1, 0xF000);
        address[] memory toRemove = buildEmptyAddressArray();
        AdminAuthParams memory auth = _buildAdminAuth(
            org,
            OperationType.ModifyMembers,
            abi.encode(keccak256(abi.encode(toAdd)), keccak256(abi.encode(toRemove))),
            200_002,
            true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyMembers_addOne");
        org.modifyMembers(toAdd, toRemove, auth);
        vm.stopSnapshotGas("modifyMembers_addOne");
    }

    function test_modifyMembers_addTen_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_003);
        address[] memory toAdd = _generateAddresses(10, 0xF100);
        address[] memory toRemove = buildEmptyAddressArray();
        AdminAuthParams memory auth = _buildAdminAuth(
            org,
            OperationType.ModifyMembers,
            abi.encode(keccak256(abi.encode(toAdd)), keccak256(abi.encode(toRemove))),
            200_004,
            true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyMembers_addTen");
        org.modifyMembers(toAdd, toRemove, auth);
        vm.stopSnapshotGas("modifyMembers_addTen");
    }

    function test_modifyMembers_addHundred_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_005);
        address[] memory toAdd = _generateAddresses(100, 0xF200);
        address[] memory toRemove = buildEmptyAddressArray();
        AdminAuthParams memory auth = _buildAdminAuth(
            org,
            OperationType.ModifyMembers,
            abi.encode(keccak256(abi.encode(toAdd)), keccak256(abi.encode(toRemove))),
            200_006,
            true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyMembers_addHundred");
        org.modifyMembers(toAdd, toRemove, auth);
        vm.stopSnapshotGas("modifyMembers_addHundred");
    }

    function test_modifyMembers_removeOne_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_007);
        address[] memory toAdd = buildEmptyAddressArray();
        address[] memory toRemove = buildArray(initiator);
        AdminAuthParams memory auth = _buildAdminAuth(
            org,
            OperationType.ModifyMembers,
            abi.encode(keccak256(abi.encode(toAdd)), keccak256(abi.encode(toRemove))),
            200_008,
            true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyMembers_removeOne");
        org.modifyMembers(toAdd, toRemove, auth);
        vm.stopSnapshotGas("modifyMembers_removeOne");
    }

    function test_modifyAdmins_addOne_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_009);
        address newAdmin = address(0xAD06);
        address[] memory toAdd = buildArray(newAdmin);
        address[] memory toRemove = buildEmptyAddressArray();
        // Must be a member first
        AdminAuthParams memory memberAuth = _buildAdminAuth(
            org,
            OperationType.ModifyMembers,
            abi.encode(keccak256(abi.encode(toAdd)), keccak256(abi.encode(toRemove))),
            200_010,
            true
        );
        vm.prank(GUARDIAN);
        org.modifyMembers(toAdd, toRemove, memberAuth);

        bytes memory operationData =
            abi.encode(keccak256(abi.encode(toAdd)), keccak256(abi.encode(toRemove)), uint256(4));
        AdminAuthParams memory auth = _buildAdminAuth(org, OperationType.ModifyAdmins, operationData, 200_011, true);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyAdmins_addOne");
        org.modifyAdmins(toAdd, toRemove, 4, auth);
        vm.stopSnapshotGas("modifyAdmins_addOne");
    }

    function test_modifyAdmins_removeOneAndLowerThreshold_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_012);
        address[] memory toAdd = buildEmptyAddressArray();
        address[] memory toRemove = buildArray(admin5);
        bytes memory operationData =
            abi.encode(keccak256(abi.encode(toAdd)), keccak256(abi.encode(toRemove)), uint256(3));
        AdminAuthParams memory auth = _buildAdminAuth(org, OperationType.ModifyAdmins, operationData, 200_013, true);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyAdmins_removeOneAndLowerThreshold");
        org.modifyAdmins(toAdd, toRemove, 3, auth);
        vm.stopSnapshotGas("modifyAdmins_removeOneAndLowerThreshold");
    }

    function test_modifyGroups_createOneGroup_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_014);
        GroupModification[] memory mods = new GroupModification[](1);
        mods[0] = GroupModification({
            groupId: 9001,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(admin1, admin2, admin3),
            membersToRemove: buildEmptyAddressArray()
        });
        bytes memory operationData = abi.encode(keccak256(abi.encode(mods)));
        AdminAuthParams memory auth = _buildAdminAuth(org, OperationType.ModifyGroups, operationData, 200_015, true);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyGroups_createOneGroup");
        org.modifyGroups(mods, auth);
        vm.stopSnapshotGas("modifyGroups_createOneGroup");
    }

    function test_modifyGroups_createFiveGroups_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_016);
        GroupModification[] memory mods = new GroupModification[](5);
        for (uint256 i = 0; i < 5; i++) {
            mods[i] = GroupModification({
                groupId: 9100 + i,
                modificationType: GroupModificationType.Create,
                membersToAdd: buildArray(admin1, admin2),
                membersToRemove: buildEmptyAddressArray()
            });
        }
        bytes memory operationData = abi.encode(keccak256(abi.encode(mods)));
        AdminAuthParams memory auth = _buildAdminAuth(org, OperationType.ModifyGroups, operationData, 200_017, true);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyGroups_createFiveGroups");
        org.modifyGroups(mods, auth);
        vm.stopSnapshotGas("modifyGroups_createFiveGroups");
    }

    function test_modifyGroups_updateOneGroup_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrgWithGroup(200_018, 8001);
        GroupModification[] memory mods = new GroupModification[](1);
        mods[0] = GroupModification({
            groupId: 8001,
            modificationType: GroupModificationType.Update,
            membersToAdd: buildArray(admin4, admin5),
            membersToRemove: buildEmptyAddressArray()
        });
        bytes memory operationData = abi.encode(keccak256(abi.encode(mods)));
        AdminAuthParams memory auth = _buildAdminAuth(org, OperationType.ModifyGroups, operationData, 200_019, true);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyGroups_updateOneGroup");
        org.modifyGroups(mods, auth);
        vm.stopSnapshotGas("modifyGroups_updateOneGroup");
    }

    function test_modifyGroups_deleteOneGroup_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrgWithGroup(200_020, 8002);
        GroupModification[] memory mods = new GroupModification[](1);
        mods[0] = GroupModification({
            groupId: 8002,
            modificationType: GroupModificationType.Delete,
            membersToAdd: buildEmptyAddressArray(),
            membersToRemove: buildEmptyAddressArray()
        });
        bytes memory operationData = abi.encode(keccak256(abi.encode(mods)));
        AdminAuthParams memory auth = _buildAdminAuth(org, OperationType.ModifyGroups, operationData, 200_021, true);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("modifyGroups_deleteOneGroup");
        org.modifyGroups(mods, auth);
        vm.stopSnapshotGas("modifyGroups_deleteOneGroup");
    }

    function test_setPolicies_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_022);
        bytes32 newRoot = keccak256("new-policies-root");
        string memory ipfsCid = "ipfs://gas-test-policies";
        bytes memory operationData = abi.encode(newRoot, keccak256(bytes(ipfsCid)));
        AdminAuthParams memory auth = _buildAdminAuth(org, OperationType.ModifyPolicies, operationData, 200_023, true);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("setPolicies");
        org.setPolicies(newRoot, ipfsCid, auth);
        vm.stopSnapshotGas("setPolicies");
    }

    function test_deployAccount_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_024);
        bytes32 create2Salt = bytes32(uint256(200_025));
        bytes memory operationData = abi.encode(create2Salt);
        AdminAuthParams memory auth = _buildAdminAuth(org, OperationType.DeployAccount, operationData, 200_026, true);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("deployAccount");
        org.deployAccount(create2Salt, auth);
        vm.stopSnapshotGas("deployAccount");
    }

    function test_rejectAdminOperation_gas() public {
        (OrganizationImplementationHarness org,) = _deployAdminOrg(200_027);
        bytes32 newRoot = keccak256("rejected-root");
        string memory ipfsCid = "ipfs://rejected";
        bytes memory operationData = abi.encode(newRoot, keccak256(bytes(ipfsCid)));
        AdminAuthParams memory auth = _buildAdminAuth(org, OperationType.ModifyPolicies, operationData, 200_028, false);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("rejectAdminOperation");
        org.rejectAdminOperation(OperationType.ModifyPolicies, operationData, auth);
        vm.stopSnapshotGas("rejectAdminOperation");
    }

    // ══════════════════════════════════════════════════════════════════════
    // 3. Account Transactions -- Policy Scaling
    // ══════════════════════════════════════════════════════════════════════

    function test_executeAccountTx_autoApprove_20policies_gas() public {
        _runPolicyScalingTest(20, PolicyType.AutoApprove, "executeAccountTx_autoApprove_20policies", 300_001);
    }

    function test_executeAccountTx_autoApprove_100policies_gas() public {
        _runPolicyScalingTest(100, PolicyType.AutoApprove, "executeAccountTx_autoApprove_100policies", 300_002);
    }

    function test_executeAccountTx_autoApprove_1000policies_gas() public {
        _runPolicyScalingTest(1000, PolicyType.AutoApprove, "executeAccountTx_autoApprove_1000policies", 300_003);
    }

    function test_executeAccountTx_manualApprove_20policies_gas() public {
        _runPolicyScalingTest(
            20, PolicyType.RequireManualApproval, "executeAccountTx_manualApprove_20policies", 300_004
        );
    }

    function test_executeAccountTx_manualApprove_100policies_gas() public {
        _runPolicyScalingTest(
            100, PolicyType.RequireManualApproval, "executeAccountTx_manualApprove_100policies", 300_005
        );
    }

    function test_executeAccountTx_manualApprove_1000policies_gas() public {
        _runPolicyScalingTest(
            1000, PolicyType.RequireManualApproval, "executeAccountTx_manualApprove_1000policies", 300_006
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // 4. Account Transactions -- Reviewer Count Scaling (ManualApproval)
    // ══════════════════════════════════════════════════════════════════════

    function test_executeAccountTx_manualApprove_1reviewer_gas() public {
        _runReviewerScalingTest(1, "executeAccountTx_manualApprove_1reviewer", 400_001);
    }

    function test_executeAccountTx_manualApprove_4reviewers_gas() public {
        _runReviewerScalingTest(4, "executeAccountTx_manualApprove_4reviewers", 400_002);
    }

    function test_executeAccountTx_manualApprove_10reviewers_gas() public {
        _runReviewerScalingTest(10, "executeAccountTx_manualApprove_10reviewers", 400_003);
    }

    function test_executeAccountTx_manualApprove_20reviewers_gas() public {
        _runReviewerScalingTest(20, "executeAccountTx_manualApprove_20reviewers", 400_004);
    }

    function test_executeAccountTx_manualApprove_50reviewers_gas() public {
        _runReviewerScalingTest(50, "executeAccountTx_manualApprove_50reviewers", 400_005);
    }

    // ══════════════════════════════════════════════════════════════════════
    // 5. Account Transactions -- Transaction Types
    // ══════════════════════════════════════════════════════════════════════

    function test_executeAccountTx_nativeTransfer_noRateLimit_gas() public {
        (OrganizationImplementationHarness org, address account, ValidationProofs memory proofs) =
            _deployOrgWithAutoApprovePolicy(TransactionType.Any, RateLimitType.None, 500_001);
        vm.deal(account, 1 ether);

        bytes memory sig = _signInitiatorTx(
            address(org), account, RECIPIENT, 0.1 ether, bytes(""), 500_002, block.timestamp + 1 days, POLICY_ID, true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("executeAccountTx_nativeTransfer_noRateLimit");
        org.executeAccountTransaction(
            account,
            RECIPIENT,
            0.1 ether,
            bytes(""),
            500_002,
            block.timestamp + 1 days,
            POLICY_ID,
            sig,
            bytes(""),
            proofs
        );
        vm.stopSnapshotGas("executeAccountTx_nativeTransfer_noRateLimit");
    }

    function test_executeAccountTx_tokenTransfer_noRateLimit_gas() public {
        (OrganizationImplementationHarness org, address account, ValidationProofs memory proofs) =
            _deployOrgWithAutoApprovePolicy(TransactionType.TokenTransfers, RateLimitType.None, 500_003);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, 1000);
        mockToken.mint(account, 10_000);

        bytes memory sig = _signInitiatorTx(
            address(org), account, address(mockToken), 0, data, 500_004, block.timestamp + 1 days, POLICY_ID, true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("executeAccountTx_tokenTransfer_noRateLimit");
        org.executeAccountTransaction(
            account, address(mockToken), 0, data, 500_004, block.timestamp + 1 days, POLICY_ID, sig, bytes(""), proofs
        );
        vm.stopSnapshotGas("executeAccountTx_tokenTransfer_noRateLimit");
    }

    function test_executeAccountTx_contractInteraction_noRateLimit_gas() public {
        (OrganizationImplementationHarness org, address account, ValidationProofs memory proofs) =
            _deployOrgWithAutoApprovePolicy(TransactionType.ContractInteractions, RateLimitType.None, 500_005);
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        bytes memory sig = _signInitiatorTx(
            address(org), account, address(mockTarget), 0, data, 500_006, block.timestamp + 1 days, POLICY_ID, true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("executeAccountTx_contractInteraction_noRateLimit");
        org.executeAccountTransaction(
            account, address(mockTarget), 0, data, 500_006, block.timestamp + 1 days, POLICY_ID, sig, bytes(""), proofs
        );
        vm.stopSnapshotGas("executeAccountTx_contractInteraction_noRateLimit");
    }

    function test_executeAccountTx_nativeTransfer_withRateLimit_gas() public {
        (OrganizationImplementationHarness org, address account, ValidationProofs memory proofs) =
            _deployOrgWithAutoApprovePolicy(TransactionType.Any, RateLimitType.TimeInterval, 500_007);
        vm.deal(account, 1 ether);

        bytes memory sig = _signInitiatorTx(
            address(org), account, RECIPIENT, 0.1 ether, bytes(""), 500_008, block.timestamp + 1 days, POLICY_ID, true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("executeAccountTx_nativeTransfer_withRateLimit");
        org.executeAccountTransaction(
            account,
            RECIPIENT,
            0.1 ether,
            bytes(""),
            500_008,
            block.timestamp + 1 days,
            POLICY_ID,
            sig,
            bytes(""),
            proofs
        );
        vm.stopSnapshotGas("executeAccountTx_nativeTransfer_withRateLimit");
    }

    function test_executeAccountTx_tokenTransfer_withRateLimit_gas() public {
        (OrganizationImplementationHarness org, address account, ValidationProofs memory proofs) =
            _deployOrgWithAutoApprovePolicy(TransactionType.TokenTransfers, RateLimitType.TimeInterval, 500_009);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, 1000);
        mockToken.mint(account, 10_000);

        bytes memory sig = _signInitiatorTx(
            address(org), account, address(mockToken), 0, data, 500_010, block.timestamp + 1 days, POLICY_ID, true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("executeAccountTx_tokenTransfer_withRateLimit");
        org.executeAccountTransaction(
            account, address(mockToken), 0, data, 500_010, block.timestamp + 1 days, POLICY_ID, sig, bytes(""), proofs
        );
        vm.stopSnapshotGas("executeAccountTx_tokenTransfer_withRateLimit");
    }

    function test_executeAccountTx_contractInteraction_withRateLimit_gas() public {
        (OrganizationImplementationHarness org, address account, ValidationProofs memory proofs) =
            _deployOrgWithAutoApprovePolicy(TransactionType.ContractInteractions, RateLimitType.TimeInterval, 500_011);
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        bytes memory sig = _signInitiatorTx(
            address(org), account, address(mockTarget), 0, data, 500_012, block.timestamp + 1 days, POLICY_ID, true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("executeAccountTx_contractInteraction_withRateLimit");
        org.executeAccountTransaction(
            account, address(mockTarget), 0, data, 500_012, block.timestamp + 1 days, POLICY_ID, sig, bytes(""), proofs
        );
        vm.stopSnapshotGas("executeAccountTx_contractInteraction_withRateLimit");
    }

    function test_executeAccountTx_tokenTransfer_rateLimitPerEntity_gas() public {
        (OrganizationImplementationHarness org, address account) = _deploySimpleOrg(500_013);
        Policy memory policy = _buildAutoApprovePolicy();
        policy.config.transactionType = TransactionType.TokenTransfers;
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = type(uint128).max;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        ValidationProofs memory proofs = _setPoliciesAndBuildProofs(org, POLICY_ID, policy, 500_014);

        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, 1000);
        mockToken.mint(account, 10_000);

        bytes memory sig = _signInitiatorTx(
            address(org), account, address(mockToken), 0, data, 500_015, block.timestamp + 1 days, POLICY_ID, true
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("executeAccountTx_tokenTransfer_rateLimitPerEntity");
        org.executeAccountTransaction(
            account, address(mockToken), 0, data, 500_015, block.timestamp + 1 days, POLICY_ID, sig, bytes(""), proofs
        );
        vm.stopSnapshotGas("executeAccountTx_tokenTransfer_rateLimitPerEntity");
    }

    // ══════════════════════════════════════════════════════════════════════
    // 6. Account Transaction Rejection
    // ══════════════════════════════════════════════════════════════════════

    function test_rejectAccountTx_autoApprove_gas() public {
        (OrganizationImplementationHarness org, address account, ValidationProofs memory proofs) =
            _deployOrgWithAutoApprovePolicy(TransactionType.Any, RateLimitType.None, 600_001);
        vm.deal(account, 1 ether);

        bytes memory initiatorSig = _signInitiatorTx(
            address(org), account, RECIPIENT, 0.1 ether, bytes(""), 600_002, block.timestamp + 1 days, POLICY_ID, true
        );
        bytes memory rejectionSig = _signInitiatorTx(
            address(org), account, RECIPIENT, 0.1 ether, bytes(""), 600_002, block.timestamp + 1 days, POLICY_ID, false
        );

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("rejectAccountTx_autoApprove");
        org.rejectAccountTransaction(
            account,
            RECIPIENT,
            0.1 ether,
            bytes(""),
            600_002,
            block.timestamp + 1 days,
            POLICY_ID,
            initiatorSig,
            rejectionSig,
            proofs
        );
        vm.stopSnapshotGas("rejectAccountTx_autoApprove");
    }

    function test_rejectAccountTx_manualApprove_gas() public {
        uint256 reviewerPk = 0xBB01;
        address reviewer = vm.addr(reviewerPk);

        (OrganizationImplementationHarness org, address account) = _deploySimpleOrgWithMember(600_003, reviewer);
        Policy memory policy = _buildManualApprovePolicy(reviewer);
        ValidationProofs memory proofs = _setPoliciesAndBuildProofs(org, POLICY_ID, policy, 600_004);

        vm.deal(account, 1 ether);

        bytes memory initiatorSig = _signInitiatorTx(
            address(org), account, RECIPIENT, 0.1 ether, bytes(""), 600_005, block.timestamp + 1 days, POLICY_ID, true
        );
        bytes32 reviewHash = _computeReviewTxHash(
            address(org),
            account,
            RECIPIENT,
            0.1 ether,
            bytes(""),
            600_005,
            block.timestamp + 1 days,
            POLICY_ID,
            false,
            initiatorSig
        );
        bytes memory reviewSig = _signHash(reviewerPk, reviewHash);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas("rejectAccountTx_manualApprove");
        org.rejectAccountTransaction(
            account,
            RECIPIENT,
            0.1 ether,
            bytes(""),
            600_005,
            block.timestamp + 1 days,
            POLICY_ID,
            initiatorSig,
            reviewSig,
            proofs
        );
        vm.stopSnapshotGas("rejectAccountTx_manualApprove");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Internal Helpers -- Organization Deployment
    // ══════════════════════════════════════════════════════════════════════

    function _buildGasInitParams(uint256 memberCount, uint256 adminCount, uint256 groupCount)
        internal
        view
        returns (InitializationParams memory params)
    {
        params.members = new address[](memberCount);
        for (uint256 i = 0; i < memberCount; i++) {
            params.members[i] = address(uint160(0x10000 + i));
        }
        params.admins = new address[](adminCount);
        for (uint256 i = 0; i < adminCount; i++) {
            params.admins[i] = params.members[i];
        }
        params.votingThreshold = adminCount;

        params.groups = new GroupModification[](groupCount);
        for (uint256 i = 0; i < groupCount; i++) {
            address[] memory groupMembers = new address[](2);
            groupMembers[0] = params.members[0];
            groupMembers[1] = params.members[i < memberCount ? i : 0];
            params.groups[i] = GroupModification({
                groupId: 7000 + i,
                modificationType: GroupModificationType.Create,
                membersToAdd: groupMembers,
                membersToRemove: new address[](0)
            });
        }

        params.guardian = GUARDIAN;
        params.accountImplementation = address(gasAccountImplementation);
        params.adminOperationTimelockDurationSeconds = ADMIN_OPERATION_TIMELOCK;
        params.transactionAndERC1271RecoveryAddress = TX_RECOVERY;
        params.txRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;
        params.guardianRecoveryAddress = GUARDIAN_RECOVERY;
        params.guardianRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;
    }

    /// @dev Deploys an org with 5 admins (threshold 4) + the initiator as a member.
    function _deployAdminOrg(uint256 saltSeed)
        internal
        returns (OrganizationImplementationHarness org, address[] memory admins)
    {
        admins = new address[](5);
        admins[0] = admin1;
        admins[1] = admin2;
        admins[2] = admin3;
        admins[3] = admin4;
        admins[4] = admin5;

        address[] memory members = new address[](6);
        members[0] = admin1;
        members[1] = admin2;
        members[2] = admin3;
        members[3] = admin4;
        members[4] = admin5;
        members[5] = initiator;

        InitializationParams memory params;
        params.members = members;
        params.admins = admins;
        params.votingThreshold = 4;
        params.groups = new GroupModification[](0);
        params.guardian = GUARDIAN;
        params.accountImplementation = address(gasAccountImplementation);
        params.adminOperationTimelockDurationSeconds = ADMIN_OPERATION_TIMELOCK;
        params.transactionAndERC1271RecoveryAddress = TX_RECOVERY;
        params.txRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;
        params.guardianRecoveryAddress = GUARDIAN_RECOVERY;
        params.guardianRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;

        vm.prank(AUTHORIZED_DEPLOYER);
        org = OrganizationImplementationHarness(
            payable(factory.deployOrganization(
                    bytes32(saltSeed), address(gasImplementation), address(whitelist), params
                ))
        );
    }

    /// @dev Deploys an admin org with one pre-created group.
    function _deployAdminOrgWithGroup(uint256 saltSeed, uint256 groupId)
        internal
        returns (OrganizationImplementationHarness org, address[] memory admins)
    {
        (org, admins) = _deployAdminOrg(saltSeed);

        GroupModification[] memory mods = new GroupModification[](1);
        mods[0] = GroupModification({
            groupId: groupId,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(admin1, admin2, admin3),
            membersToRemove: buildEmptyAddressArray()
        });
        bytes memory operationData = abi.encode(keccak256(abi.encode(mods)));
        AdminAuthParams memory auth =
            _buildAdminAuth(org, OperationType.ModifyGroups, operationData, saltSeed + 1000, true);
        vm.prank(GUARDIAN);
        org.modifyGroups(mods, auth);
    }

    /// @dev Deploys a simple org with 1 admin for account transaction tests.
    function _deploySimpleOrg(uint256 saltSeed)
        internal
        returns (OrganizationImplementationHarness org, address account)
    {
        InitializationParams memory params;
        params.members = buildArray(admin1, initiator);
        params.admins = buildArray(admin1);
        params.votingThreshold = 1;
        params.groups = new GroupModification[](0);
        params.guardian = GUARDIAN;
        params.accountImplementation = address(gasAccountImplementation);
        params.adminOperationTimelockDurationSeconds = ADMIN_OPERATION_TIMELOCK;
        params.transactionAndERC1271RecoveryAddress = TX_RECOVERY;
        params.txRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;
        params.guardianRecoveryAddress = GUARDIAN_RECOVERY;
        params.guardianRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;

        vm.prank(AUTHORIZED_DEPLOYER);
        org = OrganizationImplementationHarness(
            payable(factory.deployOrganization(
                    bytes32(saltSeed), address(gasImplementation), address(whitelist), params
                ))
        );

        bytes32 create2Salt = bytes32(saltSeed + 1);
        AdminAuthParams memory auth =
            _buildSimpleAdminAuth(org, OperationType.DeployAccount, abi.encode(create2Salt), saltSeed + 2, true);
        vm.prank(GUARDIAN);
        account = org.deployAccount(create2Salt, auth);
    }

    /// @dev Deploys a simple org with 1 admin and an extra member (for reviewer-based tests).
    function _deploySimpleOrgWithMember(uint256 saltSeed, address extraMember)
        internal
        returns (OrganizationImplementationHarness org, address account)
    {
        InitializationParams memory params;
        params.members = buildArray(admin1, initiator, extraMember);
        params.admins = buildArray(admin1);
        params.votingThreshold = 1;
        params.groups = new GroupModification[](0);
        params.guardian = GUARDIAN;
        params.accountImplementation = address(gasAccountImplementation);
        params.adminOperationTimelockDurationSeconds = ADMIN_OPERATION_TIMELOCK;
        params.transactionAndERC1271RecoveryAddress = TX_RECOVERY;
        params.txRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;
        params.guardianRecoveryAddress = GUARDIAN_RECOVERY;
        params.guardianRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;

        vm.prank(AUTHORIZED_DEPLOYER);
        org = OrganizationImplementationHarness(
            payable(factory.deployOrganization(
                    bytes32(saltSeed), address(gasImplementation), address(whitelist), params
                ))
        );

        bytes32 create2Salt = bytes32(saltSeed + 1);
        AdminAuthParams memory auth =
            _buildSimpleAdminAuth(org, OperationType.DeployAccount, abi.encode(create2Salt), saltSeed + 2, true);
        vm.prank(GUARDIAN);
        account = org.deployAccount(create2Salt, auth);
    }

    /// @dev Deploys an org with N reviewer members in a group, for reviewer scaling tests.
    function _deployOrgWithReviewerGroup(uint256 saltSeed, uint256 reviewerCount, uint256 groupId)
        internal
        returns (OrganizationImplementationHarness org, address account, uint256[] memory reviewerPks)
    {
        reviewerPks = new uint256[](reviewerCount);
        address[] memory reviewerAddresses = new address[](reviewerCount);
        for (uint256 i = 0; i < reviewerCount; i++) {
            reviewerPks[i] = 0xCC00 + i + 1;
            reviewerAddresses[i] = vm.addr(reviewerPks[i]);
        }

        // members = admin1 + initiator + all reviewers
        address[] memory members = new address[](2 + reviewerCount);
        members[0] = admin1;
        members[1] = initiator;
        for (uint256 i = 0; i < reviewerCount; i++) {
            members[2 + i] = reviewerAddresses[i];
        }

        GroupModification[] memory groups = new GroupModification[](1);
        groups[0] = GroupModification({
            groupId: groupId,
            modificationType: GroupModificationType.Create,
            membersToAdd: reviewerAddresses,
            membersToRemove: new address[](0)
        });

        InitializationParams memory params;
        params.members = members;
        params.admins = buildArray(admin1);
        params.votingThreshold = 1;
        params.groups = groups;
        params.guardian = GUARDIAN;
        params.accountImplementation = address(gasAccountImplementation);
        params.adminOperationTimelockDurationSeconds = ADMIN_OPERATION_TIMELOCK;
        params.transactionAndERC1271RecoveryAddress = TX_RECOVERY;
        params.txRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;
        params.guardianRecoveryAddress = GUARDIAN_RECOVERY;
        params.guardianRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;

        vm.prank(AUTHORIZED_DEPLOYER);
        org = OrganizationImplementationHarness(
            payable(factory.deployOrganization(
                    bytes32(saltSeed), address(gasImplementation), address(whitelist), params
                ))
        );

        bytes32 create2Salt = bytes32(saltSeed + 1);
        AdminAuthParams memory auth =
            _buildSimpleAdminAuth(org, OperationType.DeployAccount, abi.encode(create2Salt), saltSeed + 2, true);
        vm.prank(GUARDIAN);
        account = org.deployAccount(create2Salt, auth);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Internal Helpers -- Policy Builders
    // ══════════════════════════════════════════════════════════════════════

    function _buildAutoApprovePolicy() internal view returns (Policy memory policy) {
        policy = Policy({
            config: PolicyConfig({
                transactionType: TransactionType.Any,
                anySourceAccount: true,
                anyFunction: true,
                destinationType: DestinationType.Any,
                approval: ApprovalConfig({
                    policyType: PolicyType.AutoApprove,
                    approverType: ApproverType.Member,
                    approverMember: initiator,
                    approverGroupId: 0,
                    approvalThreshold: 1
                }),
                initiator: InitiatorConfig({
                    anyInitiator: false,
                    initiatorType: ApproverType.Member,
                    initiatorMember: initiator,
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

    function _buildManualApprovePolicy(address reviewer) internal view returns (Policy memory policy) {
        policy = _buildAutoApprovePolicy();
        policy.config.approval.policyType = PolicyType.RequireManualApproval;
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = reviewer;
        policy.config.approval.approvalThreshold = 1;
    }

    function _buildManualApproveGroupPolicy(uint256 groupId, uint8 threshold)
        internal
        view
        returns (Policy memory policy)
    {
        policy = _buildAutoApprovePolicy();
        policy.config.approval.policyType = PolicyType.RequireManualApproval;
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = groupId;
        policy.config.approval.approvalThreshold = threshold;
    }

    function _computePolicyLeaf(uint256 policyId, Policy memory policy) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
    }

    function _buildEmptyProofs(Policy memory policy) internal pure returns (ValidationProofs memory proofs) {
        bytes32[] memory empty = new bytes32[](0);
        proofs = ValidationProofs({
            policy: policy,
            policyProof: empty,
            sourceAccountProof: empty,
            destinationProof: empty,
            functionProof: empty,
            constraints: bytes("")
        });
    }

    function _setPoliciesAndBuildProofs(
        OrganizationImplementationHarness org,
        uint256 policyId,
        Policy memory policy,
        uint256 salt
    ) internal returns (ValidationProofs memory proofs) {
        bytes32 root = _computePolicyLeaf(policyId, policy);
        bytes memory operationData = abi.encode(root, keccak256(bytes("ipfs://gas-test")));
        AdminAuthParams memory auth =
            _buildSimpleAdminAuth(org, OperationType.ModifyPolicies, operationData, salt, true);
        vm.prank(GUARDIAN);
        org.setPolicies(root, "ipfs://gas-test", auth);
        proofs = _buildEmptyProofs(policy);
    }

    /// @dev Builds multi-policy tree, places real policy at targetIndex, returns (root, proof, proofs).
    function _buildMultiPolicyTreeAndProofs(
        uint256 policyCount,
        uint256 targetPolicyIndex,
        uint256 targetPolicyId,
        Policy memory targetPolicy
    ) internal returns (bytes32 root, ValidationProofs memory proofs) {
        bytes32[] memory leaves = new bytes32[](policyCount);
        for (uint256 i = 0; i < policyCount; i++) {
            if (i == targetPolicyIndex) {
                leaves[i] = _computePolicyLeaf(targetPolicyId, targetPolicy);
            } else {
                Policy memory dummy = _buildAutoApprovePolicy();
                dummy.config.rateLimit.timeIntervalLimit = i + 1;
                leaves[i] = _computePolicyLeaf(i + 10_000, dummy);
            }
        }

        bytes32[] memory proof;
        if (policyCount == 1) {
            root = leaves[0];
            proof = new bytes32[](0);
        } else {
            root = merkle.getRoot(leaves);
            proof = merkle.getProof(leaves, targetPolicyIndex);
        }

        proofs = ValidationProofs({
            policy: targetPolicy,
            policyProof: proof,
            sourceAccountProof: new bytes32[](0),
            destinationProof: new bytes32[](0),
            functionProof: new bytes32[](0),
            constraints: bytes("")
        });
    }

    // ══════════════════════════════════════════════════════════════════════
    // Internal Helpers -- Deployment Convenience
    // ══════════════════════════════════════════════════════════════════════

    function _deployOrgWithAutoApprovePolicy(TransactionType txType, RateLimitType rateLimitType, uint256 saltSeed)
        internal
        returns (OrganizationImplementationHarness org, address account, ValidationProofs memory proofs)
    {
        (org, account) = _deploySimpleOrg(saltSeed);
        Policy memory policy = _buildAutoApprovePolicy();
        policy.config.transactionType = txType;
        if (rateLimitType == RateLimitType.TimeInterval) {
            policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
            policy.config.rateLimit.timeIntervalHours = 24;
            policy.config.rateLimit.timeIntervalLimit = type(uint128).max;
        }
        proofs = _setPoliciesAndBuildProofs(org, POLICY_ID, policy, saltSeed + 100);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Internal Helpers -- Auth Builders
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Builds admin auth with 4-of-5 admin signatures (ADMIN_PK_1..4).
    function _buildAdminAuth(
        OrganizationImplementationHarness org,
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        bool isApproval
    ) internal view returns (AdminAuthParams memory) {
        uint256 expirationTimestamp = block.timestamp + 30 days;
        bytes32 operationHash =
            org.getAdminOperationHash(operationType, operationData, salt, expirationTimestamp, isApproval);

        uint256[] memory pks = new uint256[](4);
        pks[0] = ADMIN_PK_1;
        pks[1] = ADMIN_PK_2;
        pks[2] = ADMIN_PK_3;
        pks[3] = ADMIN_PK_4;

        bytes memory signatures = _buildSortedEOASignatures(operationHash, pks);
        return AdminAuthParams({salt: salt, expirationTimestamp: expirationTimestamp, signatures: signatures});
    }

    /// @dev Builds admin auth with 1 admin signature (for simple orgs with threshold=1).
    function _buildSimpleAdminAuth(
        OrganizationImplementationHarness org,
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        bool isApproval
    ) internal view returns (AdminAuthParams memory) {
        uint256 expirationTimestamp = block.timestamp + 30 days;
        bytes32 operationHash =
            org.getAdminOperationHash(operationType, operationData, salt, expirationTimestamp, isApproval);

        uint256[] memory pks = new uint256[](1);
        pks[0] = ADMIN_PK_1;

        bytes memory signatures = _buildSortedEOASignatures(operationHash, pks);
        return AdminAuthParams({salt: salt, expirationTimestamp: expirationTimestamp, signatures: signatures});
    }

    function _buildSortedEOASignatures(bytes32 operationHash, uint256[] memory privateKeys)
        internal
        view
        returns (bytes memory)
    {
        address[] memory signers = new address[](privateKeys.length);
        bytes[] memory signatures = new bytes[](privateKeys.length);
        for (uint256 i = 0; i < privateKeys.length; i++) {
            signers[i] = vm.addr(privateKeys[i]);
            signatures[i] = _signHash(privateKeys[i], operationHash);
        }
        // Sort by signer address
        for (uint256 i = 0; i < signers.length; i++) {
            for (uint256 j = i + 1; j < signers.length; j++) {
                if (uint160(signers[j]) < uint160(signers[i])) {
                    (signers[i], signers[j]) = (signers[j], signers[i]);
                    (signatures[i], signatures[j]) = (signatures[j], signatures[i]);
                }
            }
        }
        return _concatSignatures(signatures);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Internal Helpers -- EIP-712 Hashing & Signing
    // ══════════════════════════════════════════════════════════════════════

    function _signInitiatorTx(
        address organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval
    ) internal view returns (bytes memory) {
        bytes32 hash = _computeInitiatorTxHash(
            organization, account, to, value, data, salt, expirationTimestamp, policyId, isApproval
        );
        return _signHash(INITIATOR_PK, hash);
    }

    function _computeInitiatorTxHash(
        address organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                INITIATE_ACCOUNT_TRANSACTION_TYPEHASH,
                organization,
                account,
                to,
                value,
                keccak256(data),
                salt,
                expirationTimestamp,
                policyId,
                isApproval,
                block.chainid
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", _getDomainSeparator(organization), structHash));
    }

    function _computeReviewTxHash(
        address organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval,
        bytes memory initiatorSignature
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                REVIEW_ACCOUNT_TRANSACTION_TYPEHASH,
                organization,
                account,
                to,
                value,
                keccak256(data),
                salt,
                expirationTimestamp,
                policyId,
                isApproval,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", _getDomainSeparator(organization), structHash));
    }

    function _getDomainSeparator(address organization) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, ORGANIZATION_NAME_HASH, ORGANIZATION_VERSION_HASH, block.chainid, organization
            )
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // Internal Helpers -- Utility
    // ══════════════════════════════════════════════════════════════════════

    function _generateAddresses(uint256 count, uint256 startOffset) internal pure returns (address[] memory addrs) {
        addrs = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            addrs[i] = address(uint160(startOffset + i));
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // Internal Helpers -- Test Runners
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Runs a policy-scaling gas test with N policies in the tree.
    function _runPolicyScalingTest(uint256 policyCount, PolicyType approvalType, string memory label, uint256 saltSeed)
        internal
    {
        uint256 reviewerPk = 0xBB01;
        address reviewer = vm.addr(reviewerPk);

        // Deploy org with the reviewer as a member if manual approval
        OrganizationImplementationHarness org;
        address account;
        if (approvalType == PolicyType.RequireManualApproval) {
            (org, account) = _deploySimpleOrgWithMember(saltSeed, reviewer);
        } else {
            (org, account) = _deploySimpleOrg(saltSeed);
        }
        vm.deal(account, 1 ether);

        Policy memory policy = _buildAutoApprovePolicy();
        if (approvalType == PolicyType.RequireManualApproval) {
            policy.config.approval.policyType = PolicyType.RequireManualApproval;
            policy.config.approval.approverType = ApproverType.Member;
            policy.config.approval.approverMember = reviewer;
            policy.config.approval.approvalThreshold = 1;
        }

        uint256 targetIndex = policyCount / 2;
        (bytes32 root, ValidationProofs memory proofs) =
            _buildMultiPolicyTreeAndProofs(policyCount, targetIndex, POLICY_ID, policy);

        bytes memory operationData = abi.encode(root, keccak256(bytes("ipfs://gas-test")));
        AdminAuthParams memory auth =
            _buildSimpleAdminAuth(org, OperationType.ModifyPolicies, operationData, saltSeed + 100, true);
        vm.prank(GUARDIAN);
        org.setPolicies(root, "ipfs://gas-test", auth);

        uint256 txSalt = saltSeed + 200;
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(org), account, RECIPIENT, 0.1 ether, bytes(""), txSalt, expiration, POLICY_ID, true
        );

        bytes memory reviewSigs = bytes("");
        if (approvalType == PolicyType.RequireManualApproval) {
            bytes32 reviewHash = _computeReviewTxHash(
                address(org),
                account,
                RECIPIENT,
                0.1 ether,
                bytes(""),
                txSalt,
                expiration,
                POLICY_ID,
                true,
                initiatorSig
            );
            reviewSigs = _signHash(reviewerPk, reviewHash);
        }

        vm.prank(GUARDIAN);
        vm.startSnapshotGas(label);
        org.executeAccountTransaction(
            account, RECIPIENT, 0.1 ether, bytes(""), txSalt, expiration, POLICY_ID, initiatorSig, reviewSigs, proofs
        );
        vm.stopSnapshotGas(label);
    }

    /// @dev Runs a reviewer-count scaling gas test with N reviewers in a group.
    function _runReviewerScalingTest(uint256 reviewerCount, string memory label, uint256 saltSeed) internal {
        uint256 groupId = 6000;

        (OrganizationImplementationHarness org, address account, uint256[] memory reviewerPks) =
            _deployOrgWithReviewerGroup(saltSeed, reviewerCount, groupId);
        vm.deal(account, 1 ether);

        Policy memory policy = _buildManualApproveGroupPolicy(groupId, uint8(reviewerCount));
        ValidationProofs memory proofs = _setPoliciesAndBuildProofs(org, POLICY_ID, policy, saltSeed + 100);

        uint256 txSalt = saltSeed + 200;
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(org), account, RECIPIENT, 0.1 ether, bytes(""), txSalt, expiration, POLICY_ID, true
        );

        bytes32 reviewHash = _computeReviewTxHash(
            address(org), account, RECIPIENT, 0.1 ether, bytes(""), txSalt, expiration, POLICY_ID, true, initiatorSig
        );

        // Build sorted reviewer signatures
        address[] memory signers = new address[](reviewerCount);
        bytes[] memory sigs = new bytes[](reviewerCount);
        for (uint256 i = 0; i < reviewerCount; i++) {
            signers[i] = vm.addr(reviewerPks[i]);
            sigs[i] = _signHash(reviewerPks[i], reviewHash);
        }
        for (uint256 i = 0; i < signers.length; i++) {
            for (uint256 j = i + 1; j < signers.length; j++) {
                if (uint160(signers[j]) < uint160(signers[i])) {
                    (signers[i], signers[j]) = (signers[j], signers[i]);
                    (sigs[i], sigs[j]) = (sigs[j], sigs[i]);
                }
            }
        }
        bytes memory reviewSignatures = _concatSignatures(sigs);

        vm.prank(GUARDIAN);
        vm.startSnapshotGas(label);
        org.executeAccountTransaction(
            account,
            RECIPIENT,
            0.1 ether,
            bytes(""),
            txSalt,
            expiration,
            POLICY_ID,
            initiatorSig,
            reviewSignatures,
            proofs
        );
        vm.stopSnapshotGas(label);
    }
}
