// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {ArrayBuilders} from "test/helpers/ArrayBuilders.sol";
import {
    MockERC1271RevertingSigner,
    MockERC1271ValidSigner,
    MockERC1271WrongMagicSigner
} from "test/helpers/MockERC1271Signers.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";
import {OrganizationAdminStateHarness} from "test/organization/harness/OrganizationAdminStateHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Shared test setup/helpers for organization admin tests.
 *      Centralizes fixture creation, signature packing, and auth-param builders.
 */
abstract contract OrganizationAdminTestBase is Test, SignatureTestHelpers, ArrayBuilders {
    /// @dev Deterministic guardian used by `onlyGuardian`-gated base functions.
    address internal constant GUARDIAN = address(0xBEEF);

    /// @dev Deterministic non-guardian used for access-control negative tests.
    address internal constant NON_GUARDIAN = address(0xCAFE);

    /// @dev Deterministic EOA admin private keys.
    uint256 internal constant ADMIN_PK_1 = 0xA11CE;
    uint256 internal constant ADMIN_PK_2 = 0xB0B;
    uint256 internal constant ADMIN_PK_3 = 0xC0C;

    /// @dev Shared harness state surface used by helper utilities.
    OrganizationAdminStateHarness internal stateHarness;

    /// @dev Frequently used deterministic EOA admin addresses.
    address internal admin1;
    address internal admin2;
    address internal admin3;

    /// @dev ERC-1271 signer mocks used by auth/signature tests.
    MockERC1271ValidSigner internal validSigner1271;
    MockERC1271WrongMagicSigner internal wrongMagicSigner1271;
    MockERC1271RevertingSigner internal revertingSigner1271;

    /**
     * @dev Deploys the concrete harness for the current test suite.
     *      Implemented by each child test contract to choose the correct harness type.
     */
    function _deployHarness() internal virtual returns (OrganizationAdminStateHarness);

    /**
     * @dev Deploys harness/mocks and configures guardian storage.
     */
    function setUp() public virtual {
        // Deploy a fresh harness per test to keep storage isolated.
        stateHarness = _deployHarness();

        // Deterministically derive addresses from test private keys.
        admin1 = vm.addr(ADMIN_PK_1);
        admin2 = vm.addr(ADMIN_PK_2);
        admin3 = vm.addr(ADMIN_PK_3);

        // Deploy reusable ERC-1271 mock signers used by mixed-signature tests.
        validSigner1271 = new MockERC1271ValidSigner();
        wrongMagicSigner1271 = new MockERC1271WrongMagicSigner();
        revertingSigner1271 = new MockERC1271RevertingSigner();

        // Default guardian is required for `onlyGuardian`-gated external calls.
        stateHarness.setGuardian(GUARDIAN);
    }

    /**
     * @dev Configures member and admin mappings and sets admin count/threshold.
     */
    function _setMembersAndAdmins(address[] memory members, address[] memory admins, uint256 threshold) internal {
        // Member mapping must be configured before admin mapping because admin adds require membership.
        _setMembers(members, true);
        _setAdmins(admins, true);
        // Keep scalar storage in sync with configured mapping state.
        stateHarness.setAdminCount(admins.length);
        stateHarness.setVotingThreshold(threshold);
    }

    /**
     * @dev Sets member status for each address in `members`.
     */
    function _setMembers(address[] memory members, bool isMember) internal {
        for (uint256 i = 0; i < members.length; i++) {
            stateHarness.setMemberStatus(members[i], isMember);
        }
    }

    /**
     * @dev Sets admin status for each address in `admins`.
     */
    function _setAdmins(address[] memory admins, bool isAdmin) internal {
        for (uint256 i = 0; i < admins.length; i++) {
            stateHarness.setAdminStatus(admins[i], isAdmin);
        }
    }

    /**
     * @dev Computes operation hash via harness wrapper.
     */
    function _computeOperationHash(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 expirationTimestamp,
        bool isApproval
    ) internal view returns (bytes32) {
        return stateHarness.getAdminOperationHash({
            operationType: operationType,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: isApproval
        });
    }

    /**
     * @dev Builds sorted packed EOA signatures for `operationHash`.
     */
    function _buildSortedEOASignatures(bytes32 operationHash, uint256[] memory privateKeys)
        internal
        view
        returns (bytes memory)
    {
        address[] memory signers = new address[](privateKeys.length);
        bytes[] memory signatures = new bytes[](privateKeys.length);

        for (uint256 i = 0; i < privateKeys.length; i++) {
            // Build signer/signature pairs first, then sort once to satisfy strict signer ordering.
            signers[i] = vm.addr(privateKeys[i]);
            signatures[i] = _signHash(privateKeys[i], operationHash);
        }

        return _sortAndConcatSignatures(signers, signatures);
    }

    /**
     * @dev Sorts signer/signature pairs by signer address and concatenates the signatures.
     */
    function _sortAndConcatSignatures(address[] memory signers, bytes[] memory signatures)
        internal
        pure
        returns (bytes memory)
    {
        require(signers.length == signatures.length, "length mismatch");

        for (uint256 i = 0; i < signers.length; i++) {
            for (uint256 j = i + 1; j < signers.length; j++) {
                if (uint160(signers[j]) < uint160(signers[i])) {
                    // Swap signer/signature together to preserve pair integrity.
                    (signers[i], signers[j]) = (signers[j], signers[i]);
                    (signatures[i], signatures[j]) = (signatures[j], signatures[i]);
                }
            }
        }

        return _concatSignatures(signatures);
    }

    /**
     * @dev Builds auth params signed by EOA admins for a specific operation.
     */
    function _buildAdminAuthParamsForEOA(
        OperationType operationType,
        bytes memory operationData,
        bool isApproval,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory) {
        // This hash must match the exact in-contract typed-data hash used by authorization checks.
        bytes32 operationHash = _computeOperationHash({
            operationType: operationType,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: isApproval
        });
        bytes memory signatures = _buildSortedEOASignatures(operationHash, privateKeys);
        return AdminAuthParams({salt: salt, expirationTimestamp: expirationTimestamp, signatures: signatures});
    }

    /**
     * @dev Computes admin-operation nonce via harness wrapper.
     */
    function _computeNonce(OperationType operationType, bytes memory operationData, uint256 salt)
        internal
        view
        returns (uint256)
    {
        return stateHarness.computeNonce(operationType, operationData, salt);
    }

    /**
     * @dev Returns true when nonce is marked used.
     */
    function _isNonceUsed(uint256 nonce) internal view returns (bool) {
        return stateHarness.getUsedNonce(nonce);
    }

    /**
     * @dev Encodes operation data exactly as `OrganizationAdminBase.modifyAdmins`.
     */
    function _encodeOperationDataForModifyAdmins(
        address[] memory adminsToAdd,
        address[] memory adminsToRemove,
        uint256 newVotingThreshold
    ) internal pure returns (bytes memory) {
        // The base contract signs hashes of each array (not raw array ABI bytes directly).
        return abi.encode(keccak256(abi.encode(adminsToAdd)), keccak256(abi.encode(adminsToRemove)), newVotingThreshold);
    }

    /**
     * @dev Asserts the standard `onlyGuardian` revert shape.
     */
    function _expectOnlyGuardianRevert(address caller) internal {
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, caller, GUARDIAN));
    }

    /**
     * @dev Asserts nonce-usage status with a descriptive message.
     */
    function _assertNonceUsed(uint256 nonce, bool expectedUsed, string memory reason) internal view {
        assertEq(_isNonceUsed(nonce), expectedUsed, reason);
    }

    /**
     * @dev Asserts signature-recovery failure from malformed/invalid packed signatures.
     */
    function _expectSignatureRecoveryFailure() internal {
        vm.expectRevert(SignatureUtils.SignatureRecoveryFailed.selector);
    }

    /**
     * @dev Asserts nonce-already-used revert for a specific nonce.
     */
    function _expectNonceAlreadyUsed(uint256 nonce) internal {
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
    }
}
