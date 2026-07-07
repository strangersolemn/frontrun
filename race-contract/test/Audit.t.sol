// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/FrontrunRace.sol";
import "../src/MockERC721.sol";

interface Vm {
    function warp(uint256) external;
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function expectRevert(bytes calldata) external;
}

contract AuditTest {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address constant A = address(0xAAAA);
    address constant B = address(0xBBBB);

    function _fresh() internal returns (MockERC721 nft, FrontrunRace race) {
        nft = new MockERC721();
        nft.mint(A, 1); nft.mint(A, 2); nft.mint(A, 3);
        nft.mint(B, 10); nft.mint(B, 11);
        race = new FrontrunRace(address(nft), 0); // startTime = 0
        race.openBurn();
        vm.prank(A); nft.setApprovalForAll(address(race), true);
        vm.prank(B); nft.setApprovalForAll(address(race), true);
    }

    // ---- REGRESSION for the critical crown bug: the crown must track the true leader ----
    // Exact scenario that used to hand the crown to the non-leader. A stacks two early burns
    // (ground 370, the leader). Time passes. B makes one late burn (ground 340). A is still
    // ahead — the crown must STAY with A.
    function testCrown_StaysWithTrueLeader() public {
        (, FrontrunRace race) = _fresh();

        vm.warp(100);
        vm.startPrank(A);
        race.burnInto(1, 2);
        race.burnInto(3, 2);       // A(2): absorbed 200, groundOf 300, king
        vm.stopPrank();
        require(race.king() == 2, "A should be king");

        vm.warp(170);
        vm.prank(B);
        race.burnInto(10, 11);     // B(11): groundOf 340

        require(race.groundOf(2) > race.groundOf(11), "A is still the leader (370 > 340)");
        require(race.king() == 2, "crown stays with the true leader");
    }

    // ---- The crown DOES move when a challenger genuinely out-absorbs the king ----
    function testCrown_MovesOnRealOvertake() public {
        (, FrontrunRace race) = _fresh();
        vm.warp(100);
        vm.prank(A); race.burnInto(1, 2);      // A(2): groundOf 200, king
        require(race.king() == 2, "A king");

        vm.warp(120);
        vm.prank(B); race.burnInto(10, 11);    // B(11): absorbs 120 -> groundOf 240 > groundOf(2)=220
        require(race.groundOf(11) > race.groundOf(2), "B truly overtakes");
        require(race.king() == 11, "crown correctly moves to B");
    }

    // ---- Sacrificing the reigning king hands the crown to the absorbing survivor ----
    function testCrown_KingSacrificedInherits() public {
        (MockERC721 nft, FrontrunRace race) = _fresh();
        nft.mint(A, 4);
        vm.prank(A); nft.setApprovalForAll(address(race), true);
        vm.warp(100);
        vm.startPrank(A);
        race.burnInto(1, 2);        // 2 is king
        require(race.king() == 2, "2 king");
        race.burnInto(2, 4);        // sacrifice the king itself into 4
        vm.stopPrank();
        require(race.dead(2), "old king burned");
        require(race.king() == 4, "survivor inherits the crown");
    }

    // ---- Safety: only your own pieces ----
    function testSafety_CannotBurnUnowned() public {
        (, FrontrunRace race) = _fresh();
        vm.warp(100);
        vm.prank(B);
        vm.expectRevert(bytes("not your sacrifice"));
        race.burnInto(1, 10);
    }

    // ---- Safety: no double burn ----
    function testSafety_CannotBurnDeadTwice() public {
        (, FrontrunRace race) = _fresh();
        vm.warp(100);
        vm.startPrank(A);
        race.burnInto(1, 2);
        vm.expectRevert(bytes("piece is dead"));
        race.burnInto(1, 2);
        vm.stopPrank();
    }

    // ---- Safety: ground is conserved exactly + deflation ----
    function testSafety_GroundConservedAndDeflation() public {
        (MockERC721 nft, FrontrunRace race) = _fresh();
        vm.warp(100);
        uint256 beforeG = race.groundOf(2);
        uint256 sac = race.groundOf(1);
        vm.prank(A); race.burnInto(1, 2);
        require(race.groundOf(2) == beforeG + sac, "survivor gains exactly the sacrifice");
        require(race.groundOf(1) == 0, "dead reads zero");
        require(race.deadGround(1) == sac, "final tally preserved");
        require(nft.ownerOf(1) == address(0x000000000000000000000000000000000000dEaD), "sacrifice sent to 0xdead");
        require(race.burnCount() == 1, "supply deflated");
    }

    // ---- Safety: burn closed before launch ----
    function testSafety_BurnClosedReverts() public {
        MockERC721 nft = new MockERC721();
        nft.mint(A, 1); nft.mint(A, 2);
        FrontrunRace race = new FrontrunRace(address(nft), 0); // not opened
        vm.prank(A); nft.setApprovalForAll(address(race), true);
        vm.warp(100);
        vm.prank(A);
        vm.expectRevert(bytes("burn not open"));
        race.burnInto(1, 2);
    }

    // ---- Access control ----
    function testSafety_OnlyOwnerOpensAndOneWay() public {
        MockERC721 nft = new MockERC721();
        FrontrunRace race = new FrontrunRace(address(nft), 0);
        vm.prank(B);
        vm.expectRevert(bytes("not owner"));
        race.openBurn();
        race.openBurn();
        vm.expectRevert(bytes("already open"));
        race.openBurn();
    }
}
