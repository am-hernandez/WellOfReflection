// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Vm} from "forge-std/Vm.sol";

import {VRFCoordinatorV2_5Mock} from "@chainlink/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {WellOfReflection} from "../../src/WellOfReflection.sol";

/**
 * @title FulfillVRF
 * @notice Fulfill a pending VRF request through the mock coordinator (LOCAL ONLY).
 * @dev Usage: make fulfill REQUEST_ID=<id> [RANDOM_WORD=<number>]
 */
contract FulfillVRF is Script {
    using stdJson for string;

    function run() external {
        uint256 requestId;
        try vm.envUint("REQUEST_ID") returns (uint256 _requestId) {
            requestId = _requestId;
        } catch {
            revert("Must provide REQUEST_ID");
        }

        uint256 randomWord;
        try vm.envUint("RANDOM_WORD") returns (uint256 _word) {
            randomWord = _word;
        } catch {
            revert("Must provide RANDOM_WORD");
        }

        // Load deployment info
        string memory path = "deployments/well.json";
        string memory json = vm.readFile(path);
        address wrapperAddr = json.readAddress(".wrapper");
        address coordinatorAddr = json.readAddress(".coordinator");
        address wellAddr = json.readAddress(".well");

        console2.log("=== Fulfill VRF ===");
        console2.log("RequestId:", requestId);
        console2.log("Wrapper:", wrapperAddr);
        console2.log("Coordinator:", coordinatorAddr);
        console2.log("Well:", wellAddr);

        WellOfReflection well = WellOfReflection(payable(wellAddr));
        console2.log("Well ready (before):", well.wellIsReadyToReceive());
        (uint256 feePaidBefore, bool fulfilledBefore, uint256 randomWordBefore) = well.requests(requestId);
        console2.log("Request before - feePaid:", feePaidBefore);
        console2.log("Request before - fulfilled:", fulfilledBefore);
        console2.log("Request before - randomWord:", randomWordBefore);

        VRFCoordinatorV2_5Mock coordinator = VRFCoordinatorV2_5Mock(coordinatorAddr);

        uint256 pk;
        try vm.envUint("ANVIL_PRIVATE_KEY") returns (uint256 _pk) {
            pk = _pk;
        } catch {
            revert("ANVIL_PRIVATE_KEY not set in .env");
        }

        vm.startBroadcast(pk);
        vm.recordLogs();
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        coordinator.fulfillRandomWordsWithOverride(requestId, wellAddr, words);
        vm.stopBroadcast();

        console2.log("Well ready (after):", well.wellIsReadyToReceive());
        (uint256 feePaidAfter, bool fulfilledAfter, uint256 randomWordAfter) = well.requests(requestId);
        console2.log("Request after - feePaid:", feePaidAfter);
        console2.log("Request after - fulfilled:", fulfilledAfter);
        console2.log("Request after - randomWord:", randomWordAfter);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        console2.log("Recorded logs:", logs.length);
        for (uint256 i = 0; i < logs.length; i++) {
            console2.log("Log", i);
            console2.log("  emitter:", logs[i].emitter);
            if (logs[i].topics.length > 0) {
                console2.log("  topic0:");
                console2.logBytes32(logs[i].topics[0]);
            }
            console2.log("  data:");
            console2.logBytes(logs[i].data);
        }
    }
}
