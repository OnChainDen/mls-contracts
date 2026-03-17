// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Merkle} from "murky/Merkle.sol";

import {MerkleUtils} from "libraries/MerkleUtils.sol";

/**
 * @dev MerkleUtilsHarness
 *      Test harness that exposes the internal MerkleUtils.computeAddressLeaf function
 *      via a public wrapper so it can be called from the test contract.
 */
contract MerkleUtilsHarness {
    /// @dev Exposes address-leaf computation for direct testing.
    /// @param addr Address to convert into a Merkle leaf.
    /// @return leaf Double-hashed Merkle leaf for the address.
    function computeAddressLeaf(address addr) external pure returns (bytes32) {
        return MerkleUtils.computeAddressLeaf(addr);
    }
}

/**
 * @dev MerkleUtilsTest
 *      Comprehensive tests for MerkleUtils library.
 *      Covers leaf computation (double hashing), determinism, collision resistance,
 *      and merkle proof verification via fuzz tests.
 *
 *      MerkleUtils.computeAddressLeaf uses double hashing:
 *        keccak256(bytes.concat(keccak256(abi.encode(addr))))
 *      This prevents second preimage attacks on merkle trees.
 *
 * @author Den Technologies Inc
 */
contract MerkleUtilsTest is Test {
    MerkleUtilsHarness public harness;
    Merkle public merkle;

    /// @dev Deploys the harness and Merkle helper used across fuzz cases.
    function setUp() public {
        harness = new MerkleUtilsHarness();
        merkle = new Merkle();
    }

    /// @dev Test case: A known address should produce a known leaf matching the double-hash formula (golden test).
    ///      Pre-computed: keccak256(bytes.concat(keccak256(abi.encode(address(0x1)))))
    function test_computeAddressLeaf_knownAddress_producesKnownLeaf() public view {
        address addr = address(0x1);

        // Precomputed expected leaf for address(0x1):
        // keccak256(bytes.concat(keccak256(abi.encode(address(0x1)))))
        bytes32 expectedLeaf = 0xb5d9d894133a730aa651ef62d26b0ffa846233c74177a591a4a896adfda97d22;

        bytes32 leaf = harness.computeAddressLeaf(addr);

        assertEq(leaf, expectedLeaf, "Leaf should match the pre-computed golden value");
        // Also verify it's non-zero
        assertTrue(leaf != bytes32(0), "Leaf should be non-zero");
    }

    /// @dev Test case: The double-hashed leaf should differ from a single-hashed value, verifying the library
    ///      applies the outer keccak256(bytes.concat(...)) wrap.
    function test_computeAddressLeaf_doubleHashing_leafDiffersFromSingleHash() public view {
        address addr = address(0x1234);

        bytes32 singleHash = keccak256(abi.encode(addr));
        bytes32 leaf = harness.computeAddressLeaf(addr);

        assertTrue(leaf != singleHash, "Double-hashed leaf should differ from single-hashed value");
    }

    /// @dev Test case: address(0) should produce a valid non-zero leaf.
    function test_computeAddressLeaf_addressZero_producesNonZeroLeaf() public view {
        bytes32 leaf = harness.computeAddressLeaf(address(0));

        assertTrue(leaf != bytes32(0), "address(0) should produce a non-zero leaf");
    }

    /// @dev Test case: Two different addresses should produce different leaves.
    function test_computeAddressLeaf_differentAddresses_produceDifferentLeaves() public view {
        bytes32 leaf1 = harness.computeAddressLeaf(address(0x1));
        bytes32 leaf2 = harness.computeAddressLeaf(address(0x2));

        assertTrue(leaf1 != leaf2, "Different addresses should produce different leaves");
    }

    /// @dev Test case: The same address should always produce the same leaf (deterministic).
    function test_computeAddressLeaf_sameAddress_alwaysSameLeaf() public view {
        address addr = address(0xDEAD);

        bytes32 leaf1 = harness.computeAddressLeaf(addr);
        bytes32 leaf2 = harness.computeAddressLeaf(addr);

        assertEq(leaf1, leaf2, "Same address should always produce the same leaf");
    }

    /// @dev Test case: No two random addresses should ever produce the same leaf (collision resistance).
    function testFuzz_computeAddressLeaf_noCollisions(address addr1, address addr2) public view {
        vm.assume(addr1 != addr2);
        bytes32 leaf1 = harness.computeAddressLeaf(addr1);
        bytes32 leaf2 = harness.computeAddressLeaf(addr2);
        assertTrue(leaf1 != leaf2, "Different addresses should never collide");
    }

    /// @dev Test case: Random tree sizes (2-100 leaves) should produce verifiable merkle proofs for each leaf.
    function testFuzz_computeAddressLeaf_randomTreeSize_leafVerifiable(uint8 rawTreeSize) public view {
        uint256 treeSize = bound(rawTreeSize, 2, 100);

        // Generate unique addresses and compute their leaves
        bytes32[] memory leaves = new bytes32[](treeSize);
        for (uint256 i = 0; i < treeSize; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            address addr = address(uint160(i + 1)); // Safe: i+1 bounded, addresses 0x1, 0x2, ...
            leaves[i] = harness.computeAddressLeaf(addr);
        }

        // Build merkle root and verify each leaf with its proof
        bytes32 root = merkle.getRoot(leaves);

        for (uint256 i = 0; i < treeSize; i++) {
            bytes32[] memory proof = merkle.getProof(leaves, i);
            bool verified = MerkleProof.verify(proof, root, leaves[i]);
            assertTrue(verified, string.concat("Leaf ", vm.toString(i), " should verify with correct proof"));
        }
    }

    /// @dev Test case: Modifying any single byte of a valid merkle proof should always cause verification to fail.
    function testFuzz_computeAddressLeaf_modifiedProofByteAlwaysInvalidatesVerification(
        uint8 rawTreeSize,
        uint8 leafIndex,
        uint8 proofByteIndex
    ) public view {
        // Build a tree with at least 2 leaves (need proof with >= 1 element)
        uint256 treeSize = bound(rawTreeSize, 2, 20);
        leafIndex = uint8(bound(leafIndex, 0, treeSize - 1));

        bytes32[] memory leaves = new bytes32[](treeSize);
        for (uint256 i = 0; i < treeSize; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            address addr = address(uint160(i + 1)); // Safe: i+1 bounded
            leaves[i] = harness.computeAddressLeaf(addr);
        }

        bytes32 root = merkle.getRoot(leaves);
        bytes32[] memory proof = merkle.getProof(leaves, leafIndex);

        // Skip if proof is empty (single-leaf tree edge case)
        if (proof.length == 0) {
            return;
        }

        // Select a proof element and byte to corrupt
        uint256 proofElementIndex = uint256(proofByteIndex) % proof.length;
        uint256 bytePosition = uint256(proofByteIndex) % 32;

        // Flip exactly one bit in the selected byte to guarantee a single-byte mutation.
        bytes32 original = proof[proofElementIndex];
        bytes32 mutationMask = bytes32(uint256(1) << ((31 - bytePosition) * 8));
        bytes32 corrupted = original ^ mutationMask;
        proof[proofElementIndex] = corrupted;

        bool verified = MerkleProof.verify(proof, root, leaves[leafIndex]);
        assertFalse(verified, "Corrupted proof should fail verification");
    }
}
