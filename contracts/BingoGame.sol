// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "contracts/Interfaces/IBingoGame.sol";
import "contracts/libs/libMask.sol";

/// @title BingoGame contract to create and play multiple bingo games simultaneously
/// @author The name of the author
/// @notice This contract can be used to create multiple bingo games simultaneoulsy.A Player can join any number of games but one board per game. The creator can draw the numbers and any player who completes bingo can claim his winnings and the game finishes.
/// @dev A game can be created using the "createGame" function. A player can join a 
contract BingoGame is Ownable, IBingoGame {
    using SafeERC20 for IERC20;
    using libMask for bytes32;

    struct GameData {
        bool isGameComplete;
        uint64 startTime; //check uint64
        uint64 lastDrawTime; //check uint64
        uint256 gameEntryFee;
        uint256 playerCount;
        bytes drawnNumbers; //check uint8
    }

    uint8[5][12] private _PATTERNS = [
        [0, 1, 2, 3, 4],
        [5, 6, 7, 8, 9],
        [10, 11, 12, 13, 0],
        [14, 15, 16, 17, 18],
        [19, 20, 21, 22, 23],
        [0, 5, 10, 14, 19],
        [1, 6, 11, 15, 20],
        [2, 7, 16, 21, 0],
        [3, 8, 12, 17, 22],
        [4, 9, 13, 18, 23],
        [0, 6, 17, 23, 0],
        [4, 8, 15, 19, 0]
    ];
    // TODO: check gas costs during hardhat tests for uint8

    // only first 24 bytes are stored but using bytes32 saves type conversion costs during operations
    // gameId => player's Address => board
    mapping(uint256 => mapping(address => bytes32)) private _playerBoard; //TODO: explore bytes
    //TODO: readable getter

    uint256 public entryFee;
    IERC20 public immutable feeToken;

    // Host cannot start draw for the first time in a game until this duration is complete
    // All the players participating in the game should join before first draw
    uint256 public minJoinDuration;

    // Host needs to wait for this duration between two consecutive draws
    uint256 public minTurnDuration;

    uint256 public gameCount;

    // gameID => game
    mapping(uint256 => GameData) public games;

    /// @param _feeToken address of fee token to be set
    /// @param _entryFee the entry fee per user per game
    /// @param _minJoinDuration the min duration between start of the game and first draw
    /// @param  _minTurnDuration the min duration between two consecutive draws
    constructor(
        address _feeToken,
        uint256 _entryFee,
        uint256 _minJoinDuration,
        uint256 _minTurnDuration
    ) Ownable() {
        feeToken = IERC20(_feeToken);
        entryFee = _entryFee;
        minJoinDuration = _minJoinDuration;
        minTurnDuration = _minTurnDuration;
    }

    /// @notice updated the minumum join duration before game can start
    /// @param _newMinJoinDuration new minimum join duration to set
    /// only owner can executed this function
    function updateMinJoinDuration(
        uint256 _newMinJoinDuration
    ) external onlyOwner {
        minJoinDuration = _newMinJoinDuration;
        emit JoinDurationUpdated(_newMinJoinDuration);
    }

    /// @notice updated the minumum turn duration between 2 consicutive
    /// @param _newMinTurnDuration new minumum turn duration to set
    /// only owner can executed this function
    function updateMinTurnDuration(
        uint256 _newMinTurnDuration
    ) external onlyOwner {
        minTurnDuration = _newMinTurnDuration;
        emit TurnDurationUpdated(_newMinTurnDuration);
    }

    /// @notice updated the entry fee for a player to join a game
    /// @param _newEntryFee new entry fee
    /// only owner can executed this function
    function updateEntryFee(uint256 _newEntryFee) external onlyOwner {
        entryFee = _newEntryFee;
        emit EntryFeeUpdated(_newEntryFee);
    }

    /// @notice returns the board of a player for a game
    /// @param  _gameIndex index of the game to of which the user wants their board
    /// @param _player address of the player to get the board of
    /// @return _board  numbers on the board .
    function getBoard(
        uint256 _gameIndex,
        address _player
    ) external view returns (uint8[24] memory _board) {
        bytes32 boardBytes = _playerBoard[_gameIndex][_player];
        require(boardBytes != bytes32(0), "Bingo: not a player");
        for (uint256 i; i < 24; i++) {
            _board[i] = uint8(boardBytes[31-i]);
        }
    }

    /// @notice creates a game of bingo
    /// @dev increase game counter and sets the games start time and entry fee
    function createGame() external {
        gameCount++; // First game index is 1
        games[gameCount].startTime = uint64(block.timestamp);
        // entryFee for a game cannot be changed once a game is created
        games[gameCount].gameEntryFee = entryFee;

        emit GameCreated(gameCount);
    }

    /// @notice function to join a game.
    /// @param _gameIndex index of the game to join
    function joinGame(uint256 _gameIndex) external {
        GameData memory game = games[_gameIndex];
        require(!game.isGameComplete, "Bingo: game over");
        require(block.timestamp > game.startTime && game.startTime != 0, "Bingo: game not created");
        require(game.drawnNumbers.length == 0, "Bingo: game in progress");
        require(
            _playerBoard[_gameIndex][msg.sender] == bytes32(0),
            "Bingo: cannot join twice"
        );

        uint256 playerCount = game.playerCount;
        bytes32 blockHash = blockhash(block.number - 1);

        // board Index starts from 0
        // playerCount is used to ensure that no board collision happens in a single block for a given gameIndex
        // gameIndex is used to achieve different boards with saame player count and block number
        _playerBoard[_gameIndex][msg.sender] = keccak256(
            abi.encodePacked(blockHash, playerCount, _gameIndex)
        ).keepFirst24Bytes();
        games[_gameIndex].playerCount++;

        feeToken.safeTransferFrom(msg.sender, address(this), entryFee);

        emit PlayerJoined(msg.sender, _gameIndex);
    }

    /// @notice function to draw a number for a game.
    /// @param _gameIndex index of the game to join
    function draw(uint256 _gameIndex) external {
        uint64 currentTime = uint64(block.timestamp);
        GameData storage game = games[_gameIndex];

        game.drawnNumbers.length != 0
            ? require(
                currentTime >= game.lastDrawTime + minTurnDuration,
                "Bingo: wait for next turn"
            )
            : require(
                currentTime >= game.startTime + minJoinDuration,
                "Bingo: game not started"
            );

        bytes1 numberDrawn = (blockhash(block.number - 1)[0]);
        game.drawnNumbers.push(numberDrawn);
        game.lastDrawTime = currentTime;

        emit Draw(_gameIndex);
    }

    /// @notice function for the players to call bingo if they win
    /// @param _gameIndex index of the game to join
    /// @param _patternIndex indexs of the patter which is user has marked for bingo
    /// @param _drawnIndexes indexs of the number which are drawn to mark the bingo pattern.
    function bingo(
        uint256 _gameIndex,
        uint256 _patternIndex,
        uint256[5] calldata _drawnIndexes
    ) public {
        require(_patternIndex < 12, "Bingo: wrong pattern index");

        uint8[5] memory pattern = _PATTERNS[_patternIndex];
        GameData memory game = games[_gameIndex];
        bytes32 board = _playerBoard[_gameIndex][msg.sender];

        uint256 patternLength = (_patternIndex == 2 ||
            _patternIndex == 7 ||
            _patternIndex == 10 ||
            _patternIndex == 11)
            ? 4
            : 5;

        for (uint256 i; i < patternLength; i++) {
            require(
                board[31 - pattern[i]] ==
                    game.drawnNumbers[_drawnIndexes[i]],
                "Bingo: drawn number and board number don't match"
            );
        }

        uint256 totalFee = game.gameEntryFee * game.playerCount;
        feeToken.safeTransfer(msg.sender, totalFee);

        games[_gameIndex].isGameComplete = true;
        emit GameOver(_gameIndex);
    }
}
