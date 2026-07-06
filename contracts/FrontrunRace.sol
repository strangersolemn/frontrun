// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// FRONTRUN — THE RACE (burn-only, v2)
//
// Satellite contract. Touches the live FRONTRUN collection ZERO — it only reads
// ownerOf() and moves tokens their owner has approved. No changes to the deployed
// ERC721 (0x08d08D7f8CEF8EBb56D788a6c0C85cee313A1e17), no validator swap, no locks.
//
// THE GAME (wiki: frontrun-the-race-burn-only-2026-07-04 + king-resolved page):
//   • Every living piece accrues GROUND passively at the same rate, retroactive
//     from the reveal (startTime). Computed lazily — no keeper, no writes.
//   • The ONLY move is BURN: burn one of your pieces into another of your pieces.
//     The sacrifice goes to 0xdead permanently (real deflation, supply < 666) and
//     the survivor absorbs ALL the ground the sacrifice carried.
//   • Standings can only change when someone burns, so the crown updates only
//     inside burnInto(). Crown is UNCLAIMED until the first burn; strictly
//     greater ground steals it.
//   • King problem self-solves (resolved 2026-07-04): a banked king sits static
//     while every challenger's spare pieces keep accruing — wait, stack, burn,
//     overtake. No decay, no seasons, no caps. The design is final.
//   • AUTONOMY: burn-open is ONE-WAY (can never be closed) and ownership is
//     renounceable. After open + renounce the game runs itself forever — no
//     hand on the wheel, zero artist dependency.
//   • Tiers (crown / Front top-10 / top-25 / top-100) are read off events +
//     groundOf() by the site and renderer; the contract stays minimal.
//
// GROUND UNITS: raw seconds-since-start + absorbed. The public display name of
// the unit (poll pending) and all formatting are site concerns.

interface IERC721Race {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract FrontrunRace {
    // ---- immutables ----
    IERC721Race public immutable frontrun;      // the live FRONTRUN ERC721
    uint256 public immutable startTime;         // reveal timestamp — accrual t0 (retroactive)
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address public owner;                       // exists only to open the burn, then renounce
    bool    public burnOpen;                    // one-way: false -> true, never back

    // ---- race state ----
    mapping(uint256 => uint256) public absorbed;    // ground gained via burns, per living token
    mapping(uint256 => bool)    public dead;        // burned via the race
    mapping(uint256 => uint256) public deadGround;  // ground the piece carried into the fire (lore)
    uint256 public burnCount;                       // total pieces destroyed

    bool    public crownClaimed;                // false until the first burn — empty crown
    uint256 public king;                        // crown holder tokenId (valid iff crownClaimed)
    uint256 public kingGround;                  // king's ground at its last burn (floor to beat)

    // ---- events (site + renderer index off these) ----
    event Burned(
        address indexed player,
        uint256 indexed sacrifice,
        uint256 indexed survivor,
        uint256 groundAbsorbed,
        uint256 survivorGround
    );
    event CrownTaken(uint256 indexed tokenId, uint256 ground, uint256 prevKing, bool wasClaimed);
    event BurnOpened();

    constructor(address frontrunContract, uint256 revealTimestamp) {
        frontrun = IERC721Race(frontrunContract);
        startTime = revealTimestamp;
        owner = msg.sender;
    }

    // ================= views =================

    /// Ground of a living piece: shared base accrual since reveal + everything absorbed.
    /// Dead pieces return 0 (their final tally is preserved in deadGround).
    function groundOf(uint256 tokenId) public view returns (uint256) {
        if (dead[tokenId]) return 0;
        uint256 base = block.timestamp > startTime ? block.timestamp - startTime : 0;
        return base + absorbed[tokenId];
    }

    /// The crown as the site reads it. kingToken is meaningless until claimed.
    function crown() external view returns (bool claimed, uint256 kingToken, uint256 kingCurrentGround) {
        return (crownClaimed, king, crownClaimed ? groundOf(king) : 0);
    }

    // ================= the move =================

    /// Burn `sacrifice` into `survivor`. Caller must own BOTH pieces and have
    /// approved this contract (setApprovalForAll) on the FRONTRUN collection.
    /// The sacrifice is transferred to 0xdead — permanent, unrecoverable.
    function burnInto(uint256 sacrifice, uint256 survivor) external {
        require(burnOpen, "burn not open");
        require(sacrifice != survivor, "cannot burn into itself");
        require(!dead[sacrifice] && !dead[survivor], "piece is dead");
        require(frontrun.ownerOf(sacrifice) == msg.sender, "not your sacrifice");
        require(frontrun.ownerOf(survivor) == msg.sender, "not your survivor");

        // tally the sacrifice at the moment of death
        uint256 carried = groundOf(sacrifice);

        // state before external call (checks-effects-interactions)
        dead[sacrifice] = true;
        deadGround[sacrifice] = carried;
        absorbed[survivor] += carried;
        burnCount += 1;

        // the fire — real transfer to the dead address
        frontrun.transferFrom(msg.sender, DEAD, sacrifice);

        uint256 survivorGround = groundOf(survivor);
        emit Burned(msg.sender, sacrifice, survivor, carried, survivorGround);

        // crown: empty until the first burn; strictly greater steals it; if the
        // old king was itself just sacrificed, the survivor inherits by absorption.
        if (!crownClaimed || survivorGround > kingGround || king == sacrifice) {
            uint256 prev = crownClaimed ? king : type(uint256).max;
            bool was = crownClaimed;
            crownClaimed = true;
            king = survivor;
            kingGround = survivorGround;
            emit CrownTaken(survivor, survivorGround, prev, was);
        }
    }

    // ================= launch (then let go of the wheel) =================

    /// One-way. Once the burn opens it can never be closed.
    function openBurn() external {
        require(msg.sender == owner, "not owner");
        require(!burnOpen, "already open");
        burnOpen = true;
        emit BurnOpened();
    }

    /// After this the contract has no owner and no admin surface at all.
    function renounce() external {
        require(msg.sender == owner, "not owner");
        owner = address(0);
    }
}
