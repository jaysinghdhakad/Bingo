// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


library Board{

    uint256 private constant _BOARD_MASK = uint256(type(uint192).max);

    function maskBoard(uint256 _Board) internal pure returns(uint256){
        return _Board & _BOARD_MASK;
    }
    
}