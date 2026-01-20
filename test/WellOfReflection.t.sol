// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Test} from "@forge-std/Test.sol";
import {Vm} from "@forge-std/Vm.sol";
import {MockLinkToken} from "@chainlink/mocks/MockLinkToken.sol";
import {MockV3Aggregator} from "@chainlink/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {VRFV2PlusWrapper} from "@chainlink/vrf/dev/VRFV2PlusWrapper.sol";
import {WellOfReflection} from "../src/WellOfReflection.sol";

contract WellOfReflectionTest is Test {
    WellOfReflection public wellOfReflection;
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

        // Set gas price for VRF price calculation (0.00033 gwei)
        vm.txGasPrice(0.00033 gwei);

        // Deploy WellOfReflection with the wrapper
        wellOfReflection = new WellOfReflection(address(vrfV2PlusWrapper));

        visitor1 = makeAddr("visitor1");
        visitor2 = makeAddr("visitor2");
        visitor3 = makeAddr("visitor3");

        // give ETH to visitors
        vm.deal(visitor1, ethAmount);
        vm.deal(visitor2, ethAmount);
        vm.deal(visitor3, ethAmount);
    }

    struct OfferingLogs {
        uint256 wellId;
        address visitor;
        uint256 requestId;
        uint256 coordinatorRequestId;
    }

    // =========================================================================
    //                               Helper Functions
    // =========================================================================

    /**
     * @notice Helper function to make an offering and parse the logs
     * @param visitor The address making the offering
     * @param imprint The imprint value to use
     * @param totalAmount The total amount to send (offeringAmount + vrfFee)
     * @return logs Struct containing wellId, visitor, requestId, and coordinatorRequestId
     */
    function makeOfferingAndParseLogs(address visitor, uint256 imprint, uint256 totalAmount)
        internal
        returns (OfferingLogs memory logs)
    {
        vm.recordLogs();
        vm.startPrank(visitor);
        wellOfReflection.makeOffering{value: totalAmount}(imprint);
        vm.stopPrank();

        Vm.Log[] memory eventLogs = vm.getRecordedLogs();

        bytes32 requestSentEventSignature = keccak256("RequestSent(uint256,uint256,address)");
        bytes32 randomWordsRequestedEventSignature =
            keccak256("RandomWordsRequested(bytes32,uint256,uint256,uint256,uint16,uint32,uint32,bytes,address)");

        for (uint256 i = 0; i < eventLogs.length; i++) {
            // Extract data from RequestSent event emitted by WellOfReflection
            // Event: RequestSent(uint256 indexed requestId, uint256 indexed wellId, address indexed visitor)
            // The requestId here is the wrapper's request ID (returned from requestRandomnessPayInNative)
            if (
                eventLogs[i].emitter == address(wellOfReflection) && eventLogs[i].topics[0] == requestSentEventSignature
            ) {
                // topics[1] = requestId, topics[2] = wellId, topics[3] = visitor
                logs.requestId = uint256(eventLogs[i].topics[1]);
                logs.wellId = uint256(eventLogs[i].topics[2]);
                logs.visitor = address(uint160(uint256(eventLogs[i].topics[3])));
            }

            // Get the coordinator's request ID from RandomWordsRequested event
            if (
                eventLogs[i].emitter == address(vrfCoordinator)
                    && eventLogs[i].topics[0] == randomWordsRequestedEventSignature
            ) {
                // Event: RandomWordsRequested(bytes32 indexed keyHash, uint256 requestId, uint256 preSeed, ...)
                (uint256 coordinatorRequestId) = abi.decode(eventLogs[i].data, (uint256));
                logs.coordinatorRequestId = coordinatorRequestId;
            }
        }

        return logs;
    }

    function test_makeOffering() public {
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
        OfferingLogs memory logs = makeOfferingAndParseLogs(visitor1, 1, totalAmount);

        // After the offering
        assertEq(wellOfReflection.hasOffered(key), true);
        assertEq(wellOfReflection.wellDepth(wellId), offeringAmount);

        // Get the VRF cost that was paid
        (uint256 vrfFeePaidByVisitor, bool fulfilled, uint256 randomWord) = wellOfReflection.requests(logs.requestId);

        uint256 vrfCost = vrfFeePaidByVisitor;
        assertEq(vrfCost, vrfFee);
        assertEq(fulfilled, false);
        assertEq(randomWord, 0);

        uint256 contractBalanceAfter = address(wellOfReflection).balance;
        // VRF fee is paid from the fee portion, offering remains in the contract
        uint256 expectedBalance = offeringAmount;

        // Balance should equal offering amount (VRF fee was deducted from the fee portion)
        assertEq(contractBalanceAfter, expectedBalance, "Contract balance should equal offering amount");
        assertEq(visitor1.balance, ethAmount - totalAmount);
        assertEq(wellOfReflection.currentWellId(), 0);
    }

    function test_fulfillRandomWords() public {
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

        OfferingLogs memory logs = makeOfferingAndParseLogs(visitor, 1, totalAmount);

        // -------------------------- //
        // --- Before Fulfillment --- //
        // -------------------------- //

        // Verify the request was stored
        (uint256 vrfFeePaidByVisitor, bool fulfilled, uint256 randomWord) = wellOfReflection.requests(logs.requestId);

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
        vrfCoordinator.fulfillRandomWords(logs.coordinatorRequestId, address(vrfV2PlusWrapper));

        // check if words were fulfilled
        (, bool afterFulfillment_fulfilled, uint256 afterFulfillment_randomWord) =
            wellOfReflection.requests(logs.requestId);

        console.log("afterFulfillment_randomWord", afterFulfillment_randomWord);

        assertEq(afterFulfillment_fulfilled, true, "Request should be fulfilled");
        assertGt(afterFulfillment_randomWord, 0, "Random word should be set");
    }

    ///@notice Test will override the random words to 1234567890
    ///@notice and use the imprint 7890 because 1234567890 % 10000 = 7890
    function test_receiveReflection() public {
        // Set gas price for VRF price calculation (3 gwei)
        vm.txGasPrice(0.00033 gwei);

        address visitor = visitor1;
        uint256 wellId = wellOfReflection.currentWellId();
        uint256 imprint = 7890;
        uint256 offeringAmount = wellOfReflection.OFFERING_AMOUNT();
        uint256 beforeBalance = visitor.balance;
        uint256 vrfFee = vrfV2PlusWrapper.calculateRequestPriceNative(100_000, 1);
        uint256 totalAmount = offeringAmount + vrfFee;
        uint256 beforeOfferingWellDepth = wellOfReflection.wellDepth(wellId);

        assertEq(beforeOfferingWellDepth, 0, "Before offering, well depth should be equal to 0");

        // --------------------- //
        // --- Make Offering --- //
        // --------------------- //

        OfferingLogs memory logs = makeOfferingAndParseLogs(visitor, imprint, totalAmount);

        uint256 afterOfferingWellDepth = wellOfReflection.wellDepth(wellId);
        assertEq(
            afterOfferingWellDepth, offeringAmount, "After offering, well depth should be equal to offering amount"
        );

        // ---------------------------- //
        // --- Fulfill Random Words --- //
        // ---------------------------- //

        // Override the random words to 1234567890
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1234567890;
        vrfCoordinator.fulfillRandomWordsWithOverride(logs.coordinatorRequestId, address(vrfV2PlusWrapper), randomWords);

        // ------------------------- //
        // --- After Fulfillment --- //
        // ------------------------- //

        // check if words were fulfilled
        (, bool afterFulfillment_fulfilled, uint256 afterFulfillment_randomWord) =
            wellOfReflection.requests(logs.requestId);

        console.log("afterFulfillment_randomWord", afterFulfillment_randomWord);

        assertEq(afterFulfillment_fulfilled, true, "Request should be fulfilled");
        assertEq(afterFulfillment_randomWord, 1234567890, "Random word should be set to 1234567890");

        // -------------------------- //
        // --- Receive Reflection --- //
        // -------------------------- //

        // Receive the reflection
        vm.startPrank(visitor);
        wellOfReflection.receiveReflection();
        vm.stopPrank();

        // check if reflection was received
        assertEq(visitor.balance, beforeBalance - totalAmount + afterOfferingWellDepth);
        assertEq(wellOfReflection.wellDepth(wellId), 0);
        assertEq(wellOfReflection.attainableReflections(visitor), 0);
        assertEq(wellOfReflection.currentWellId(), 1);
        assertEq(wellOfReflection.wellIsReadyToReceive(), true);
    }
}
