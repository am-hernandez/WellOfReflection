// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {VRFV2PlusClient} from "@chainlink/vrf/dev/libraries/VRFV2PlusClient.sol";
import {VRFV2PlusWrapperConsumerBase} from "@chainlink/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";

/**
 * @title WellOfReflection
 * @notice
 * Accepts a fixed a fixed amount of ETH offering into a shared pool.
 * The pool may be returned to a participant based solely
 * on verifiable randomness via Chainlink VRF v2.5.
 */
contract WellOfReflection is VRFV2PlusWrapperConsumerBase {
    uint256 public constant OFFERING_AMOUNT = 3e15; // 0.003 ETHER
    uint32 public constant CALLBACK_GAS_LIMIT = 100_000;
    uint256 public currentWellId = 0;
    bool public wellIsReadyToReceive = true;
    mapping(address => uint256) public attainableReflections;
    mapping(bytes32 => bool) public hasOffered; /* visitorAddress + wellId --> hasOffered */
    mapping(uint256 => RequestStatus) public requests; /* requestId --> RequestStatus */
    mapping(uint256 => RequestContext) public requestContext; /* requestId --> RequestContext */
    mapping(uint256 => uint256) public wellDepth; /* wellId --> wellDepth */

    // =========================================================================
    //                                  STRUCTS
    // =========================================================================

    struct RequestContext {
        address visitor;
        uint256 wellId;
        uint256 imprint;
    }

    struct RequestStatus {
        uint256 vrfFeePaid;
        bool fulfilled;
        uint256 randomWord;
    }

    //==========================================================================
    //                                   EVENTS
    //==========================================================================

    event ReflectionReceived(address indexed recipient, uint256 amount);

    event RequestSent(uint256 indexed requestId, uint256 indexed wellId, address indexed visitor);

    event RequestFulfilled(
        uint256 indexed requestId,
        uint256 indexed wellId,
        address indexed visitor,
        bool reflected,
        uint256 depthAtResolution
    );

    event UnexpectedFulfillment(uint256 indexed requestId);

    // =========================================================================
    //                                   ERRORS
    // =========================================================================

    error AlreadyOffered();
    error EthTransferFailed();
    error FailedToCompleteOffering();
    error InvalidOfferingPlusFeeAmount();
    error WellIsNotReadyToReceive();
    error NothingToReceive();

    // =========================================================================
    //                                CONSTRUCTOR
    // =========================================================================

    constructor(address _vrfV2PlusWrapper) VRFV2PlusWrapperConsumerBase(_vrfV2PlusWrapper) {}

    // =========================================================================
    //                                 MODIFIERS
    // =========================================================================

    modifier onlyWhenWellIsReadyToReceive() {
        _onlyWhenWellIsReadyToReceive();
        _;
    }

    // =========================================================================
    //                             EXTERNAL FUNCTIONS
    // =========================================================================

    function makeOffering(uint256 imprint) external payable onlyWhenWellIsReadyToReceive {
        uint256 vrfFee = _quoteVrfFee();
        if (msg.value < OFFERING_AMOUNT + vrfFee) revert InvalidOfferingPlusFeeAmount();

        // get current well ID
        uint256 wellId = currentWellId;
        // check if the well is paused
        if (!wellIsReadyToReceive) revert WellIsNotReadyToReceive();
        // get visitor's addr
        address visitorAddress = msg.sender;

        // form the mapping key
        bytes32 key = keccak256(abi.encodePacked(wellId, visitorAddress));

        if (hasOffered[key]) revert AlreadyOffered();

        // Visitor makes offering
        hasOffered[key] = true;
        // increase depth of this well
        wellDepth[wellId] += OFFERING_AMOUNT;
        // pause the well
        wellIsReadyToReceive = false;

        // request random words from Chainlink VRF
        _requestRandomWords(visitorAddress, wellId, imprint);
    }

    /**
     * @notice
     * Finalizes a reflected return from the Well and transfers
     * the accumulated pool to the caller.
     */
    function receiveReflection() external {
        _finalizeReturn(payable(msg.sender));
    }

    // =========================================================================
    //                             INTERNAL FUNCTIONS
    // =========================================================================

    function _finalizeReturn(address payable recipient) internal {
        uint256 amount = attainableReflections[recipient];
        if (amount == 0) revert NothingToReceive();

        attainableReflections[recipient] = 0;

        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert EthTransferFailed();

        emit ReflectionReceived(recipient, amount);
    }

    function _onlyWhenWellIsReadyToReceive() internal view {
        if (!wellIsReadyToReceive) revert WellIsNotReadyToReceive();
    }

    function _requestRandomWords(address _visitor, uint256 _wellId, uint256 _imprint) internal {
        // Encode extraArgs for native payment
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}));

        // request random words from Chainlink VRF
        (uint256 requestId, uint256 reqPrice) = requestRandomnessPayInNative(CALLBACK_GAS_LIMIT, 5, 1, extraArgs);

        // store the request ID, well ID, visitor's address, and imprint
        requestContext[requestId] = RequestContext({visitor: _visitor, wellId: _wellId, imprint: _imprint});

        requests[requestId] = RequestStatus({vrfFeePaid: reqPrice, randomWord: 0, fulfilled: false});

        emit RequestSent(requestId, _wellId, _visitor);
    }

    function _quoteVrfFee() internal view returns (uint256) {
        return i_vrfV2PlusWrapper.calculateRequestPriceNative(CALLBACK_GAS_LIMIT, 1);
    }

    // =========================================================================
    //                                 OVERRIDES
    // =========================================================================

    /**
     * @notice
     * Fulfill the random words request and determine if the visitor wins.
     * If they win, transfer the reflection amount to their address and reset the well depth.
     * @param _requestId The request ID
     * @param _randomWords The random words
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        RequestStatus storage requestStatus = requests[_requestId];

        if (requestStatus.vrfFeePaid == 0 || requestStatus.fulfilled) emit UnexpectedFulfillment(_requestId);

        uint256 randomWord = _randomWords[0];

        requestStatus.fulfilled = true;
        requestStatus.randomWord = randomWord;
        RequestContext memory context = requestContext[_requestId];
        address visitor = context.visitor;
        uint256 wellId = context.wellId;
        uint256 imprint = context.imprint;

        bool wellReflected = (randomWord % 10_000) == imprint;
        uint256 reflectionAmount = wellDepth[wellId];

        if (wellReflected) {
            attainableReflections[visitor] += reflectionAmount;
            wellDepth[wellId] = 0;
            currentWellId++;
        }

        // unpause the well
        wellIsReadyToReceive = true;

        emit RequestFulfilled(_requestId, wellId, visitor, wellReflected, reflectionAmount);
    }
}
