// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Ownable2StepUpgradeable} from "@openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {
    LibImplementationWhitelistDeployerAddressStorage
} from "implementation-whitelist/libraries/storage/LibImplementationWhitelistDeployerAddressStorage.sol";
import {
    LibImplementationWhitelistStorage
} from "implementation-whitelist/libraries/storage/LibImplementationWhitelistStorage.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @title Implementation Whitelist
 * @notice Contract for managing whitelisted implementation addresses
 * @author Den Technologies Inc
 */
contract ImplementationWhitelistImplementation is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    IImplementationWhitelist
{
    /**
     * @notice Modifier that enforces only the deployer can call the function
     */
    modifier onlyDeployer() {
        _enforceOnlyDeployer();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the implementation whitelist
     * @param initialOwner The initial owner address
     */
    function initialize(address initialOwner) external override initializer onlyDeployer {
        __Ownable_init(initialOwner);
        __Ownable2Step_init();

        emit ImplementationWhitelistInitialized(initialOwner);
    }

    /**
     * @notice Whitelists and/or unwhitelists implementation addresses
     * @param contractType The type of contract (Account or Organization)
     * @param toWhitelist The implementation addresses to whitelist
     * @param toUnwhitelist The implementation addresses to remove from whitelist
     */
    function whitelistImplementations(
        ContractType contractType,
        address[] calldata toWhitelist,
        address[] calldata toUnwhitelist
    ) external override onlyOwner {
        LibImplementationWhitelistStorage.Layout storage storageLayout = LibImplementationWhitelistStorage.layout();

        for (uint256 i = 0; i < toWhitelist.length; ++i) {
            storageLayout.whitelisted[contractType][toWhitelist[i]] = true;
            emit ImplementationWhitelisted(contractType, toWhitelist[i]);
        }

        for (uint256 i = 0; i < toUnwhitelist.length; ++i) {
            storageLayout.whitelisted[contractType][toUnwhitelist[i]] = false;
            emit ImplementationUnwhitelisted(contractType, toUnwhitelist[i]);
        }
    }

    /**
     * @notice Returns the address that deployed this implementation whitelist proxy
     * @return The deployer address
     */
    function getDeployerAddress() external view override returns (address) {
        return LibImplementationWhitelistDeployerAddressStorage.layout().deployerAddress;
    }

    /**
     * @notice Checks if the implementation whitelist has been initialized
     * @dev Checks if owner is set (since every initialized whitelist must have an owner)
     * @return True if initialized, false otherwise
     */
    function isInitialized() external view override returns (bool) {
        return owner() != address(0);
    }

    /**
     * @notice Checks if an implementation address is whitelisted
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address to check
     * @return True if the implementation is whitelisted, false otherwise
     */
    function isImplementationWhitelisted(ContractType contractType, address implementation)
        external
        view
        override
        returns (bool)
    {
        return LibImplementationWhitelistStorage.layout().whitelisted[contractType][implementation];
    }

    /**
     * @notice Validates that an implementation address is whitelisted, reverts if not
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address to check
     */
    function validateIsImplementationWhitelistedOrRevert(ContractType contractType, address implementation)
        external
        view
        override
    {
        if (!LibImplementationWhitelistStorage.layout().whitelisted[contractType][implementation]) {
            revert ImplementationNotWhitelisted(implementation);
        }
    }

    /**
     * @notice Authorize an upgrade
     * @dev This function is empty because the onlyOwner modifier ensures that only the owner can upgrade
     * @param newImplementation The new implementation address
     */
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    /**
     * @dev Enforces that the caller is the deployer address.
     *      This function will revert if msg.sender is not the deployer.
     */
    function _enforceOnlyDeployer() private view {
        if (msg.sender != LibImplementationWhitelistDeployerAddressStorage.layout().deployerAddress) {
            revert UnauthorizedDeployer();
        }
    }
}
