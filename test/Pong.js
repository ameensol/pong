import test from 'blue-tape'
import p from 'es6-promisify'
import setup from '../setup'

test('Pong', async () => {

    let { web3, contract, accounts } = await setup()

    test('watt watt', async t => {
      let a = await contract.test.call(1)
      t.equal(+a.toString(), 2)
    })
})
