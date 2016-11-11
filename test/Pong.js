import test from 'blue-tape'
import p from 'es6-promisify'
import setup from '../setup'

test('Pong', async () => {

    let { web3, contract, accounts } = await setup()

    test('watt watt', async t => {
      let a = await contract.test.call(1)
      t.equal(+a.toString(), 2)
    })

    test('openTable', async t => {
      // all initial values are correct
      // games mapping has been updated
      // gamers mapping has been updated
      // game counter has been incremented
    })

    test('openTable should fail ', async t => {
    })
})
