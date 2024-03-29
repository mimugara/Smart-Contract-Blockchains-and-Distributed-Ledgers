// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.2;

contract OddEven {
    uint8 constant public BET_MIN         = 1;                   // The minimum bet (1 wei)
    uint8 constant public BET_MAX         = 100;                 // The maximum bet (100 wei)
    uint16 constant public REVEAL_TIMEOUT = 10 minutes;          // Timeout of the revelation phase
    uint16 private timeStampFirstReveal;                         // TimeStamp of the first reveal

    address payable addressPlayerA;
    address payable addressPlayerB;

    bytes32 private hashedMovePlayerA;
    bytes32 private hashedMovePlayerB;

    uint8 private movePlayerA;
    uint8 private movePlayerB;

    
    mapping (address => uint) private playerBalances;

    // Events
    event LogRegistration(address indexed playerAddress, uint8 playerIndex);
    event LogReveal(address indexed playerAddress, uint8 move);
    event LogTimeoutClaim(address indexed playerAddress, uint amount);
    event LogWithdrawal(address indexed playerAddress, uint amount);
    

    /*--------------------------------------------------------*/
    /*_____________________ COMMIT PHASE _____________________*/
    /*--------------------------------------------------------*/

    function obtainHash(uint8 move, string memory nonce) public pure returns (bytes32) {
        require(move >= BET_MIN && move <= BET_MAX, "Move is not within the allowed range [1,100].");
        return keccak256(abi.encode(move, nonce));
    }

    // Returns the player's index if the commit is successful. 
    // If not, reverts throwing an error.
    function commitMove(bytes32 hashedMove) external payable returns (uint8) {
        require(playerBalances[msg.sender] + msg.value >= 200, "You must have more than 200 wei in your balance to register.");
        if (addressPlayerA == address(0x0)) {
            addressPlayerA = payable(msg.sender);
            hashedMovePlayerA = hashedMove;
            playerBalances[addressPlayerA] += msg.value;
            emit LogRegistration(addressPlayerA, 1);
            return 1;
        } else if (addressPlayerB == address(0x0)) {
            require(msg.sender != addressPlayerA, "PlayerA has already registered."); 
            require(hashedMove != hashedMovePlayerA, "The hashes of the two players must be different."); 
            addressPlayerB = payable(msg.sender);
            hashedMovePlayerB = hashedMove;
            playerBalances[addressPlayerB] += msg.value;
            emit LogRegistration(addressPlayerB, 2);
            return 2;
        }
        else revert("Both players have already registered.");
    }

    /*--------------------------------------------------------*/
    /*_____________________ REVEAL PHASE _____________________*/
    /*--------------------------------------------------------*/

    // Compares hash(<move, nonce>) with the stored hashed move. If these match, returns the move.
    function reveal(uint8 move, string memory nonce) public returns (uint8) {
        require(hashedMovePlayerA != 0x0 && hashedMovePlayerB != 0x0, "The commit phase has not ended.");
        require(timeStampFirstReveal == 0 || uint16(block.timestamp) < timeStampFirstReveal + REVEAL_TIMEOUT, "The time to reveal has run out.");
        // If hashes match, the given move is saved.
        bytes32 hashedMove = obtainHash(move, nonce);
        if (msg.sender == addressPlayerA) {
            require(movePlayerA == 0, "The player has already revealed.");
            require(hashedMove == hashedMovePlayerA, "The hashes do not match. Check the entered move and nonce.");
            movePlayerA = move;
            emit LogReveal(addressPlayerA, move);
        } else if (msg.sender == addressPlayerB) {
            require(movePlayerB == 0, "The player has already revealed.");
            require(hashedMove == hashedMovePlayerB, "The hashes do not match. Check the entered move and nonce.");
            movePlayerB = move;
            emit LogReveal(addressPlayerB, move);
        } else {
            revert("The player has not been registered.");
        }
        // Timer starts after the first move is revealed.
        if (timeStampFirstReveal == 0) {
            //First player to reveal
            timeStampFirstReveal = uint16(block.timestamp);
        }
        else {
            //Last player to reveal
            updateBalances((movePlayerA + movePlayerB)%2 == 0, movePlayerA + movePlayerB);
            reset();
        }
        return move;
    }

    /*--------------------------------------------------------*/
    /*_____________________ RESULT PHASE _____________________*/
    /*--------------------------------------------------------*/

    function claimTimeout() external returns(uint8){ 
        require(timeStampFirstReveal != 0, "None of the players have yet revealed.");
        require(uint16(block.timestamp) > timeStampFirstReveal + REVEAL_TIMEOUT, "There is still time to reveal. Check revealTimeLeft().");
        // Due to the requirement one of the two moves being 0 (initialised value), 
        // the player who has not shown is penalised with the maximum he could have lost: 
        // the value of the opposing player's bet + 100.
        uint8 amount = movePlayerA + movePlayerB + 100;
        updateBalances(movePlayerB == 0, amount);
        reset();
        emit LogTimeoutClaim(msg.sender, amount);
        return amount;
    }

    // If winnerPlayerA is true, addressPlayerA pays addressPlayerB the given amount.
    // Otherwise, addressPlayerB pays addressPlayerA the given amount.
    function updateBalances(bool winnerPlayerA, uint8 amount) private {
        if (winnerPlayerA) {
            playerBalances[addressPlayerA] += amount;
            playerBalances[addressPlayerB] -= amount;
        } else {
            playerBalances[addressPlayerA] -= amount;
            playerBalances[addressPlayerB] += amount;
        } 
    }

    // Withdraw funds
    function withdrawBalance() external returns(uint) {
        require(msg.sender != addressPlayerA && msg.sender != addressPlayerB, "Before withdrawing funds, the game must end.");
        uint amountToWithdraw = playerBalances[msg.sender];
        playerBalances[msg.sender] = 0;
        payable(msg.sender).transfer(amountToWithdraw);
        emit LogWithdrawal(msg.sender, amountToWithdraw);
        return amountToWithdraw;
    }


    // Reset the game.
    function reset() private {
        timeStampFirstReveal     = 0;
        addressPlayerA         = payable(address(0x0));
        addressPlayerB         = payable(address(0x0));
        hashedMovePlayerA = 0x0;
        hashedMovePlayerB = 0x0;
        movePlayerA     = 0;
        movePlayerB     = 0;
    }

    // receive() and fallback() functions.
    receive () external payable {}
    fallback () external payable {}

    /*--------------------------------------------------------*/
    /*___________________ HELPER FUNCTIONS____________________*/
    /*--------------------------------------------------------*/

    // Returns the player (caller) index.
    // If the player does not exist returns 0.
    function getPlayerIndex() public view returns (uint8) {
        if (msg.sender == addressPlayerA) {
            return 1;
        } else if (msg.sender == addressPlayerB) {
            return 2;
        } else {
            return 0;
        }
    }

    // Returns true if both players have successfully commited a valid move. 
    // Otherwise returns false.
    function bothCommited() public view returns (bool) {
        return (hashedMovePlayerA != 0x0 && hashedMovePlayerB != 0x0);
    }

    // Returns how much time (seconds) is left for the second player to reveal the move.
    // If none of the players have revealed, returns the maximum timeout.
    function revealTimeLeft() public view returns (uint16) {
        if (timeStampFirstReveal != 0) {
            if (uint16(block.timestamp) < timeStampFirstReveal + REVEAL_TIMEOUT) 
                return timeStampFirstReveal + REVEAL_TIMEOUT - uint16(block.timestamp);
            return 0;
        }
        return REVEAL_TIMEOUT;
    }
    
    // Returns the contract balance. 
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }

    // Returns the player's balance. 
    function getMyBalance() public view returns (uint) {
        return playerBalances[msg.sender];
    }
}
