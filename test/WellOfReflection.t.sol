// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {Test} from "@forge-std/Test.sol";
import {WellOfReflection} from "../src/WellOfReflection.sol";
import {console} from "@forge-std/console.sol";
import {Vm} from "@forge-std/Vm.sol";
import {MockLinkToken} from "@chainlink/mocks/MockLinkToken.sol";
import {MockV3Aggregator} from "@chainlink/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {VRFV2PlusWrapper} from "@chainlink/vrf/dev/VRFV2PlusWrapper.sol";

contract WellOfReflectionTest is Test {
    WellOfReflection public wellOfReflection;
    MockUSDC public usdc;
    MockLinkToken public linkToken;
    MockV3Aggregator public linkNativeFeed;
    VRFCoordinatorV2_5Mock public vrfCoordinator;
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
        // Deploy mock LINK token and feed (needed by wrapper)
        linkToken = new MockLinkToken();
        linkNativeFeed = new MockV3Aggregator(18, 500000000000000000); // 0.5 ETH per LINK

        // Deploy VRF Coordinator Mock
        // Parameters: baseFee, gasPrice, weiPerUnitLink
        vrfCoordinator = new VRFCoordinatorV2_5Mock(0, 0, 50000000000000000);

        // Create subscription for wrapper
        wrapperSubscriptionId = vrfCoordinator.createSubscription();

        // Deploy VRF V2 Plus Wrapper
        vrfV2PlusWrapper = new VRFV2PlusWrapper(
            address(linkToken), address(linkNativeFeed), address(vrfCoordinator), wrapperSubscriptionId
        );

        // Add wrapper as consumer to subscription
        vrfCoordinator.addConsumer(wrapperSubscriptionId, address(vrfV2PlusWrapper));

        // Configure wrapper
        vrfV2PlusWrapper.setConfig(
            WRAPPER_GAS_OVERHEAD,
            COORDINATOR_GAS_OVERHEAD_NATIVE,
            COORDINATOR_GAS_OVERHEAD_LINK,
            0, // coordinatorGasOverheadPerWord
            0, // coordinatorNativePremiumPercentage
            0, // coordinatorLinkPremiumPercentage
            VRF_KEY_HASH,
            1, // maxNumWords
            1, // stalenessSeconds
            50000000000000000, // fallbackWeiPerUnitLink
            0, // fulfillmentFlatFeeNativePPM
            0 // fulfillmentFlatFeeLinkDiscountPPM
        );

        // Fund the wrapper subscription with ETH
        vm.deal(address(this), 100 ether);
        vrfCoordinator.fundSubscriptionWithNative{value: 10 ether}(wrapperSubscriptionId);

        // Deploy WellOfReflection with the wrapper
        // usdc = new MockUSDC();
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
        // Set gas price for VRF price calculation
        vm.txGasPrice(0.00033 gwei);

        uint256 wellId = wellOfReflection.currentWellId();
        uint256 offeringAmount = wellOfReflection.OFFERING_AMOUNT();
        bytes32 key = keccak256(abi.encodePacked(wellId, visitor1));

        // Calculate VRF fee that visitor needs to pay
        uint256 vrfFee = vrfV2PlusWrapper.calculateRequestPriceNative(100_000, 1);
        uint256 totalAmount = offeringAmount + vrfFee;

        // Before the offering
        assertEq(visitor1.balance, ethAmount);
        assertEq(wellOfReflection.hasOffered(key), false);
        assertEq(wellId, 0);
        assertEq(wellOfReflection.wellDepth(wellId), 0);

        // make offering (visitor pays offeringAmount + vrfFee)
        vm.recordLogs();
        vm.startPrank(visitor1);
        wellOfReflection.makeOffering{value: totalAmount}();
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
        assertEq(wellOfReflection.wellDepth(wellId), offeringAmount);

        // Get the VRF cost that was paid
        (uint256 vrfFeePaidByVisitor, bool fulfilled, uint256 randomWord) =
            wellOfReflection.requests(requestIdFromEvent);

        uint256 vrfCost = vrfFeePaidByVisitor;
        assertEq(vrfCost, vrfFee);
        assertEq(fulfilled, false);
        assertEq(randomWord, 0);

        uint256 contractBalanceAfter = address(wellOfReflection).balance;
        uint256 expectedBalance = offeringAmount; // VRF fee is paid from the fee portion, offering remains

        // Balance should equal offering amount (VRF fee was deducted from the fee portion)
        assertEq(contractBalanceAfter, expectedBalance, "Contract balance should equal offering amount");
        assertEq(visitor1.balance, ethAmount - totalAmount);
        assertEq(wellOfReflection.currentWellId(), 0);
    }

    function test_fulfillRandomWords() public {
        // Set gas price for VRF price calculation (3 gwei)
        vm.txGasPrice(0.00033 gwei);

        address visitor = visitor1;
        uint256 wellId = wellOfReflection.currentWellId();
        uint256 offeringAmount = wellOfReflection.OFFERING_AMOUNT();
        uint256 beforeBalance = visitor.balance;

        // Calculate VRF fee that visitor needs to pay
        uint256 vrfFee = vrfV2PlusWrapper.calculateRequestPriceNative(100_000, 1);
        uint256 totalAmount = offeringAmount + vrfFee;

        // --------------------- //
        // --- Make Offering --- //
        // --------------------- //

        vm.recordLogs();
        vm.startPrank(visitor);
        wellOfReflection.makeOffering{value: totalAmount}();
        vm.stopPrank();

        // get request ID from event OfferingMade(wellId, visitorAddress, requestId);
        Vm.Log[] memory eventLogs = vm.getRecordedLogs();

        bytes32 offeringMadeEventSignature = keccak256("OfferingMade(uint256,address,uint256)");
        bytes32 randomWordsRequestedEventSignature =
            keccak256("RandomWordsRequested(bytes32,uint256,uint256,uint256,uint16,uint32,uint32,bytes,address)");
        uint256 requestId;
        uint256 coordinatorRequestId;
        bool coordinatorRequestIdFound;

        for (uint256 i = 0; i < eventLogs.length; i++) {
            // Get the wrapper's request ID from OfferingMade event
            if (
                eventLogs[i].emitter == address(wellOfReflection)
                    && eventLogs[i].topics[0] == offeringMadeEventSignature
            ) {
                (,, uint256 requestIdFromEvent) = abi.decode(eventLogs[i].data, (uint256, address, uint256));
                requestId = requestIdFromEvent;
            }

            // Get the coordinator's request ID from RandomWordsRequested event
            if (
                eventLogs[i].emitter == address(vrfCoordinator)
                    && eventLogs[i].topics[0] == randomWordsRequestedEventSignature
            ) {
                // Event: RandomWordsRequested(bytes32 indexed keyHash, uint256 requestId, uint256 preSeed, ...)
                // requestId is NOT indexed, so it's in the data
                // requestId is the first parameter in data, so we can read it directly (first 32 bytes)
                assertGe(eventLogs[i].data.length, 32);
                coordinatorRequestId = uint256(bytes32(eventLogs[i].data));

                console.log("coordinatorRequestId", coordinatorRequestId);
                coordinatorRequestIdFound = true;
            }
        }

        assertTrue(coordinatorRequestIdFound, "Coordinator request ID not found in events");
        assertGt(coordinatorRequestId, 0, "Coordinator request ID should be non-zero");

        // -------------------------- //
        // --- Before Fulfillment --- //
        // -------------------------- //

        // Verify the request was stored
        (uint256 vrfFeePaidByVisitor, bool fulfilled, uint256 randomWord) = wellOfReflection.requests(requestId);

        // vrfCost should be greater than 0
        assertGt(vrfFeePaidByVisitor, 0, "VRF request should have been paid");
        assertEq(fulfilled, false, "Request should not be fulfilled yet");
        assertEq(randomWord, 0, "Random word should not be set yet");

        // Visitor pays offeringAmount + vrfFee
        assertEq(visitor.balance, beforeBalance - totalAmount);

        // Verify the well depth has increased by offeringAmount
        assertEq(wellOfReflection.wellDepth(0), offeringAmount);

        // Verify the well is still paused
        assertEq(wellOfReflection.wellIsReadyToReceive(), false, "Well should be paused after offering");

        // Verify the current well ID is still 0
        assertEq(wellOfReflection.currentWellId(), 0);

        // Verify the offering was stored
        assertEq(wellOfReflection.hasOffered(keccak256(abi.encodePacked(wellId, visitor))), true);

        // ------------------------- //
        // --- After Fulfillment --- //
        // ------------------------- //

        // Fulfill the VRF request through the coordinator
        // The coordinator will call the wrapper, which will call WellOfReflection
        vrfCoordinator.fulfillRandomWords(coordinatorRequestId, address(vrfV2PlusWrapper));

        // check if words were fulfilled
        (, bool afterFulfillment_fulfilled, uint256 afterFulfillment_randomWord) = wellOfReflection.requests(requestId);

        console.log("afterFulfillment_randomWord", afterFulfillment_randomWord);

        assertEq(afterFulfillment_fulfilled, true, "Request should be fulfilled");
        assertGt(afterFulfillment_randomWord, 0, "Random word should be set");
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
