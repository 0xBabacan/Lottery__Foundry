// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
	function run() external returns (uint64) {
		return createSubscriptionUsingConfig();
	}

	function createSubscriptionUsingConfig() public returns (uint64) {
		HelperConfig helperConfig = new HelperConfig();
		(, , address vrfCoordinator, , , , , uint256 deployerKey) = helperConfig.activeNetworkConfig();
		return createSubscription(vrfCoordinator, deployerKey);
	}

	function createSubscription(address vrfCoordinator, uint256 deployerKey) public returns(uint64) {
		console.log("Creating subscription on ChainId: ", block.chainid);
		vm.startBroadcast(deployerKey);
		uint64 subId = VRFCoordinatorV2Mock(vrfCoordinator).createSubscription();
		vm.stopBroadcast();
		console.log("Your sub id is: ", subId);
		console.log("Please update subscriptionId in HelperConfig");
		return subId;
	}
}

contract FundSubscription is Script {
	uint96 public constant FUND_AMOUNT = 3 ether;

	function run() external {
		fundSubscriptionUsingConfig();
	}

	function fundSubscriptionUsingConfig() public {
		HelperConfig helperConfig = new HelperConfig();
		(, , address vrfCoordinator, , uint64 subId, , address link, uint256 deployerKey) = helperConfig.activeNetworkConfig();
		fundSubscription(vrfCoordinator, subId, link, deployerKey);
	}

	function fundSubscription(address vrfCoordinator, uint64 subId, address link, uint256 deployerKey) public {
		console.log("Funding subscription: ", subId);
		console.log("Using vrfCoordinator: ", vrfCoordinator);
		console.log("On ChainID: ", block.chainid);
		if (block.chainid == 31337) {	// if localhost (Hardhat network always uses the chain id from your config, which defaults to 31337)
			vm.startBroadcast(deployerKey);
			VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(subId, FUND_AMOUNT);
			vm.stopBroadcast();
		} else {
			vm.startBroadcast();
			/** Explanation is taken from https://updraft.cyfrin.io/courses/foundry/smart-contract-lottery/subscription-ui
			 *
			 *  When you try to "add funds" to your subscription on vrf.chainlink website (https://vrf.chain.link/sepolia/9957)
			 * you click "confirm" button by providing some amount of LINK. Then Metamask pop-up
			 * and ask your confirmation. In this pop-up, if you are at "details" tab you can see
			 * the function name which will be called after the confirmation: "Transfer And Call".
			 * When you click the ethscan link right next to the function name in the pop-up you can 
			 * check out details on ethscan: see on which contract the "TransferAndCall" function is
			 * called @Contract tab [Contract Name: LinkToken] (https://sepolia.etherscan.io/address/0x779877A7B0D9E8603169DdbD7836e478b4624789#code)
			 *
			 *  To sum up:
			 * In order to provide the cost of VRF use, we need to transfer LINK token 
			 * from our wallet to the Subscription Contract (vrfCoordinator) by calling 
			 * the TransferAndCall function of LINK token
			*/
			LinkToken(link).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subId));
			vm.stopBroadcast();
		}
	}
}

contract AddConsumer is Script {

	function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(raffle);
	} 

	function addConsumerUsingConfig(address raffle) public {
		HelperConfig helperConfig = new HelperConfig();
		(
			,
			,
			address vrfCoordinator,
			,
			uint64 subId,
			,
			,
			uint256 deployerKey
		) = helperConfig.activeNetworkConfig();
		addConsumer(vrfCoordinator, subId, raffle, deployerKey);
	}

	function addConsumer(address vrfCoordinator, uint64 subId, address raffle, uint256 deployerKey) public {
		console.log("Adding consumer contract: ", raffle);
		console.log("Using vrfCoordinator: ", vrfCoordinator);
		console.log("On ChainID: ", block.chainid);
		vm.startBroadcast(deployerKey);
		/** Explanation is taken from https://updraft.cyfrin.io/courses/foundry/smart-contract-lottery/add-consumer
		 * VRFCoordinatorV2Mock::function addConsumer(uint64 _subId, address _consumer) external override onlySubOwner(_subId)
		 *
		 *  When you try to "add consumer" to your subscription on vrf.chainlink website (https://vrf.chain.link/sepolia/9957)
		 * you click "Add Consumer" button by providing the consumer contract address. Metamask will pop-up
		 * and ask your confirmation. In this pop-up, if you are at "details" tab you can see
		 * the function name which will be called after the confirmation: "Add Consumer".
		 * When you click the ethscan link right next to the function name in the pop-up you can 
		 * check out details on ethscan: see on which contract the "addConsumer" function is
		 * called @Contract tab [Contract Name: VRFCoordinatorV2] (https://sepolia.etherscan.io/address/0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625#code)
		 * So we need to write a script which will call "addConsumer" automatically for us.
		*/
		VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subId, raffle);
		vm.stopBroadcast();
	}
}