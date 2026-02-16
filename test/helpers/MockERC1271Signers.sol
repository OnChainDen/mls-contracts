// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title Mock ERC-1271 Signer Contracts
 * @dev A collection of mock contracts used to test ERC-1271 signature validation
 *      in SignatureUtils. Each mock simulates a specific behavior that the library
 *      must handle correctly (valid response, wrong magic, reverts, etc.).
 * @author Den Technologies Inc
 */

/// @dev Returns the correct ERC-1271 magic value (0x1626ba7e) for any signature.
///      Used to test the happy-path where a contract validates a signature successfully.
contract MockERC1271ValidSigner is IERC1271 {
    /// @param hash The hash that was signed (unused)
    /// @param signature The signature bytes (unused)
    /// @return The ERC-1271 magic value (0x1626ba7e)
    function isValidSignature(bytes32 hash, bytes memory signature) external pure override returns (bytes4) {
        return IERC1271.isValidSignature.selector; // 0x1626ba7e
    }
}

/// @dev Returns an incorrect magic value (0xdeadbeef) for any signature.
///      Used to verify that SignatureUtils rejects non-magic return values.
contract MockERC1271WrongMagicSigner is IERC1271 {
    /// @param hash The hash that was signed (unused)
    /// @param signature The signature bytes (unused)
    /// @return An incorrect magic value (0xdeadbeef)
    function isValidSignature(bytes32 hash, bytes memory signature) external pure override returns (bytes4) {
        return 0xdeadbeef;
    }
}

/// @dev Always reverts when isValidSignature is called.
///      Used to verify that SignatureUtils handles staticcall failures gracefully.
contract MockERC1271RevertingSigner is IERC1271 {
    /// @param hash The hash that was signed (unused)
    /// @param signature The signature bytes (unused)
    /// @return Never returns; always reverts
    function isValidSignature(bytes32 hash, bytes memory signature) external pure override returns (bytes4) {
        revert("MockERC1271RevertingSigner: always reverts");
    }
}

/// @dev Enters an infinite loop consuming all available gas.
///      Used to verify that SignatureUtils returns false (not revert) when the
///      staticcall runs out of gas.
contract MockERC1271GasConsumer is IERC1271 {
    /// @param hash The hash that was signed (unused)
    /// @param signature The signature bytes (unused)
    /// @return Never returns; consumes all gas in infinite loop
    function isValidSignature(bytes32 hash, bytes memory signature) external pure override returns (bytes4) {
        // Infinite loop that consumes all gas
        while (true) {}
        return 0x00000000; // unreachable, but required for compilation
    }
}

/// @dev Returns fewer than 32 bytes from isValidSignature via assembly.
///      Used to verify the `result.length >= 32` check in _isValidERC1271SignatureNow.
contract MockERC1271ShortReturnSigner {
    /// @dev Returns only 31 bytes (one short of the minimum 32) via assembly
    // forgefmt: disable-next-item
    fallback() external payable {
        // Return only 31 bytes (one byte short of the minimum 32)
        assembly {
            mstore(0x00, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            return(0x00, 31)
        }
    }
}

/// @dev Returns exactly 0 bytes from isValidSignature via assembly.
///      Used to verify the `result.length >= 32` check catches empty results.
contract MockERC1271EmptyReturnSigner {
    /// @dev Returns exactly 0 bytes via assembly
    // forgefmt: disable-next-item
    fallback() external payable {
        assembly {
            return(0x00, 0)
        }
    }
}

/// @dev Returns >32 bytes starting with the correct magic value.
///      Used to verify that extra trailing bytes don't break validation
///      (the library should still accept as long as the first 4 bytes decode correctly).
contract MockERC1271ExtraBytesSigner is IERC1271 {
    /// @param hash The hash that was signed (unused)
    /// @param signature The signature bytes (unused)
    /// @return The ERC-1271 magic value; returns 64 bytes total (magic + 32 extra)
    // forgefmt: disable-next-item
    function isValidSignature(bytes32 hash, bytes memory signature) external pure override returns (bytes4) {
        // Return 64 bytes: magic value (padded to 32 bytes) + 32 extra bytes
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x20), 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef)
            return(ptr, 64)
        }
    }
}

/// @dev Returns >1000 bytes starting with the correct magic value.
///      Used to verify that very large return data is handled correctly.
contract MockERC1271LargeReturnSigner is IERC1271 {
    /// @param hash The hash that was signed (unused)
    /// @param signature The signature bytes (unused)
    /// @return The ERC-1271 magic value; returns 1024 bytes total
    // forgefmt: disable-next-item
    function isValidSignature(bytes32 hash, bytes memory signature) external pure override returns (bytes4) {
        assembly {
            let ptr := mload(0x40)
            // Write magic value in first 32-byte word
            mstore(ptr, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            // Fill remaining words with non-zero data
            for { let i := 0x20 } lt(i, 1024) { i := add(i, 0x20) } {
                mstore(add(ptr, i), 0xabababababababababababababababababababababababababababababababab)
            }
            return(ptr, 1024)
        }
    }
}

/// @dev Attempts to modify state (sstore) during a staticcall via inline assembly.
///      When called via staticcall, the EVM will revert at the SSTORE opcode,
///      so SignatureUtils should see success=false and return false gracefully.
///      We use a fallback with assembly to bypass the compiler's `view` enforcement.
contract MockERC1271StateModifierSigner {
    /// @dev Attempts to modify state via sstore; reverts when called via staticcall
    // forgefmt: disable-next-item
    fallback() external payable {
        assembly {
            // Attempt to modify storage slot 0 (will cause staticcall revert)
            sstore(0, add(sload(0), 1))
            // If somehow this doesn't revert, return the magic value
            mstore(0x00, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            return(0x00, 32)
        }
    }
}

/// @dev Returns the correct magic value right-padded with a non-zero byte.
///      For example: 0x1626ba7e00...01. The abi.decode should still extract
///      only the first 4 bytes (0x1626ba7e), so this should be considered valid.
contract MockERC1271RightPaddedSigner is IERC1271 {
    /// @param hash The hash that was signed (unused)
    /// @param signature The signature bytes (unused)
    /// @return Magic value right-padded with non-zero byte; abi.decode may revert
    // forgefmt: disable-next-item
    function isValidSignature(bytes32 hash, bytes memory signature) external pure override returns (bytes4) {
        assembly {
            let ptr := mload(0x40)
            // Magic value in first 4 bytes, non-zero byte at byte 31
            mstore(ptr, 0x1626ba7e00000000000000000000000000000000000000000000000000000001)
            return(ptr, 32)
        }
    }
}

/// @dev Returns exactly 31 bytes (one short of valid) to test the length boundary.
///      This is distinct from MockERC1271ShortReturnSigner which also returns 31 bytes,
///      but this variant is used specifically for boundary test 84.5.
contract MockERC1271Return31BytesSigner {
    /// @dev Returns exactly 31 bytes (one short of valid) via assembly
    // forgefmt: disable-next-item
    fallback() external payable {
        assembly {
            mstore(0x00, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            return(0x00, 31)
        }
    }
}

/// @dev Returns an arbitrary 4-byte value from isValidSignature.
///      Used to verify that only IERC1271's exact magic value is accepted.
contract MockERC1271CustomReturn is IERC1271 {
    bytes4 private immutable RETURN_VALUE;

    /// @param returnValue The bytes4 value to return from isValidSignature
    constructor(bytes4 returnValue) {
        RETURN_VALUE = returnValue;
    }

    /// @param hash The hash that was signed (unused)
    /// @param signature The signature bytes (unused)
    /// @return The configured return value (RETURN_VALUE)
    function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4) {
        return RETURN_VALUE;
    }
}
