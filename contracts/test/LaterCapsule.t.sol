// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LaterCapsule} from "../src/LaterCapsule.sol";

contract LaterCapsuleTest is Test {
    LaterCapsule later;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address eve = makeAddr("eve");
    bytes ct = hex"deadbeefcafe";

    event Sealed(uint256 indexed id, address indexed sender, address indexed recipient, uint64 unlockAt, uint64 drandRound, bool onSky, bytes ciphertext);
    event Opened(uint256 indexed id, address indexed opener, uint64 openedAt);

    function setUp() public {
        vm.warp(1_800_000_000);
        later = new LaterCapsule();
    }

    function _seal(address from, address to, uint64 lock) internal returns (uint256) {
        vm.prank(from);
        return later.seal(to, uint64(block.timestamp) + lock, 12345, true, ct);
    }

    function test_sealStoresAndEmits() public {
        uint64 unlock = uint64(block.timestamp + 30 days);
        vm.expectEmit(true, true, true, true);
        emit Sealed(0, alice, bob, unlock, 777, true, ct);
        vm.prank(alice);
        uint256 id = later.seal(bob, unlock, 777, true, ct);
        LaterCapsule.Capsule memory c = later.getCapsule(id);
        assertEq(c.sender, alice);
        assertEq(c.recipient, bob);
        assertEq(c.unlockAt, unlock);
        assertEq(c.ciphertextHash, keccak256(ct));
        assertFalse(c.opened);
        assertEq(later.totalCapsules(), 1);
        assertEq(later.capsulesSentBy(alice)[0], 0);
        assertEq(later.capsulesFor(bob)[0], 0);
        assertTrue(later.verifyCiphertext(id, ct));
        assertFalse(later.verifyCiphertext(id, hex"00"));
    }

    function test_selfCapsuleNotDuplicatedInReceived() public {
        _seal(alice, alice, 1 days);
        assertEq(later.capsulesFor(alice).length, 0);
        assertEq(later.capsulesSentBy(alice).length, 1);
    }

    function test_revertsOnBadInput() public {
        vm.startPrank(alice);
        vm.expectRevert(LaterCapsule.UnlockTooSoon.selector);
        later.seal(bob, uint64(block.timestamp + 5 minutes), 1, true, ct);
        vm.expectRevert(LaterCapsule.UnlockTooFar.selector);
        later.seal(bob, uint64(block.timestamp + 101 * 365 days), 1, true, ct);
        vm.expectRevert(LaterCapsule.ZeroDrandRound.selector);
        later.seal(bob, uint64(block.timestamp + 1 days), 0, true, ct);
        vm.expectRevert(LaterCapsule.EmptyCiphertext.selector);
        later.seal(bob, uint64(block.timestamp + 1 days), 1, true, "");
        vm.expectRevert(LaterCapsule.CiphertextTooLarge.selector);
        later.seal(bob, uint64(block.timestamp + 1 days), 1, true, new bytes(8 * 1024 + 1));
        vm.stopPrank();
    }

    function test_cannotOpenEarly() public {
        uint256 id = _seal(alice, bob, 7 days);
        vm.warp(block.timestamp + 7 days - 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(LaterCapsule.StillLocked.selector, uint64(1_800_000_000 + 7 days)));
        later.open(id);
        // not even the sender
        vm.prank(alice);
        vm.expectRevert();
        later.open(id);
    }

    function test_openAfterUnlock() public {
        uint256 id = _seal(alice, bob, 7 days);
        vm.warp(block.timestamp + 7 days);
        assertTrue(later.isUnlocked(id));
        vm.expectEmit(true, true, false, true);
        emit Opened(id, bob, uint64(block.timestamp));
        vm.prank(bob);
        later.open(id);
        assertTrue(later.getCapsule(id).opened);
        vm.prank(alice);
        vm.expectRevert(LaterCapsule.AlreadyOpened.selector);
        later.open(id);
    }

    function test_strangerCannotOpenAddressedCapsule() public {
        uint256 id = _seal(alice, bob, 1 days);
        vm.warp(block.timestamp + 1 days);
        vm.prank(eve);
        vm.expectRevert(LaterCapsule.NotAllowed.selector);
        later.open(id);
        vm.prank(alice);
        later.open(id);
    }

    function test_linkCapsuleOpenableByAnyone() public {
        uint256 id = _seal(alice, address(0), 1 days);
        vm.warp(block.timestamp + 1 days);
        vm.prank(eve);
        later.open(id);
    }

    function test_unknownCapsule() public {
        vm.expectRevert(LaterCapsule.UnknownCapsule.selector);
        later.getCapsule(0);
        vm.expectRevert(LaterCapsule.UnknownCapsule.selector);
        later.open(3);
    }

    function testFuzz_lockWindow(uint64 lock) public {
        lock = uint64(bound(lock, 10 minutes, 100 * 365 days));
        uint256 id = _seal(alice, bob, lock);
        assertFalse(later.isUnlocked(id));
        vm.warp(block.timestamp + lock);
        assertTrue(later.isUnlocked(id));
    }

    function test_gasSeal() public {
        bytes memory big = new bytes(1024);
        vm.prank(alice);
        uint256 g = gasleft();
        later.seal(bob, uint64(block.timestamp + 30 days), 1, true, big);
        emit log_named_uint("gas seal 1KB", g - gasleft());
    }
}
