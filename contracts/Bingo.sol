// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libBoard.sol";

// 1  3  5  7  2
// 11 23 11 45 56
// 34 24 *  4  6
// 23 1  5  7  9
// 8  12 17 28 40

// drawnindexes [2,6, 1,3,0]
// drawnNumbers [8, 34, 1, 23, 9, 7, 11]

// TODO: Create IBingoInterface
contract Bingo is Ownable {
    using SafeERC20 for IERC20;
    using Board for uint256;

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
    // only first 24 bytes are stored but using bytes32 saves type conversion costs during operations

    mapping(uint256 => mapping(address => bytes32)) private _playerBoard; //TODO: explore bytes
    //TODO: readable getter
   
   // TODO: add events
    event GameCreated(uint256 indexed gameId);
    event JoinDurationUpdated(uint256 indexed newMinJoinDuration);
    event TurnDurationUpdated(uint256 indexed newMinTurnDuration);
    event EntryFeeUpdated(uint256 indexed newEntryFee);
    event PlayerJoined(address indexed player, uint256 indexed _gameIndex );
    event Draw(uint256 indexed gameIndex, uint256 indexed numberDrawn);
    event GameOver(uint256 indexed gameIndex, address winner);

    constructor(address _feeToken, uint256 _entryFee, uint256 _minJoinDuration, uint256 _minTurnDuration) Ownable() {
        feeToken = IERC20(_feeToken);
        entryFee = _entryFee;
        minJoinDuration = _minJoinDuration;
        minTurnDuration = _minTurnDuration;
    }
    // TODO: add admin functions
    function updateMinJoinDuration(uint256 _newMinJoinDuration) external onlyOwner() {
        minJoinDuration = _newMinJoinDuration;
        emit JoinDurationUpdated(_newMinJoinDuration);
    }
    function updateMinTurnDuration(uint256 _newMinTurnDuration) external onlyOwner() {
        minTurnDuration = _newMinTurnDuration;
        emit TurnDurationUpdated(_newMinTurnDuration);
    }

    function updateEntryFee(uint256 _newEntryFee) external onlyOwner() {
        entryFee = _newEntryFee;
        emit EntryFeeUpdated(_newEntryFee);
    }
    function createGame() external {
        gameCount++; // First game index is 1
        games[gameCount].startTime = block.timestamp;
        games[gameCount].gameEntryFee = entryFee;
        emit GameCreated(gameCount);
    }
    // getter function for board 
    function getBoard(uint256 _gameIndex) external view returns(bytes32){
        return bytes32(_playerBoard[_gameIndex][msg.sender]);
    }

    function joinGame(uint256 _gameIndex) external {
        // TODO: add check current timestamp is greater than game start time (Game exists)
        GameData memory game = games[_gameIndex];
        require(!game.isGameComplete, "Bingo: Game already finished");
        require(block.timestamp > game.startTime, "Bingo: Game not started yet");
        // TODO: add check first draw has not been done
        require(game.drawnNumbers.length == 0, "Bingo: Game already begain");
        require(_playerBoard[_gameIndex][msg.sender] == bytes32(0), "Bingo: Player already joined");
        // generate board
        // maximum number of boards that can be created in a game = 2^256
        // board Index starts from 0 (changed)
        // playerCount is used to ensure that no board collision happens in a single block in a game
        // Assumption: since this is assumed to be a good source of randomness blockhash(block.number - 1) should not produce same board between two games in a block
        // otherwise we should use chainlink orcles for true randomness
        // TODO: mask la        // update draw timestamp
        // emit eventst 8 bytes
        uint256 playerCount = game.playerCount;
        bytes32 blockHash = blockhash(block.number - 1);
        uint256 boardBase = uint256(keccak256(abi.encodePacked(blockHash, playerCount))); // TODO: reduce state reads when function is complete
        uint256 board = boardBase.maskBoard();
        _playerBoard[_gameIndex][msg.sender] = bytes32(board);
        games[_gameIndex].playerCount++;
        feeToken.safeTransferFrom(msg.sender, address(this), entryFee);
        emit PlayerJoined(msg.sender, _gameIndex);
    }

    function draw(uint256 _gameIndex) external {
        uint256 currentTime = block.timestamp;
        GameData storage game = games[_gameIndex];

        game.drawnNumbers.length != 0 ? require(currentTime >= game.lastDrawTime + minTurnDuration, "Bingo: to early to draw") : require(currentTime >= game.startTime + minJoinDuration, "Bingo: Game not started yet");

        uint8 numberDrawn = uint8(blockhash(block.number - 1)[0]);
        game.drawnNumbers.push(numberDrawn);
        game.lastDrawTime = currentTime;
        emit Draw(_gameIndex, numberDrawn);
    }
    function callBingo(uint256 _gameIndex, uint256 patternIndex, uint256[5] calldata drawnIndexes) public {
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