// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {LibOrganizationAdminSuiteBase} from "test/organization/helpers/LibOrganizationAdminSuiteBase.sol";

/**
 * @dev Unit tests for signature-checking helpers in `LibOrganizationAdmin`.
 */
contract LibOrganizationAdminSignaturesTest is LibOrganizationAdminSuiteBase {
    /// @dev Empty signatures returns false.
    function test_areAdminSignaturesValid_emptySignatures_returnsFalse() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        assertFalse(harness.areAdminSignaturesValid(bytes(""), keccak256("op")), "empty signatures should be false");
    }

    /// @dev Exactly threshold valid signatures returns true.
    function test_areAdminSignaturesValid_exactThreshold_returnsTrue() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 hash = keccak256("op59");
        bytes memory signatures = _buildSortedEOASignatures(hash, buildUint256Array(ADMIN_PK_1, ADMIN_PK_2));

        assertTrue(harness.areAdminSignaturesValid(signatures, hash), "exact threshold signatures should validate");
    }

    /// @dev More than threshold signatures returns true via early exit.
    function test_areAdminSignaturesValid_moreThanThreshold_returnsTrue() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        bytes32 hash = keccak256("op60");
        bytes memory signatures = _buildSortedEOASignatures(hash, buildUint256Array(ADMIN_PK_1, ADMIN_PK_2));

        assertTrue(harness.areAdminSignaturesValid(signatures, hash), "more-than-threshold signatures should validate");
    }

    /// @dev Fewer than threshold valid signatures returns false.
    function test_areAdminSignaturesValid_fewerThanThreshold_returnsFalse() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 hash = keccak256("op61");
        bytes memory signatures = _buildSortedEOASignatures(hash, buildUint256Array(ADMIN_PK_1));

        assertFalse(harness.areAdminSignaturesValid(signatures, hash), "fewer-than-threshold signatures should fail");
    }

    /// @dev Duplicate signer reverts DuplicateOrOutOfOrderAdminSigner.
    function test_areAdminSignaturesValid_duplicateSigner_revertsDuplicateOrOutOfOrder() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 hash = keccak256("op62");
        bytes memory sig = _signHash(ADMIN_PK_1, hash);
        bytes memory signatures = abi.encodePacked(sig, sig);

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, admin1, admin1)
        );
        harness.areAdminSignaturesValid(signatures, hash);
    }

    /// @dev Out-of-order signer reverts DuplicateOrOutOfOrderAdminSigner.
    function test_areAdminSignaturesValid_outOfOrderSigner_revertsDuplicateOrOutOfOrder() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 hash = keccak256("op63");
        bytes memory sig1 = _signHash(ADMIN_PK_1, hash);
        bytes memory sig2 = _signHash(ADMIN_PK_2, hash);

        bytes memory outOfOrder;
        address signer1 = vm.addr(ADMIN_PK_1);
        address signer2 = vm.addr(ADMIN_PK_2);

        if (signer1 < signer2) {
            outOfOrder = abi.encodePacked(sig2, sig1);
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, signer1, signer2)
            );
        } else {
            outOfOrder = abi.encodePacked(sig1, sig2);
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, signer2, signer1)
            );
        }

        harness.areAdminSignaturesValid(outOfOrder, hash);
    }

    /// @dev Non-admin signer reverts SignerIsNotAdmin.
    function test_areAdminSignaturesValid_nonAdminSigner_revertsSignerIsNotAdmin() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 nonAdminPk = 0xF00D;
        address nonAdmin = vm.addr(nonAdminPk);
        bytes32 hash = keccak256("op64");
        bytes memory sig = _signHash(nonAdminPk, hash);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, nonAdmin));
        harness.areAdminSignaturesValid(sig, hash);
    }

    /// @dev Mixed EOA + ERC-1271 signers succeed when globally sorted.
    function test_areAdminSignaturesValid_mixedEOAAndERC1271_sorted_succeeds() public {
        address contractAdmin = address(validSigner1271);
        _setMembersAndAdmins({
            members: buildArray(admin1, contractAdmin), admins: buildArray(admin1, contractAdmin), threshold: 2
        });

        bytes32 hash = keccak256("op65");
        address[] memory signers = buildArray(admin1, contractAdmin);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signHash(ADMIN_PK_1, hash);
        signatures[1] = _buildContractSignature({signer: contractAdmin, innerSig: hex"1234"});

        bytes memory packed = _sortAndConcatSignatures(signers, signatures);
        assertTrue(harness.areAdminSignaturesValid(packed, hash), "mixed sorted signatures should validate");
    }

    /// @dev Malformed signature encoding reverts SignatureRecoveryFailed.
    function test_areAdminSignaturesValid_malformedEncoding_revertsSignatureRecoveryFailed() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        _expectSignatureRecoveryFailure();
        harness.areAdminSignaturesValid(hex"1b", keccak256("op66"));
    }

    /// @dev Threshold met before trailing malformed bytes returns true (short-circuit).
    function test_areAdminSignaturesValid_thresholdMetBeforeMalformedTrailingBytes_returnsTrue() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        bytes32 hash = keccak256("op67");
        bytes memory validSig = _signHash(ADMIN_PK_1, hash);
        bytes memory packed = abi.encodePacked(validSig, hex"00ffff");

        assertTrue(harness.areAdminSignaturesValid(packed, hash), "function should short-circuit after threshold");
    }
}
