// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {Test} from "@forge-std/Test.sol";
import {WellOfReflection} from "../src/WellOfReflection.sol";
import {console} from "@forge-std/console.sol";
import {Vm} from "@forge-std/Vm.sol";

contract WellOfReflectionTest is Test {
    WellOfReflection public wellOfReflection;
    MockUSDC public USDC;
    uint256 public mintAmount = 1e8;
    address visitor1;
    address visitor2;
    address visitor3;

    function setUp() public {
        USDC = new MockUSDC();
        wellOfReflection = new WellOfReflection(address(USDC));

        visitor1 = makeAddr("visitor1");
        visitor2 = makeAddr("visitor2");
        visitor3 = makeAddr("visitor3");

        // mint USDC to visitors
        deal(address(USDC), visitor1, mintAmount);
        deal(address(USDC), visitor2, mintAmount);
        deal(address(USDC), visitor3, mintAmount);
    }

    function test_makeOffering() public {
        uint256 wellId = wellOfReflection.currentWellId();
        uint256 offeringAmount = wellOfReflection.OFFERING_AMOUNT();
        uint256 wellDepth = wellOfReflection.wellDepth(wellId);

        // get balance of USDC for visitor1
        uint256 balanceBefore = USDC.balanceOf(visitor1);
        bytes32 key = keccak256(abi.encodePacked(wellId, visitor1));
        bool hasOffered = wellOfReflection.hasOffered(key);

        // Before the offering
        assertEq(balanceBefore, mintAmount);
        assertEq(hasOffered, false);
        assertEq(wellId, 0);
        assertEq(wellDepth, 0);

        // make offering
        vm.recordLogs();
        vm.startPrank(visitor1);
        USDC.approve(address(wellOfReflection), offeringAmount);
        wellOfReflection.makeOffering();
        vm.stopPrank();

        // Expecting the OfferingMade event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("OfferingMade(uint256,address)");
        bool eventFound;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(wellOfReflection) && entries[i].topics[0] == eventSignature) {
                eventFound = true;

                (uint256 wellIdFromEvent, address visitorFromEvent) = abi.decode(entries[i].data, (uint256, address));

                assertEq(wellIdFromEvent, wellId);
                assertEq(visitorFromEvent, visitor1);
                break;
            }
        }
        assertTrue(eventFound, "OfferingMade event not found");

        // After the offering
        assertEq(wellOfReflection.hasOffered(key), true);
        assertEq(wellOfReflection.wellDepth(0), offeringAmount);
        assertEq(USDC.balanceOf(address(wellOfReflection)), offeringAmount);
        assertEq(USDC.balanceOf(visitor1), mintAmount - offeringAmount);
        assertEq(wellOfReflection.currentWellId(), 0);
    }
}

contract MockUSDC is IERC20 {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    function totalSupply() external pure returns (uint256) {
        return 1000000000000000000000000000;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return allowances[owner][spender];
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        balances[from] -= amount;
        balances[to] += amount;
        allowances[from][msg.sender] -= amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function name() external pure returns (string memory) {
        return "Mock USDC";
    }

    function symbol() external pure returns (string memory) {
        return "mUSDC";
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }
}
