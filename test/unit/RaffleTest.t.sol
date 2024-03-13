// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
		/** Events */
	event EnteredRaffle(address indexed player);
	event PickedWinner(address indexed winner);

	Raffle raffle;
	HelperConfig helperConfig;

	uint256 entranceFee;
	uint256 interval;
	address vrfCoordinator;
	bytes32 gasLane;
	uint64 subscriptionId;
	uint32 callbackGasLimit;
	address link;

	address public PLAYER = makeAddr("player");		// Creates an address derived from the provided name.
	uint256 public constant STARTING_USER_BALANCE = 10 ether;

	function setUp() external {
		DeployRaffle deployer = new DeployRaffle();
		(raffle, helperConfig) = deployer.run();
		(
			entranceFee,
			interval,
			vrfCoordinator,
			gasLane,
			subscriptionId,
			callbackGasLimit,
			link,

		) = helperConfig.activeNetworkConfig();
		vm.deal(PLAYER, STARTING_USER_BALANCE);
	}

	modifier raffleEnteredAndTimePassed() {
		vm.prank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
		vm.warp(block.timestamp + interval + 1);
		vm.roll(block.number + 1);
		_;
	}

	modifier skipFork() {
		if (block.chainid != 31337)	// localhost
			return;
		_;
	}

	//////////////////////////
	// enterRaffle 			//
	//////////////////////////
	function testRaffleInitializesInOpenState() public view {
		assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
	}

	function testRaffleRevertWhenYouDontPayEnough() public {
		// Arrange
		vm.prank(PLAYER);
		//Act / Assert
		vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
		raffle.enterRaffle();
	}

	function testRaffleRecordsPlayerWhenTheyEnter() public {
		vm.prank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
		address playerRecorded = raffle.getPlayer(0);
		assert(playerRecorded == PLAYER);
	}

	function testEmitsEventOnEntrance() public {
		vm.prank(PLAYER);
		vm.expectEmit(true, false, false, false, address(raffle));
		emit EnteredRaffle(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
	}

	function testCantEnterWhenRaffleIsCalculating() public raffleEnteredAndTimePassed {
		raffle.performUpkeep("");

		vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
		vm.prank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
	}

	//////////////////////////
	// checkUpkeep 			//
	//////////////////////////
	function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
		// Arrange
		vm.warp(block.timestamp + interval + 1);
		vm.roll(block.number + 1);

		// Act
		(bool upkeepNeeded, ) = raffle.checkUpkeep("");

		// Assert
		assert(upkeepNeeded == false);
	}

	function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public raffleEnteredAndTimePassed {
		raffle.performUpkeep("");

		(bool upkeepNeeded, ) = raffle.checkUpkeep("");

		assert(upkeepNeeded == false);
	}

	function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
		vm.prank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
		vm.warp(block.timestamp + interval - 2);
		vm.roll(block.number + 1);

		(bool upkeepNeeded, ) = raffle.checkUpkeep("");

		assert(upkeepNeeded == false);
	}

	function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
		vm.prank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
		vm.warp(block.timestamp + interval + 1);
		vm.roll(block.number + 1);

		(bool upkeepNeeded, ) = raffle.checkUpkeep("");

		assert(upkeepNeeded == true);
	}

	//////////////////////////
	// performUpkeep 		//
	//////////////////////////
	function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public raffleEnteredAndTimePassed {
		raffle.performUpkeep("");
	}

	function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
		uint256 currentBalance = address(raffle).balance;
		uint256 numPlayers = 0;
		uint256 raffleState = uint256(raffle.getRaffleState());
		vm.expectRevert(
			abi.encodeWithSelector(
				Raffle.Raffle__UpkeepNotNeeded.selector,
				currentBalance,
				numPlayers,
				raffleState
			)
		);
		raffle.performUpkeep("");
	}

	function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed {
		vm.recordLogs();			// start recording emitted events
		raffle.performUpkeep("");	// emit requestId
		Vm.Log[] memory entries = vm.getRecordedLogs();	// store emitted events
		bytes32 requestId = entries[1].topics[1];

		Raffle.RaffleState rState = raffle.getRaffleState();

		assert(uint256(requestId) > 0);
		assert(uint256(rState) == 1);
	}

	//////////////////////////
	// fulfillRandomWords	//
	//////////////////////////
	function testFulFillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(	/* Fuzz Testing */
		uint256 randomRequestId
	) public raffleEnteredAndTimePassed skipFork {
		vm.expectRevert("nonexistent request");
		VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
	}

	function testFulfillRandomWordsPicksAWinnerAndSendsMoney() public raffleEnteredAndTimePassed skipFork {
		// Arrange
		uint256 additionalEntrants = 5;
		uint256 startingIndex = 1;	// we already have one entrant coming from the modifier
		for(uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
			address player = address(uint160(i)); // instead of using makeAddr(i)
			hoax(player, STARTING_USER_BALANCE);	// prank + deal
			raffle.enterRaffle{value: entranceFee}();
		}
		
		uint256 prize = entranceFee * (additionalEntrants + 1);
		vm.recordLogs();			// start recording emitted events
		raffle.performUpkeep("");	// emit requestId
		Vm.Log[] memory entries = vm.getRecordedLogs();	// store emitted events
		bytes32 requestId = entries[1].topics[1];
		uint256 previousTimeStamp = raffle.getLastTimeStamp();

		// Act: Pretend to be chainlink VRF to get random number & pick a winner
		VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

		// Assert
		assert(uint256(raffle.getRaffleState()) == 0);
		assert(raffle.getRecentWinner() != address(0));
		assert(raffle.getLengthOfPlayers() == 0);
		assert(previousTimeStamp < raffle.getLastTimeStamp());
		assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize - entranceFee);
	}

}