// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

/**
 * @title StringUtils
 * @dev String utility functions for Foundry deployment scripts.
 *      Replaces OpenZeppelin's Strings library for 0.7.x compatibility.
 *
 *      This library uses a floating pragma (>=0.7.0 <0.9.0) to allow reuse by both
 *      platform scripts (0.8.33) and Safe deployment scripts (0.7.6).
 */
library StringUtils {
    /**
     * @dev Compares two strings for equality
     * @param a First string to compare
     * @param b Second string to compare
     * @return True if strings are equal
     */
    function stringEquals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @dev Converts a uint256 to its ASCII string decimal representation
     * @param value The uint256 value to convert
     * @return The string representation
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts an address to its ASCII string hexadecimal representation with 0x prefix
     * @param addr The address to convert
     * @return The hex string representation (42 characters including 0x)
     */
    function toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        bytes memory hexAlphabet = "0123456789abcdef";
        uint160 value = uint160(addr);
        for (uint256 i = 41; i > 1; i--) {
            buffer[i] = hexAlphabet[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}
