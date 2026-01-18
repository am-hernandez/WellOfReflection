// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {Test} from "@forge-std/Test.sol";
import {WellOfReflection} from "../src/WellOfReflection.sol";
import {console} from "@forge-std/console.sol";
import {Vm} from "@forge-std/Vm.sol";
import {MockLinkToken} from "@chainlink/mocks/MockLinkToken.sol";
import {MockV3Aggregator} from "@chainlink/tests/MockV3Aggregator.sol";
import {ExposedVRFCoordinatorV2_5} from "@chainlink/vrf/dev/testhelpers/ExposedVRFCoordinatorV2_5.sol";
import {VRFV2PlusWrapper} from "@chainlink/vrf/dev/VRFV2PlusWrapper.sol";

contract WellOfReflectionTest is Test {
    WellOfReflection public wellOfReflection;
    MockUSDC public usdc;
    MockLinkToken public linkToken;
    MockV3Aggregator public linkNativeFeed;
    ExposedVRFCoordinatorV2_5 public vrfCoordinator;
    VRFV2PlusWrapper public vrfV2PlusWrapper;
    uint256 public wrapperSubscriptionId;
    uint256 public ethAmount = 1 ether;
    address visitor1;
    address visitor2;
    address visitor3;

    // VRF Configuration constants
    bytes32 private constant VRF_KEY_HASH = hex"9f2353bde94264dbc3d554a94cceba2d7d2b4fdce4304d3e09a1fea9fbeb1528";
    uint32 private constant WRAPPER_GAS_OVERHEAD = 100_000;
    uint32 private constant COORDINATOR_GAS_OVERHEAD_NATIVE = 200_000;
    uint32 private constant COORDINATOR_GAS_OVERHEAD_LINK = 220_000;

    function setUp() public {
        // Deploy mock LINK token and LINK/Native feed
        // linkToken = new MockLinkToken();
        // linkNativeFeed = new MockV3Aggregator(18, 500000000000000000); // 0.5 ETH per LINK

        // Deploy VRF Coordinator
        vrfCoordinator = new ExposedVRFCoordinatorV2_5(address(0));

        // Create subscription for wrapper
        wrapperSubscriptionId = vrfCoordinator.createSubscription();

        // Deploy VRF V2 Plus Wrapper
        vrfV2PlusWrapper = new VRFV2PlusWrapper(address(0), address(0), address(vrfCoordinator), wrapperSubscriptionId);

        // Add wrapper as consumer to subscription
        vrfCoordinator.addConsumer(wrapperSubscriptionId, address(vrfV2PlusWrapper));

        // Configure coordinator
        // vrfCoordinator.setLINKAndLINKNativeFeed(address(0), address(0));
        vrfCoordinator.setConfig(
            0, // minRequestConfirmations
            2_500_000, // maxGasLimit
            1, // stalenessSeconds
            50_000, // gasAfterPaymentCalculation
            50000000000000000, // fallbackWeiPerUnitLink
            0, // fulfillmentFlatFeeNativePPM
            0, // fulfillmentFlatFeeLinkDiscountPPM
            0, // nativePremiumPercentage
            0 // linkPremiumPercentage
        );

        // Configure wrapper
        vrfV2PlusWrapper.setConfig(
            WRAPPER_GAS_OVERHEAD,
            COORDINATOR_GAS_OVERHEAD_NATIVE,
            COORDINATOR_GAS_OVERHEAD_LINK,
            0, // coordinatorGasOverheadPerWord
            0, // coordinatorNativePremiumPercentage
            0, // coordinatorLinkPremiumPercentage
            VRF_KEY_HASH,
            10, // maxNumWords
            1, // stalenessSeconds
            50000000000000000, // fallbackWeiPerUnitLink
            0, // fulfillmentFlatFeeNativePPM
            0 // fulfillmentFlatFeeLinkDiscountPPM
        );

        // Fund the wrapper subscription with native and LINK
        vm.deal(address(this), 100 ether);
        vrfCoordinator.fundSubscriptionWithNative{value: 10 ether}(wrapperSubscriptionId);

        // Deploy WellOfReflection with the wrapper
        usdc = new MockUSDC();
        wellOfReflection = new WellOfReflection(address(vrfV2PlusWrapper));

        visitor1 = makeAddr("visitor1");
        visitor2 = makeAddr("visitor2");
        visitor3 = makeAddr("visitor3");

        // give ETH to visitors
        vm.deal(visitor1, ethAmount);
        vm.deal(visitor2, ethAmount);
        vm.deal(visitor3, ethAmount);
    }

    function test_makeOffering() public {
        // Set gas price for VRF price calculation (3 gwei)
        vm.txGasPrice(0.00033 gwei);

        uint256 wellId = wellOfReflection.currentWellId();
        uint256 offeringAmount = wellOfReflection.OFFERING_AMOUNT();
        uint256 wellDepth = wellOfReflection.wellDepth(wellId);

        // get ETH balance for visitor1
        uint256 balanceBefore = visitor1.balance;
        bytes32 key = keccak256(abi.encodePacked(wellId, visitor1));
        bool hasOffered = wellOfReflection.hasOffered(key);

        console.log("balanceBefore", balanceBefore);

        // Before the offering
        assertEq(balanceBefore, ethAmount);
        assertEq(hasOffered, false);
        assertEq(wellId, 0);
        assertEq(wellDepth, 0);

        // make offering
        vm.recordLogs();
        vm.startPrank(visitor1);
        wellOfReflection.makeOffering{value: offeringAmount}();
        vm.stopPrank();

        // Expecting the OfferingMade event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("OfferingMade(uint256,address,uint256)");
        bool eventFound;
        uint256 requestIdFromEvent;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(wellOfReflection) && entries[i].topics[0] == eventSignature) {
                eventFound = true;

                (uint256 wellIdFromEvent, address visitorFromEvent, uint256 requestId) =
                    abi.decode(entries[i].data, (uint256, address, uint256));

                assertEq(wellIdFromEvent, wellId);
                assertEq(visitorFromEvent, visitor1);
                // requestId is non-zero (VRF request was made)
                assertGt(requestId, 0);
                requestIdFromEvent = requestId;
                break;
            }
        }
        assertTrue(eventFound, "OfferingMade event not found");

        // After the offering
        assertEq(wellOfReflection.hasOffered(key), true);
        assertEq(wellOfReflection.wellDepth(0), offeringAmount);

        // Get the VRF cost that was paid
        WellOfReflection.RequestStatus memory requestStatus = wellOfReflection.requests(requestIdFromEvent);
        uint256 vrfCost = requestStatus.paid;

        // Contract balance should be: offeringAmount - VRF request price
        // Contract starts with 0, receives offeringAmount, then pays VRF cost
        uint256 contractBalanceAfter = address(wellOfReflection).balance;
        uint256 expectedBalance = offeringAmount - vrfCost;

        console.log("contractBalanceAfter", contractBalanceAfter);
        console.log("offeringAmount", offeringAmount);
        console.log("vrfCost", vrfCost);
        console.log("expectedBalance", expectedBalance);

        // Balance should equal offering amount minus VRF cost
        assertEq(contractBalanceAfter, expectedBalance, "Contract balance should equal offering amount minus VRF cost");
        assertEq(visitor1.balance, ethAmount - offeringAmount);
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
