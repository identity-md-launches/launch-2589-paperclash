// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Paperclash} from "src/Paperclash.sol";

/// @notice Algebraic properties and allowance boundaries supplementing the original token tests.
/// forge-config: default.fuzz.runs = 1000
contract PaperclashPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    Paperclash private token;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new Paperclash();
        alice = makeAddr("properties alice");
        bob = makeAddr("properties bob");
        spender = makeAddr("properties spender");
        otherSpender = makeAddr("properties other spender");
    }

    function test_LargestFiniteAllowanceDecrementsAfterReplacingInfiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        _assertBalances(2, 0);
    }

    function test_OneBaseUnitCanBeMovedApprovedAndReturned() public {
        assertTrue(token.transfer(alice, 1));
        _assertBalances(1, 0);
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        _assertBalances(0, 1);
        assertEq(token.allowance(alice, spender), 0);
        vm.prank(bob);
        assertTrue(token.transfer(address(this), 1));
        _assertBalances(0, 0);
    }

    function test_SelfTransfersStillRejectAnOverdraw() public {
        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1);
        vm.expectRevert(expected);
        token.transfer(address(this), SUPPLY + 1);

        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1);
        _assertBalances(0, 0);
    }

    function test_HolderCanUseSelfApprovalButCannotReuseIt() public {
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        _assertBalances(1, 0);
    }

    function test_InfiniteApprovalCannotOverdrawAndWorksAgainAfterRefill() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.transfer(alice, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(SUPPLY, 0);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_ZeroDelegatedTransferEmitsTransferAndPreservesExistingAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), type(uint256).max - 1);
        _assertBalances(0, 0);
    }

    function testFuzz_SplitTransfersEqualOneTransfer(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        Paperclash single = new Paperclash();

        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, total - first));
        assertTrue(single.transfer(alice, total));

        _assertBalances(total, 0);
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.totalSupply(), single.totalSupply());
    }

    function testFuzz_SplitDelegatedTransfersEqualOneSpend(uint256 total, uint256 first, uint256 approved) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        approved = bound(approved, total, type(uint256).max);
        Paperclash single = new Paperclash();
        assertTrue(token.approve(spender, approved));
        assertTrue(single.approve(spender, approved));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, total - first));
        assertTrue(single.transferFrom(address(this), alice, total));
        vm.stopPrank();

        _assertBalances(total, 0);
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        uint256 remaining = token.allowance(address(this), spender);
        assertEq(remaining, single.allowance(address(this), spender));
        if (approved == type(uint256).max) assertEq(remaining, approved);
        else assertEq(remaining + total, approved);
    }

    function testFuzz_RepeatedRoundTripsPreserveBothHolders(uint256 initial, uint256 amount, uint8 cycles) public {
        initial = bound(initial, 1, SUPPLY);
        amount = bound(amount, 1, initial);
        cycles = uint8(bound(cycles, 1, 16));
        assertTrue(token.transfer(alice, initial));
        assertTrue(token.transfer(bob, SUPPLY - initial));
        for (uint256 i; i < cycles; ++i) {
            vm.prank(alice);
            assertTrue(token.transfer(bob, amount));
            _assertBalances(initial - amount, SUPPLY - initial + amount);
            vm.prank(bob);
            assertTrue(token.transfer(alice, amount));
            _assertBalances(initial, SUPPLY - initial);
        }
    }

    function testFuzz_FailedDelegatedOverdrawRestoresEveryAllowance(
        uint256 held,
        uint256 amount,
        uint256 approved,
        bool unlimited
    ) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max - 1);
        approved = unlimited ? type(uint256).max : bound(approved, amount, type(uint256).max - 1);
        assertTrue(token.transfer(alice, held));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, approved));
        assertTrue(token.approve(otherSpender, 17));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);

        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.allowance(alice, otherSpender), 17);
        assertEq(token.allowance(bob, spender), 0);
        _assertBalances(held, 0);
    }

    function testFuzz_FailedZeroRecipientTransferRestoresAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);

        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(0)), 0);
        _assertBalances(0, 0);
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndIsolated(uint256 previous, uint256 replacement) public {
        assertTrue(token.approve(spender, previous));
        assertTrue(token.approve(otherSpender, previous));
        vm.prank(alice);
        assertTrue(token.approve(spender, previous));

        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Approval(address(this), spender, replacement);
            assertTrue(token.approve(spender, replacement));
            assertEq(token.allowance(address(this), spender), replacement);
            assertEq(token.allowance(address(this), otherSpender), previous);
            assertEq(token.allowance(alice, spender), previous);
            assertEq(token.allowance(spender, address(this)), 0);
            _assertBalances(0, 0);
        }
    }

    function testFuzz_ReturnedTokensDoNotRestoreSpentAllowance(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        _assertBalances(amount, 0);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        _assertBalances(0, 0);
    }

    function _assertBalances(uint256 aliceBalance, uint256 bobBalance) private view {
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
