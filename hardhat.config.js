require("@nomicfoundation/hardhat-toolbox");
require('solidity-coverage');
require("hardhat-gas-reporter");


// TODO: setup hardhat properly
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.17",
  gasReporter: {
    enabled: true,
    currency: 'CHF',
    gasPrice: 21
  }
};
