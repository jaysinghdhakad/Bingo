// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IBingoGame {
    function getBoard(uint256 _gameIndex) external view returns(bytes32);

    function joinGame(uint256 _gameIndex) external;

    function draw(uint256 _gameIndex) external;

    function callBingo(uint256 _gameIndex, uint256 patternIndex, uint256[5] calldata drawnIndexes) external;
}