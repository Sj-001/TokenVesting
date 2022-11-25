//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./NftyDToken.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract TokenVesting is Ownable, Pausable {
    uint256 private constant GENESIS_TIMESTAMP = 1514764800; // Jan 1, 2018 00:00:00 UTC (arbitrary date/time for timestamp validatio

    struct VestingGrant {
        bool isGranted; // Flag to indicate grant was issued
        address issuer; // Account that issued grant
        address beneficiary; // Beneficiary of grant
        uint256 grantDreams; // Number of dreams granted
        uint256 startTimestamp; // Start date/time of vesting
        uint256 cliffTimestamp; // Cliff date/time for vesting
        uint256 endTimestamp; // End date/time of vesting
        bool isRevocable; // Whether issuer can revoke and reclaim dreams
        uint256 releasedDreams; // Number of dreams already released
    }

    mapping(address => VestingGrant) public vestingGrants;
    mapping(address => bool) public authorizedAddresses; // Token grants subject to vesting
    address[] private vestingGrantLookup; // Lookup table of token grants

    NftyDToken public tokenContract;

    /* Vesting Events */
    event Grant(
        // Fired when an account grants tokens to another account on a vesting schedule
        address indexed owner,
        address indexed beneficiary,
        uint256 value
    );

    event Revoke(
        // Fired when an account revokes previously granted unvested tokens to another account
        address indexed owner,
        address indexed beneficiary,
        uint256 value
    );

    /**
     * @dev Constructor
     *
     * @param  _tokenContract Address of the WHENToken contract
     */
    constructor(address payable _tokenContract) {
        tokenContract = NftyDToken(_tokenContract);
    }

    /**
     * @dev Authorizes a smart contract to call this contract
     *
     * @param account Address of the calling smart contract
     */
    function authorizeAddress(address account) public whenNotPaused onlyOwner {
        require(account != address(0), "Account must be a valid address");

        authorizedAddresses[account] = true;
    }

    /**
     * @dev Deauthorizes a previously authorized smart contract from calling this contract
     *
     * @param account Address of the calling smart contract
     */
    function deauthorizeAddress(address account)
        external
        whenNotPaused
        onlyOwner
    {
        require(account != address(0), "Account must be a valid address");

        authorizedAddresses[account] = false;
    }

    /**
     * @dev Grants a beneficiary dreams using a vesting schedule
     *
     * @param beneficiary The account to whom dreams are being granted
     * @param dreams dreams that are granted but not vested
     * @param startTimestamp Date/time when vesting begins
     * @param cliffSeconds Date/time prior to which tokens vest but cannot be released
     * @param vestingSeconds Vesting duration (also known as vesting term)
     * @param revocable Indicates whether the granting account is allowed to revoke the grant
     */

    function grant(
        address beneficiary,
        uint256 dreams,
        uint256 startTimestamp,
        uint256 cliffSeconds,
        uint256 vestingSeconds,
        bool revocable
    ) external whenNotPaused {
        require(authorizedAddresses[msg.sender], "Sender not authorized");
        require(beneficiary != address(0), "Account must be a valid address");
        require(
            !vestingGrants[beneficiary].isGranted,
            "Tokens already granted"
        ); // Can't have multiple grants for same account
        require(
            (dreams > 0 && dreams <= tokenContract.balanceOf(msg.sender)),
            "Tokens must be greater than zero"
        ); // There must be dreams that are being granted

        require(startTimestamp >= GENESIS_TIMESTAMP, "Invalid startTimestamp"); // Just a way to prevent really old dates
        require(vestingSeconds > 0, "Duration must be greater than zero");
        require(cliffSeconds >= 0, "Cliff must be greater than zero");
        require(
            cliffSeconds < vestingSeconds,
            "Cliff must be smaller than vestingSeconds"
        );

        tokenContract.transferFrom(msg.sender, address(this), dreams);
        // The vesting grant is added to the beneficiary and the vestingGrant lookup table is updated
        vestingGrants[beneficiary] = VestingGrant({
            isGranted: true,
            issuer: msg.sender,
            beneficiary: beneficiary,
            grantDreams: dreams,
            startTimestamp: startTimestamp,
            cliffTimestamp: startTimestamp + cliffSeconds,
            endTimestamp: startTimestamp + vestingSeconds,
            isRevocable: revocable,
            releasedDreams: 0
        });

        vestingGrantLookup.push(beneficiary);

        emit Grant(msg.sender, beneficiary, dreams); // Fire event

        // If the cliff time has already passed or there is no cliff, then release
        // any dreams for which the beneficiary is already eligible
        if (vestingGrants[beneficiary].cliffTimestamp <= block.timestamp) {
            releaseFor(beneficiary);
        }
    }

    /**
     * @dev Releases dreams that have been vested for caller
     *
     */
    function release() external {
        releaseFor(msg.sender);
    }

    /**
     * @dev Gets current grant balance for caller
     *
     */
    function getGrantBalance() external view returns (uint256) {
        return getGrantBalanceOf(msg.sender);
    }

    /**
     * @dev Gets current grant balance for an account
     *
     * The return value subtracts dreams that have previously
     * been released.
     *
     * @param account Account whose grant balance is returned
     *
     */
    function getGrantBalanceOf(address account) public view returns (uint256) {
        require(account != address(0), "Account must be a valid address");
        require(vestingGrants[account].isGranted, "Tokens must be granted");

        return (vestingGrants[account].grantDreams -
            (vestingGrants[account].releasedDreams));
    }

    /**
     * @dev Returns a lookup table of all vesting grant beneficiaries
     *
     */
    function getGrantBeneficiaries() external view returns (address[] memory) {
        return vestingGrantLookup;
    }

    /**
     * @dev Returns releasableDreams of an account
     *
     * @param account  Account whose releasable dreams will be calculated
     */

    function getReleasableDreams(address account)
        public
        view
        returns (uint256 releasableDreams)
    {
        if (vestingGrants[account].cliffTimestamp > block.timestamp) {
            releasableDreams = 0;
        } else {
            // Calculate vesting rate per second
            uint256 duration = (vestingGrants[account].endTimestamp -
                (vestingGrants[account].startTimestamp));

            // Calculate how many dreams can be released
            uint256 secondsPassed = (block.timestamp -
                vestingGrants[account].startTimestamp);

            uint256 vestedDreams = ((vestingGrants[account].grantDreams *
                secondsPassed) / duration);
            console.log("Vested Dreams:", vestedDreams);
            releasableDreams =
                vestedDreams -
                (vestingGrants[account].releasedDreams);

            // If the additional released dreams would cause the total released to exceed total granted, then
            // cap the releasable dreams to whatever was granted.
            if (
                (vestingGrants[account].releasedDreams + (releasableDreams)) >
                vestingGrants[account].grantDreams
            ) {
                releasableDreams =
                    vestingGrants[account].grantDreams -
                    (vestingGrants[account].releasedDreams);
            }
        }
    }

    /**
     * @dev Releases dreams that have been vested for an account
     *
     * @param account Account whose dreams will be released
     *
     */
    function releaseFor(address account) public {
        require(account != address(0), "Account must be a valid address");
        require(vestingGrants[account].isGranted, "Tokens must be granted");
        require(
            vestingGrants[account].cliffTimestamp <= block.timestamp,
            "Cannot release tokens before cliff period"
        );

        uint256 releasableDreams = getReleasableDreams(account);

        if (releasableDreams > 0) {
            // Update the released dreams counter
            vestingGrants[account].releasedDreams =
                vestingGrants[account].releasedDreams +
                (releasableDreams);
            tokenContract.transfer(account, releasableDreams);
        }
    }

    /**
     * @dev Revokes previously issued vesting grant
     *
     * For a grant to be revoked, it must be revocable.
     * In addition, only the unreleased tokens can be revoked.
     *
     * @param account Account for which a prior grant will be revoked
     */
    function revoke(address account) public whenNotPaused {
        require(account != address(0), "Account must be a valid address");
        require(vestingGrants[account].isGranted, "Tokens must be granted");
        require(vestingGrants[account].isRevocable, "Tokens must be revocable");
        require(vestingGrants[account].issuer == msg.sender, "Not an issuer"); // Only the original issuer can revoke a grant

        // Set the isGranted flag to false to prevent any further
        // actions on this grant from ever occurring
        vestingGrants[account].isGranted = false;

        // Get the remaining balance of the grant
        uint256 balanceDreams = vestingGrants[account].grantDreams -
            (vestingGrants[account].releasedDreams);
        emit Revoke(vestingGrants[account].issuer, account, balanceDreams);

        // If there is any balance left, return it to the issuer
        if (balanceDreams > 0) {
            tokenContract.transfer(msg.sender, balanceDreams);
        }
    }

    fallback() external {
        revert();
    }
}
