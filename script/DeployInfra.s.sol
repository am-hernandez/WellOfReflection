// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {MockLinkToken} from "@chainlink/mocks/MockLinkToken.sol";
import {MockV3Aggregator} from "@chainlink/tests/MockV3Aggregator.sol";

/**
 * @title DeployInfra
 * @notice Deploys Chainlink VRF infrastructure and creates a subscription.
 * @dev Run this first, then use `cast` to read the subId from the SubscriptionCreated event,
 *      then run DeployWrapperAndWell.s.sol with that subId.
 *
 * Usage:
 *   make deploy-infra
 *   # Then read subId from logs and update deployments/infra.json
 *   make deploy-well
 */
contract DeployInfra is Script {
    using stdJson for string;

    function run() external {
        require(block.chainid == 31337, "Local only");

        uint256 pk;
        try vm.envUint("ANVIL_PRIVATE_KEY") returns (uint256 _pk) {
            pk = _pk;
        } catch {
            revert("ANVIL_PRIVATE_KEY not set in .env");
        }
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // Deploy mocks
        MockLinkToken link = new MockLinkToken();
        MockV3Aggregator linkNativeFeed = new MockV3Aggregator(18, 5e17); // 0.5 ETH per LINK

        VRFCoordinatorV2_5Mock coordinator = new VRFCoordinatorV2_5Mock(
            100000000000000000, // baseFee
            1000000000, // gasPriceLink
            4190000000000000 // weiPerUnitLink
        );

        // Create subscription - emits SubscriptionCreated(subId, owner)
        coordinator.createSubscription();

        vm.stopBroadcast();

        // Write infra addresses (subId will be added by Makefile after reading logs)
        string memory path = "deployments/infra.json";
        string memory out = string.concat(
            "{",
            '"deployer":"',
            vm.toString(deployer),
            '",',
            '"link":"',
            vm.toString(address(link)),
            '",',
            '"linkNativeFeed":"',
            vm.toString(address(linkNativeFeed)),
            '",',
            '"coordinator":"',
            vm.toString(address(coordinator)),
            '"',
            "}"
        );
        vm.writeFile(path, out);

        console2.log("=== Infrastructure Deployed ===");
        console2.log("Deployer:", deployer);
        console2.log("Link:", address(link));
        console2.log("LinkNativeFeed:", address(linkNativeFeed));
        console2.log("Coordinator:", address(coordinator));
        console2.log("");
        console2.log("Wrote:", path);
        console2.log("");
        console2.log("Next: Run 'make deploy-well' to read subId from logs and deploy wrapper+well");
    }
}
