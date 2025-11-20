// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { LibUpgradeAuthorization } from "./libraries/LibUpgradeAuthorization.sol";
import { UpgradeAuthorizationStorage } from "./libraries/UpgradeAuthorizationStorage.sol";

/**
 * @title Base UUPS Implementation
 * @notice Base contract for UUPS upgradeable implementations with authorization
 * @dev All implementation contracts should inherit from this contract
 * @author Den Technologies Inc
 */
abstract contract BaseUUPSImplementation is UUPSUpgradeable, Initializable {
    /**
     * @notice Error thrown when upgrade authorization fails
     */
    error UpgradeAuthorizationFailed(string reason);

    /**
     * @notice Initialize the base UUPS implementation
     * @param whitelistAddress The address of the implementation whitelist contract
     * @param contractType The contract type (0 = Account, 1 = Organization)
     */
    function __BaseUUPSImplementation_init(address whitelistAddress, uint8 contractType) internal onlyInitializing {
        __UUPSUpgradeable_init();
        UpgradeAuthorizationStorage.Layout storage upgradeAuthLayout = UpgradeAuthorizationStorage.layout();
        upgradeAuthLayout.whitelistAddress = whitelistAddress;
        upgradeAuthLayout.contractType = contractType;
    }

    /**
     * @notice Upgrade the implementation to a new address with authorization
     * @param newImplementation The new implementation address
     * @param whitelistSetId The whitelist set ID to validate against
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this upgrade
     */
    function upgradeToWithAuthorization(
        address newImplementation,
        uint256 whitelistSetId,
        uint256 salt,
        bytes calldata signatures
    )
        external
    {
        LibUpgradeAuthorization.validateUpgradeAuthorization(newImplementation, whitelistSetId, salt, signatures);
        _upgradeToAndCallUUPS(newImplementation, "");
    }

    /**
     * @notice Upgrade the implementation to a new address and call a function with authorization
     * @param newImplementation The new implementation address
     * @param data The calldata to call on the new implementation
     * @param whitelistSetId The whitelist set ID to validate against
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this upgrade
     */
    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes memory data,
        uint256 whitelistSetId,
        uint256 salt,
        bytes calldata signatures
    )
        external
    {
        LibUpgradeAuthorization.validateUpgradeAuthorization(newImplementation, whitelistSetId, salt, signatures);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    /**
     * @notice Authorize an upgrade (required by UUPSUpgradeable)
     * @dev This function is called by UUPSUpgradeable before upgrading
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override {
        // Authorization is handled by upgradeToWithAuthorization and upgradeToAndCallWithAuthorization
        // This function should not be called directly - it's a safety check
        revert UpgradeAuthorizationFailed("Use upgradeToWithAuthorization or upgradeToAndCallWithAuthorization");
    }
}
