// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    LibOrganizationAdminSuiteBase
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminSuiteBase.sol";

/**
 * @dev Unit tests for signature-checking helpers in `LibOrganizationAdmin`.
 */
contract LibOrganizationAdminSignaturesTest is LibOrganizationAdminSuiteBase {
    /// @dev Verifies `LibOrganizationAdmin._areAdminSignaturesValid` returns `false` for an empty signature payload.
    function test_L_58__NMADM_SIG_1_areAdminSignaturesValid_emptySignatures_returnsFalse() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: invoke signature validation on an empty packed-signatures payload.
        bool actualIsValid = harness.areAdminSignaturesValid(bytes(""), keccak256("op"));

        // Verify: assert that signature validation fails for this input set.
        assertFalse(actualIsValid, "empty signatures should be false");
    }

    /// @dev Verifies `LibOrganizationAdmin._areAdminSignaturesValid` returns `true` once the admin threshold is met.
    function test_L_59__NMADM_SIG_6_areAdminSignaturesValid_exactThreshold_returnsTrue() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 hash = keccak256("op59");
        bytes memory signatures = _buildSortedEOASignatures(hash, buildUint256Array(ADMIN_PK_1, ADMIN_PK_2));

        // Call: invoke signature validation with exactly-threshold signatures.
        bool actualIsValid = harness.areAdminSignaturesValid(signatures, hash);

        // Verify: assert that signature validation succeeds for this input set.
        assertTrue(actualIsValid, "exact threshold signatures should validate");
    }

    /// @dev Verifies that more-than-threshold signatures return true via early exit.
    function test_areAdminSignaturesValid_moreThanThreshold_returnsTrue() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        bytes32 hash = keccak256("op60");
        bytes memory signatures = _buildSortedEOASignatures(hash, buildUint256Array(ADMIN_PK_1, ADMIN_PK_2));

        // Call: invoke signature validation with more-than-threshold signatures.
        bool actualIsValid = harness.areAdminSignaturesValid(signatures, hash);

        // Verify: assert that signature validation succeeds for this input set.
        assertTrue(actualIsValid, "more-than-threshold signatures should validate");
    }

    /// @dev Verifies `LibOrganizationAdmin._areAdminSignaturesValid` returns `false` when a non-empty signer stream ends below threshold.
    function test_NMADM_SIG_4_areAdminSignaturesValid_fewerThanThreshold_returnsFalse() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 hash = keccak256("op61");
        bytes memory signatures = _buildSortedEOASignatures(hash, buildUint256Array(ADMIN_PK_1));

        // Call: invoke signature validation with fewer-than-threshold signatures.
        bool actualIsValid = harness.areAdminSignaturesValid(signatures, hash);

        // Verify: the helper reports insufficient signatures with `false` so the caller can decide whether to revert.
        assertFalse(actualIsValid, "fewer-than-threshold signatures should fail");
    }

    /// @dev Verifies `LibOrganizationAdmin._areAdminSignaturesValid` reverts for duplicate admin signers.
    function test_L_62__NMADM_SIG_2_areAdminSignaturesValid_duplicateSigner_revertsDuplicateOrOutOfOrder() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 hash = keccak256("op62");
        bytes memory sig = _signHash(ADMIN_PK_1, hash);
        bytes memory signatures = abi.encodePacked(sig, sig);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, admin1, admin1)
        );
        // Call: invoke signature validation on the packed signatures payload.
        harness.areAdminSignaturesValid(signatures, hash);
    }

    /// @dev Verifies `LibOrganizationAdmin._areAdminSignaturesValid` reverts for out-of-order admin signers.
    function test_L_63__NMADM_SIG_3_areAdminSignaturesValid_outOfOrderSigner_revertsDuplicateOrOutOfOrder()
        public
    {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 hash = keccak256("op63");
        bytes memory sig1 = _signHash(ADMIN_PK_1, hash);
        bytes memory sig2 = _signHash(ADMIN_PK_2, hash);

        bytes memory outOfOrder;
        address signer1 = vm.addr(ADMIN_PK_1);
        address signer2 = vm.addr(ADMIN_PK_2);

        if (signer1 < signer2) {
            outOfOrder = abi.encodePacked(sig2, sig1);
            // Verify: confirm this branch reverts for the intended failure condition.
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, signer1, signer2)
            );
        } else {
            outOfOrder = abi.encodePacked(sig1, sig2);
            // Verify: confirm this branch reverts for the intended failure condition.
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, signer2, signer1)
            );
        }

        // Call: invoke signature validation on the packed signatures payload.

        harness.areAdminSignaturesValid(outOfOrder, hash);
    }

    /// @dev Verifies `LibOrganizationAdmin._areAdminSignaturesValid` reverts when a recovered signer is not an admin.
    function test_L_64__NMADM_SIG_5_areAdminSignaturesValid_nonAdminNonMemberSigner_revertsSignerIsNotAdmin()
        public
    {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 nonAdminPk = 0xF00D;
        address nonAdmin = vm.addr(nonAdminPk);
        bytes32 hash = keccak256("op64");
        bytes memory sig = _signHash(nonAdminPk, hash);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, nonAdmin));
        // Call: invoke signature validation on the packed signatures payload.
        harness.areAdminSignaturesValid(sig, hash);
    }

    /// @dev Verifies that a member who is not an admin reverts with `SignerIsNotAdmin`.
    function test_areAdminSignaturesValid_nonAdminMemberSigner_revertsSignerIsNotAdmin() public {
        uint256 memberNonAdminPk = 0xF00E;
        address memberNonAdmin = vm.addr(memberNonAdminPk);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, memberNonAdmin), admins: buildArray(admin1), threshold: 1});

        bytes32 hash = keccak256("op64-member");
        bytes memory sig = _signHash(memberNonAdminPk, hash);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, memberNonAdmin));
        // Call: invoke signature validation on the packed signatures payload.
        harness.areAdminSignaturesValid(sig, hash);
    }

    /// @dev Verifies that mixed EOA and ERC-1271 signers succeed when globally sorted.
    function test_areAdminSignaturesValid_mixedEOAAndERC1271_sorted_succeeds() public {
        address contractAdmin = address(validSigner1271);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, contractAdmin), admins: buildArray(admin1, contractAdmin), threshold: 2
        });

        bytes32 hash = keccak256("op65");
        address[] memory signers = buildArray(admin1, contractAdmin);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signHash(ADMIN_PK_1, hash);
        signatures[1] = _buildContractSignature({signer: contractAdmin, innerSig: hex"1234"});

        bytes memory packed = _sortAndConcatSignatures(signers, signatures);

        // Call: invoke signature validation with mixed EOA + ERC-1271 signatures.
        bool actualIsValid = harness.areAdminSignaturesValid(packed, hash);

        // Verify: assert that signature validation succeeds for this input set.
        assertTrue(actualIsValid, "mixed sorted signatures should validate");
    }

    /// @dev Verifies `LibOrganizationAdmin._areAdminSignaturesValid` reverts for malformed packed signatures.
    function test_L_66__NMADM_SIG_8_areAdminSignaturesValid_malformedEncoding_revertsSignatureRecoveryFailed()
        public
    {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: malformed packed signatures must fail during recovery.
        _expectSignatureRecoveryFailure();
        // Call: invoke signature validation on the packed signatures payload.
        harness.areAdminSignaturesValid(hex"1b", keccak256("op66"));
    }

    /// @dev Verifies that threshold being met before trailing malformed bytes returns true via short-circuit.
    function test_areAdminSignaturesValid_thresholdMetBeforeMalformedTrailingBytes_returnsTrue() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        bytes32 hash = keccak256("op67");
        bytes memory validSig = _signHash(ADMIN_PK_1, hash);
        bytes memory packed = abi.encodePacked(validSig, hex"00ffff");

        // Call: invoke signature validation with valid threshold signatures plus trailing bytes.
        bool actualIsValid = harness.areAdminSignaturesValid(packed, hash);

        // Verify: assert that signature validation succeeds for this input set.
        assertTrue(actualIsValid, "function should short-circuit after threshold");
    }

    /// @dev Verifies `LibOrganizationAdmin._areAdminSignaturesValid` parses mixed EOA and ERC-1271 signatures across
    /// multiple packed offsets.
    function test_NMADM_SIG_7_areAdminSignaturesValid_mixedEOA_ERC1271_EOA_offsetsParseCorrectly() public {
        address contractAdmin = address(0x5000000000000000000000000000000000000000);

        // Setup: install valid ERC-1271 bytecode at an address sorted between two EOA admins and require all three
        // signatures so the helper must parse every packed segment.
        vm.etch(contractAdmin, address(validSigner1271).code);
        assertTrue(
            uint160(admin2) < uint160(contractAdmin) && uint160(contractAdmin) < uint160(admin3),
            "test requires EOA -> ERC1271 -> EOA ordering"
        );
        _setMembersAndAdmins({
            members: buildArray(admin2, contractAdmin, admin3),
            admins: buildArray(admin2, contractAdmin, admin3),
            threshold: 3
        });

        bytes32 hash = keccak256("op65-mixed-offsets");
        bytes memory packed = abi.encodePacked(
            _signHash(ADMIN_PK_2, hash),
            _buildContractSignature({signer: contractAdmin, innerSig: hex"CAFEF00D123456"}),
            _signHash(ADMIN_PK_3, hash)
        );

        // Call: validate the sorted `EOA -> ERC1271 -> EOA` packed signature stream against the shared operation
        // hash.
        bool actualIsValid = harness.areAdminSignaturesValid(packed, hash);

        // Verify: the helper returns `true` after recovering each signer from the correct packed offset and reaching
        // the threshold on the third signature.
        assertTrue(actualIsValid, "mixed packed signatures should validate across all offsets");
    }
}
