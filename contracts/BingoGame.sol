// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "contracts/interfaces/IBingo.sol";
import "contracts/libs/libMask.sol";

// TODO: add dev comments
contract BingoGame is Ownable, IBingo {
    using SafeERC20 for IERC20;
    using libMask for uint256;

    struct GameData {
        bool isGameComplete;
        uint256 startTime; //check uint64
        uint256 lastDrawTime; //check uint64
        uint256 gameEntryFee;
        uint256 playerCount;
        uint256[] drawnNumbers; //check uint8
    }

    uint256[5] private _PATTERN_INDEX_1 = [1,2,3,4,5]; // TODO: check gas costs during hardhat tests for uint8
    uint256[5] private _PATTERN_INDEX_2 = [6,7,8,9,10];
    uint256[5] private _PATTERN_INDEX_3 = [11,12,0,13,14];
    uint256[5] private _PATTERN_INDEX_4 = [15,16,17,18,19];
    uint256[5] private _PATTERN_INDEX_5 = [20,21,22,23,24];
    uint256[5] private _PATTERN_INDEX_6 = [1,6,11,15,20];
    uint256[5] private _PATTERN_INDEX_7 = [2,7,12,16,21];
    uint256[5] private _PATTERN_INDEX_8 = [3,8,0,17,22];
    uint256[5] private _PATTERN_INDEX_9 = [4,9,13,18,23];
    uint256[5] private _PATTERN_INDEX_10 = [5,10,14,19,24];
    uint256[5] private _PATTERN_INDEX_11 = [1,7,0,18,24];
    uint256[5] private _PATTERN_INDEX_12 = [5,9,0,16,20];

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
   
   // TODO: add events
    event GameCreated(uint256 indexed gameId);
    event JoinDurationUpdated(uint256 indexed newMinJoinDuration);
    event TurnDurationUpdated(uint256 indexed newMinTurnDuration);
    event EntryFeeUpdated(uint256 indexed newEntryFee);
    event PlayerJoined(uint256 indexed gameIndex, address indexed player);
    event Draw(uint256 indexed gameIndex, uint256 numberDrawn);
    event GameOver(uint256 indexed gameIndex, address indexed winner);

    /// @param _feeToken address of fee token to be set
    /// @param _entryFee the entry fee per user per game 
    /// @param _minJoinDuration the min duration between start of the game and first draw
    /// @param  _minTurnDuration the min duration between two consecutive draws
    constructor(address _feeToken, uint256 _entryFee, uint256 _minJoinDuration, uint256 _minTurnDuration) Ownable() {
        feeToken = IERC20(_feeToken);
        entryFee = _entryFee;
        minJoinDuration = _minJoinDuration;
        minTurnDuration = _minTurnDuration;
    }

    // Admin functions

    /// @notice updated the minumum join duration before game can start
    /// @param _newMinJoinDuration new minimum join duration to set 
    /// only owner can executed this function
    function updateMinJoinDuration(uint256 _newMinJoinDuration) external onlyOwner() {
        minJoinDuration = _newMinJoinDuration;
        emit JoinDurationUpdated(_newMinJoinDuration);
    }

    /// @notice updated the minumum turn duration between 2 consicutive
    /// @param _newMinTurnDuration new minumum turn duration to set 
    /// only owner can executed this function
    function updateMinTurnDuration(uint256 _newMinTurnDuration) external onlyOwner() {
        minTurnDuration = _newMinTurnDuration;
        emit TurnDurationUpdated(_newMinTurnDuration);
    }

    /// @notice updated the entry fee for a player to join a game 
    /// @param _newEntryFee new entry fee
    /// only owner can executed this function
    function updateEntryFee(uint256 _newEntryFee) external onlyOwner() {
        entryFee = _newEntryFee;
        emit EntryFeeUpdated(_newEntryFee);
    }

    /// @notice returns the board of a player for a game
    /// @param  _gameIndex index of the game to of which the user wants their board
    /// @return board in bytes32 fformat.
    function getBoard(uint256 _gameIndex, address _player) external view returns(uint8[24] _board){
        bytes32 boardBytes = _playerBoard[_gameIndex][_player];

        // TODO: complete
        board = [boardBytes[0], boardBytes[1], boardBytes[2], ...];
    }

    /// @notice creates a game of bingo 
    /// @dev increase game counter and sets the games start time and entry fee
    function createGame() external {
        gameCount++; // First game index is 1
        games[gameCount].startTime = block.timestamp;
        // entryFee for a game cannot be changed once a game is created
        games[gameCount].gameEntryFee = entryFee;

        emit GameCreated(gameCount);
    }

    /// @notice function to join a game.
    /// @param _gameIndex index of the game to join
    function joinGame(uint256 _gameIndex) external {
        GameData memory game = games[_gameIndex];
        require(!game.isGameComplete, "Bingo: game over");
        require(block.timestamp > game.startTime, "Bingo: game not created");
        require(game.drawnNumbers.length == 0, "Bingo: game in progress");
        require(_playerBoard[_gameIndex][msg.sender] == bytes32(0), "Bingo: cannot join twice");

        uint256 playerCount = game.playerCount;
        bytes32 blockHash = blockhash(block.number - 1);

        // board Index starts from 0
        // playerCount is used to ensure that no board collision happens in a single block for a given gameIndex
        // gameIndex is used to achieve different boards with saame player count and block number
        uint256 boardBase = uint256(keccak256(abi.encodePacked(blockHash, playerCount, _gameIndex)));
        
        uint256 board = boardBase.maskBoard();
        _playerBoard[_gameIndex][msg.sender] = bytes32(board);
        games[_gameIndex].playerCount++;
        feeToken.safeTransferFrom(msg.sender, address(this), entryFee);
        emit PlayerJoined(msg.sender, _gameIndex);
    }

    /// @notice function to draw a number for a game.
    /// @param _gameIndex index of the game to join
    function draw(uint256 _gameIndex) external {
        uint256 currentTime = block.timestamp;
        GameData storage game = games[_gameIndex];

        game.drawnNumbers.length != 0 ? require(currentTime >= game.lastDrawTime + minTurnDuration, "Bingo: to early to draw") : require(currentTime >= game.startTime + minJoinDuration, "Bingo: Game not started yet");

        uint8 numberDrawn = uint8(blockhash(block.number - 1)[0]);
        game.drawnNumbers.push(numberDrawn);
        game.lastDrawTime = currentTime;
        emit Draw(_gameIndex, numberDrawn);
    }

    /// @notice function for the players to call bingo if they win
    /// @param _gameIndex index of the game to join
    /// @param patternIndex indexs of the patter which is user has marked for bingo
    /// @param drawnIndexes indexs of the number which are drawn to mark the bingo pattern.
    function bingo(uint256 _gameIndex, uint256 patternIndex, uint256[5] calldata drawnIndexes) public {
        uint256[5] memory pattern;
        address sender = msg.sender;
        if (patternIndex == 1) {
           pattern = _PATTERN_INDEX_1;
        } else if (patternIndex == 2) {
            pattern = _PATTERN_INDEX_2;
        } else if (patternIndex == 3) {
            pattern = _PATTERN_INDEX_3;
        } else if (patternIndex == 4) {
            pattern = _PATTERN_INDEX_4;
        } else if (patternIndex == 5) {
            pattern = _PATTERN_INDEX_5;
        } else if (patternIndex == 6) {
            pattern = _PATTERN_INDEX_6;
        } else if (patternIndex == 7) {
            pattern = _PATTERN_INDEX_7;
        } else if (patternIndex == 8) {
            pattern = _PATTERN_INDEX_8;
        } else if (patternIndex == 9) {
            pattern = _PATTERN_INDEX_9;
        } else if (patternIndex == 10) {
            pattern = _PATTERN_INDEX_10;
        } else if (patternIndex == 11) {
            pattern = _PATTERN_INDEX_11;
        } else if (patternIndex == 12) {
            pattern = _PATTERN_INDEX_12;
        } else {
            revert("Bingo: wrong pattern index");
        }

        GameData memory game = games[_gameIndex];
        bytes32 board = _playerBoard[_gameIndex][sender];
        for(uint256 i; i < pattern.length; i++){
            uint256 boardNumberIndex = pattern[i];
            uint256 drawNumberIndex = drawnIndexes[i];
            if(boardNumberIndex != 0){
              require(board[boardNumberIndex - 1] == bytes1(uint8(game.drawnNumbers[drawNumberIndex])), "Bingo: drawn number and board number don't match");
            }
        }
        uint256 totalFee = game.gameEntryFee * game.playerCount;
        feeToken.safeTransfer(sender, totalFee);

        games[_gameIndex].isGameComplete = true;
        emit GameOver(_gameIndex,sender);
    }
}