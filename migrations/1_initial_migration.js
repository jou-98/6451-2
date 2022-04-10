const Issuer = artifacts.require("Issuer");

module.exports = function(deployer) {
  // Command Truffle to deploy the Smart Contract
  deployer.deploy(Issuer);
};