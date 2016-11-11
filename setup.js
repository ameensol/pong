import fs from 'fs'
import Web3 from 'web3'
import Pudding from 'ether-pudding'
import p from 'es6-promisify'
import TestRPC from 'ethereumjs-testrpc'
import solc from 'solc'

const SOL_PATH = __dirname + '/contracts/'
const PUDDING_PATH = __dirname + '/pudding/'
const TESTRPC_PORT = 8545

export default async function () {
  // COMPILE AND PUDDINGIFY
  // Everything in this section could be moved into another process
  // watching ./contracts
  const input = {
    // 'ECVerify.sol': fs.readFileSync(SOL_PATH + 'ECVerify.sol').toString(),
    'Pong.sol': fs.readFileSync(SOL_PATH + 'Pong.sol').toString()
  }

  const output = solc.compile({ sources: input }, 1)
  if (output.errors) { throw new Error(output.errors) }

  await Pudding.save({
    abi: JSON.parse(output.contracts['Pong'].interface),
    binary: output.contracts['Pong'].bytecode
  }, PUDDING_PATH + './Pong.sol.js')

  // START TESTRPC
  /*
  await p(TestRPC.server({
    mnemonic: 'elegant ability lawn fiscal fossil general swarm trap bind require exchange ostrich'
  }).listen)(TESTRPC_PORT)
  */

  // MAKE WEB3
  const web3 = new Web3()
  web3.setProvider(new Web3.providers.HttpProvider('http://localhost:' + TESTRPC_PORT))
  const accounts = await p(web3.eth.getAccounts)()
  web3.eth.defaultAccount = accounts[0]


  // INSTANTIATE PUDDING CONTRACT ABSTRACTION
  const Pong = require(PUDDING_PATH + './Pong.sol.js')
  Pong.setProvider(new Web3.providers.HttpProvider('http://localhost:' + TESTRPC_PORT))
  const contract = await Pong.new()

  return  { contract, web3, accounts }
}
