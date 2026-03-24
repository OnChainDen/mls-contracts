// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {
    ImplementationWhitelistImplementation
} from "implementation-whitelist/ImplementationWhitelistImplementation.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @dev Test-only namespaced storage used to verify storage compatibility across whitelist upgrades.
 *      Use this in upgrade tests that need to persist and read migration markers through proxy transitions.
 */
library LibImplementationWhitelistTestStorage {
    struct Layout {
        uint256 marker;
    }

    bytes32 internal constant STORAGE_LOCATION = 0xe0470f43d0023f152d2ec16dedec85d2f8e61ce5f9573f1ed85df649f053a500;

    /**
     * @dev Returns the dedicated storage namespace used by whitelist upgrade harness tests.
     * @return storageLayout Storage pointer rooted at `STORAGE_LOCATION`.
     */
    function layout() internal pure returns (Layout storage storageLayout) {
        assembly {
            storageLayout.slot := STORAGE_LOCATION
        }
    }
}

/**
 * @dev Test harness that exposes internal whitelist mutation helpers via external wrappers.
 *      Use this for unit tests that need to call internal whitelist paths directly.
 */
contract ImplementationWhitelistHarness is ImplementationWhitelistImplementation {
    /**
     * @dev Calls `_addToWhitelist` so tests can exercise internal add flows directly.
     * @param contractType Contract type bucket being mutated.
     * @param implementations Implementation addresses to add to the whitelist bucket.
     */
    function exposeAddToWhitelist(ContractType contractType, address[] calldata implementations) external {
        _addToWhitelist(contractType, implementations);
    }

    /**
     * @dev Calls `_removeFromWhitelist` so tests can exercise internal remove flows directly.
     * @param contractType Contract type bucket being mutated.
     * @param implementations Implementation addresses to remove from the whitelist bucket.
     */
    function exposeRemoveFromWhitelist(ContractType contractType, address[] calldata implementations) external {
        _removeFromWhitelist(contractType, implementations);
    }
}

/**
 * @dev Upgrade-target harness used in UUPS integration tests for whitelist proxies.
 *      Use this when asserting post-upgrade execution and storage persistence behavior.
 */
contract ImplementationWhitelistV2Harness is ImplementationWhitelistHarness {
    /**
     * @dev Stores a marker in dedicated test storage to validate upgrade storage continuity.
     * @param marker Marker value written for later post-upgrade assertions.
     */
    function setMigrationMarker(uint256 marker) external {
        LibImplementationWhitelistTestStorage.layout().marker = marker;
    }

    /**
     * @dev Reads the migration marker from dedicated test storage.
     * @return marker Marker previously written via `setMigrationMarker`.
     */
    function getMigrationMarker() external view returns (uint256 marker) {
        marker = LibImplementationWhitelistTestStorage.layout().marker;
    }

    /**
     * @dev Returns a fixed version tag used to prove V2 logic is active after upgrade.
     * @return versionNumber Constant version value for this harness target.
     */
    function version() external pure returns (uint256 versionNumber) {
        versionNumber = 2;
    }
}

/**
 * @dev Non-UUPS implementation probe used for negative upgrade-safety tests.
 *      Use this when asserting upgrades reject implementations without UUPS support.
 */
contract ImplementationWhitelistNonUUPS {}

/**
 * @dev UUPS implementation probe with an incompatible UUID.
 *      Use this for negative tests that verify ERC-1822 UUID compatibility checks.
 */
contract ImplementationWhitelistWrongUUID is UUPSUpgradeable {
    /**
     * @dev Returns an intentionally incorrect UUID for negative upgrade-path testing.
     * @return uuid Incompatible UUID value expected to fail UUPS compatibility checks.
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function proxiableUUID() public pure override returns (bytes32 uuid) {
        uuid = bytes32(uint256(0xDEAD));
    }

    /**
     * @dev No-op authorization hook for harness use only.
     * @param newImplementation Candidate implementation address passed by UUPS upgrade flow.
     */
    function _authorizeUpgrade(address newImplementation) internal view override {
        assembly {
            pop(newImplementation)
        }
    }
}
