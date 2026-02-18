// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BitmaskHelpers} from "test/helpers/BitmaskHelpers.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";
import {
    LibOrganizationAdminHarness
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Stateful invariant handler for `LibOrganizationAdmin` invariants.
 *      Mutations are executed through library entry points and mirrored into a local model.
 */
contract LibOrganizationAdminInvariantHandler is BitmaskHelpers, SignatureTestHelpers {
    /// @dev Harness under test.
    LibOrganizationAdminHarness public immutable harness;

    /// @dev Known private keys that can produce valid EOA signatures during stateful testing.
    uint256 public immutable adminPk1;
    uint256 public immutable adminPk2;

    /// @dev Known signer addresses derived from admin private keys.
    address public immutable admin1;
    address public immutable admin2;

    /// @dev Additional tracked member addresses that may be added/removed as admins.
    address public immutable member3;
    address public immutable member4;

    /// @dev Model: tracked admin mapping.
    mapping(address => bool) public modelIsAdmin;

    /// @dev Model: tracked consumed nonces.
    mapping(uint256 => bool) public modelNonceUsed;

    /// @dev Model: admin count and threshold.
    uint256 public modelAdminCount;
    uint256 public modelVotingThreshold;

    /// @dev Tracked addresses participating in admin mutations.
    address[] internal trackedAddresses;

    /// @dev Tracked nonces that have been observed as consumed.
    uint256[] internal trackedUsedNonces;

    /**
     * @dev Initializes harness state + model with 2 admins and threshold 1.
     */
    constructor(
        LibOrganizationAdminHarness harness_,
        uint256 adminPk1_,
        uint256 adminPk2_,
        address member3_,
        address member4_
    ) {
        harness = harness_;

        adminPk1 = adminPk1_;
        adminPk2 = adminPk2_;

        admin1 = vm.addr(adminPk1_);
        admin2 = vm.addr(adminPk2_);

        member3 = member3_;
        member4 = member4_;

        trackedAddresses.push(admin1);
        trackedAddresses.push(admin2);
        trackedAddresses.push(member3);
        trackedAddresses.push(member4);

        // Keep all tracked addresses as members for admin-membership invariant (admin => member).
        harness.setMemberStatus(admin1, true);
        harness.setMemberStatus(admin2, true);
        harness.setMemberStatus(member3, true);
        harness.setMemberStatus(member4, true);

        // Initial admin set: {admin1, admin2}, threshold = 1.
        harness.setAdminStatus(admin1, true);
        harness.setAdminStatus(admin2, true);
        harness.setAdminCount(2);
        harness.setVotingThreshold(1);

        modelIsAdmin[admin1] = true;
        modelIsAdmin[admin2] = true;
        modelAdminCount = 2;
        modelVotingThreshold = 1;
    }

    /**
     * @dev Stateful operation: fuzzed add/remove/threshold mutation through library path.
     */
    function modifyAdmins(uint8 addMask, uint8 removeMask, uint8 thresholdSeed) external {
        // Candidate universe is intentionally fixed to keep model comparison simple and explicit.
        address[] memory candidates = new address[](4);
        candidates[0] = admin1;
        candidates[1] = admin2;
        candidates[2] = member3;
        candidates[3] = member4;

        uint256 addLength = _popcountLowerBits(addMask, 4);
        uint256 removeLength = _popcountLowerBits(removeMask, 4);

        // Build concrete calldata arrays from compact bitmasks.
        address[] memory adminsToAdd = new address[](addLength);
        address[] memory adminsToRemove = new address[](removeLength);

        uint256 addIndex;
        uint256 removeIndex;
        for (uint256 i = 0; i < candidates.length; i++) {
            if (((addMask >> i) & 1) == 1) {
                adminsToAdd[addIndex] = candidates[i];
                addIndex++;
            }
            if (((removeMask >> i) & 1) == 1) {
                adminsToRemove[removeIndex] = candidates[i];
                removeIndex++;
            }
        }

        uint256 newThreshold = thresholdSeed % 6;

        // Use low-level call so invariant runs continue even when a mutation intentionally reverts.
        (bool success,) = address(harness)
            .call(abi.encodeCall(harness.modifyAdminsViaLibrary, (adminsToAdd, adminsToRemove, newThreshold)));

        if (success) {
            // Mirror successful mutation in model (same add-first/remove-second ordering as library).
            for (uint256 i = 0; i < adminsToAdd.length; i++) {
                address adminToAdd = adminsToAdd[i];
                if (!modelIsAdmin[adminToAdd]) {
                    modelIsAdmin[adminToAdd] = true;
                    modelAdminCount++;
                }
            }

            for (uint256 i = 0; i < adminsToRemove.length; i++) {
                address adminToRemove = adminsToRemove[i];
                if (modelIsAdmin[adminToRemove]) {
                    modelIsAdmin[adminToRemove] = false;
                    modelAdminCount--;
                }
            }

            modelVotingThreshold = newThreshold;
        }
    }

    /**
     * @dev Stateful operation: consume a nonce through admin auth validation when feasible.
     */
    function consumeNonceThroughValidation(uint256 saltSeed, bytes32 payloadSeed, bool isApproval) external {
        (address[] memory signingAdmins, uint256[] memory signingPks) = _knownSigningAdmins();

        // Cannot construct valid signatures when threshold exceeds available known-signing admins.
        if (signingAdmins.length < modelVotingThreshold || modelVotingThreshold == 0) {
            return;
        }

        bytes memory operationData = abi.encode("invariant", payloadSeed, uint256(1));
        uint256 salt = uint256(keccak256(abi.encode(saltSeed, payloadSeed, isApproval)));
        uint256 expiration = block.timestamp + 1 hours;

        // Recompute the exact typed-data hash used by production auth logic.
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: isApproval
        });

        bytes[] memory signatures = new bytes[](signingPks.length);
        for (uint256 i = 0; i < signingPks.length; i++) {
            signatures[i] = _signHash(signingPks[i], operationHash);
        }

        bytes memory packed = _sortAndConcatSignatures(signingAdmins, signatures);
        AdminAuthParams memory auth = AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: packed});

        // Same reason as above: absorb expected failures and keep the stateful sequence progressing.
        (bool success,) = address(harness)
            .call(
                abi.encodeCall(
                    harness.validateAdminAuthAndConsumeNonceOrRevert,
                    (OperationType.ModifyAdmins, operationData, isApproval, auth)
                )
            );

        if (success) {
            uint256 nonce = harness.computeNonce(OperationType.ModifyAdmins, operationData, salt);
            if (!modelNonceUsed[nonce]) {
                modelNonceUsed[nonce] = true;
                trackedUsedNonces.push(nonce);
            }
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

    /**
     * @dev Returns tracked used nonce count.
     */
    function trackedUsedNonceCount() external view returns (uint256) {
        return trackedUsedNonces.length;
    }

    /**
     * @dev Returns tracked used nonce at index.
     */
    function trackedUsedNonceAt(uint256 index) external view returns (uint256) {
        return trackedUsedNonces[index];
    }

    /**
     * @dev Returns known model-admin set that can sign (EOA keys available).
     */
    function _knownSigningAdmins() internal view returns (address[] memory signers, uint256[] memory privateKeys) {
        uint256 count;
        if (modelIsAdmin[admin1]) count++;
        if (modelIsAdmin[admin2]) count++;

        // Return only the currently-active known signers so generated signatures can pass ordering checks.
        signers = new address[](count);
        privateKeys = new uint256[](count);

        uint256 index;
        if (modelIsAdmin[admin1]) {
            signers[index] = admin1;
            privateKeys[index] = adminPk1;
            index++;
        }
        if (modelIsAdmin[admin2]) {
            signers[index] = admin2;
            privateKeys[index] = adminPk2;
        }
    }

    /**
     * @dev Sorts signer/signature pairs and concatenates signatures.
     */
    function _sortAndConcatSignatures(address[] memory signers, bytes[] memory signatures)
        internal
        pure
        returns (bytes memory)
    {
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
}
