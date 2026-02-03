// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console2} from "@forge-std/console2.sol";
import {stdJson} from "@forge-std/StdJson.sol";
import {Vm} from "@forge-std/Vm.sol";

import {WellOfReflection} from "../../src/WellOfReflection.sol";

/**
 * @title MakeOffering
 * @notice Script to make a single offering to the Well of Reflection
 * @dev Usage: make offer PK=<private_key> [IMPRINT=<0-9999>]
 * Example: make offer PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 IMPRINT=42
 */
contract MakeOffering is Script {
    using stdJson for string;

    function run() external {
        uint256 visitorPk = vm.envUint("VISITOR_PK");
        address visitor = vm.addr(visitorPk);

        uint256 imprint;
        try vm.envUint("IMPRINT") returns (uint256 _imprint) {
            imprint = _imprint;
        } catch {
            revert("Must provide IMPRINT");
        }

        // Load Well address from deployment
        string memory path = "deployments/well.json";
        string memory json = vm.readFile(path);
        address wellAddr = json.readAddress(".well");

        WellOfReflection well = WellOfReflection(payable(wellAddr));

        // Get offering details
        uint256 offering = well.OFFERING_AMOUNT();
        uint256 vrfFee = well.quoteVrfFee();
        uint256 total = offering + vrfFee;

        console2.log("=== Make Offering ===");
        console2.log("Well:", wellAddr);
        console2.log("Visitor:", visitor);
        console2.log("Visitor balance:", visitor.balance);
        console2.log("Imprint:", imprint);
        console2.log("Offering amount:", offering);
        console2.log("VRF fee:", vrfFee);
        console2.log("Total required:", total);
        console2.log("Well ready:", well.wellIsReadyToReceive());
        console2.log("Current well ID:", well.currentWellId());
        console2.log("Well depth:", well.wellDepth(well.currentWellId()));

        require(well.wellIsReadyToReceive(), "Well is not ready to receive");
        require(visitor.balance >= total, "Insufficient balance");

        vm.recordLogs();
        vm.startBroadcast(visitorPk);
        well.makeOffering{value: total}(imprint);
        vm.stopBroadcast();

        // parse RequestSent(requestId, wellId, visitor)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("RequestSent(uint256,uint256,address)");

        uint256 requestId = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == wellAddr && logs[i].topics[0] == sig) {
                // requestId is indexed => topics[1]
                requestId = uint256(logs[i].topics[1]);
                break;
            }
        }
        require(requestId != 0, "RequestSent not found");

        console2.log("requestId:", requestId);

        console2.log("=== Offering Made ===");
        console2.log("New well depth:", well.wellDepth(well.currentWellId()));
    }
}
