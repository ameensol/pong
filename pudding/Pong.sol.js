var Web3 = require("web3");
var SolidityEvent = require("web3/lib/web3/event.js");

(function() {
  // Planned for future features, logging, etc.
  function Provider(provider) {
    this.provider = provider;
  }

  Provider.prototype.send = function() {
    this.provider.send.apply(this.provider, arguments);
  };

  Provider.prototype.sendAsync = function() {
    this.provider.sendAsync.apply(this.provider, arguments);
  };

  var BigNumber = (new Web3()).toBigNumber(0).constructor;

  var Utils = {
    is_object: function(val) {
      return typeof val == "object" && !Array.isArray(val);
    },
    is_big_number: function(val) {
      if (typeof val != "object") return false;

      // Instanceof won't work because we have multiple versions of Web3.
      try {
        new BigNumber(val);
        return true;
      } catch (e) {
        return false;
      }
    },
    merge: function() {
      var merged = {};
      var args = Array.prototype.slice.call(arguments);

      for (var i = 0; i < args.length; i++) {
        var object = args[i];
        var keys = Object.keys(object);
        for (var j = 0; j < keys.length; j++) {
          var key = keys[j];
          var value = object[key];
          merged[key] = value;
        }
      }

      return merged;
    },
    promisifyFunction: function(fn, C) {
      var self = this;
      return function() {
        var instance = this;

        var args = Array.prototype.slice.call(arguments);
        var tx_params = {};
        var last_arg = args[args.length - 1];

        // It's only tx_params if it's an object and not a BigNumber.
        if (Utils.is_object(last_arg) && !Utils.is_big_number(last_arg)) {
          tx_params = args.pop();
        }

        tx_params = Utils.merge(C.class_defaults, tx_params);

        return new Promise(function(accept, reject) {
          var callback = function(error, result) {
            if (error != null) {
              reject(error);
            } else {
              accept(result);
            }
          };
          args.push(tx_params, callback);
          fn.apply(instance.contract, args);
        });
      };
    },
    synchronizeFunction: function(fn, instance, C) {
      var self = this;
      return function() {
        var args = Array.prototype.slice.call(arguments);
        var tx_params = {};
        var last_arg = args[args.length - 1];

        // It's only tx_params if it's an object and not a BigNumber.
        if (Utils.is_object(last_arg) && !Utils.is_big_number(last_arg)) {
          tx_params = args.pop();
        }

        tx_params = Utils.merge(C.class_defaults, tx_params);

        return new Promise(function(accept, reject) {

          var decodeLogs = function(logs) {
            return logs.map(function(log) {
              var logABI = C.events[log.topics[0]];

              if (logABI == null) {
                return null;
              }

              var decoder = new SolidityEvent(null, logABI, instance.address);
              return decoder.decode(log);
            }).filter(function(log) {
              return log != null;
            });
          };

          var callback = function(error, tx) {
            if (error != null) {
              reject(error);
              return;
            }

            var timeout = C.synchronization_timeout || 240000;
            var start = new Date().getTime();

            var make_attempt = function() {
              C.web3.eth.getTransactionReceipt(tx, function(err, receipt) {
                if (err) return reject(err);

                if (receipt != null) {
                  // If they've opted into next gen, return more information.
                  if (C.next_gen == true) {
                    return accept({
                      tx: tx,
                      receipt: receipt,
                      logs: decodeLogs(receipt.logs)
                    });
                  } else {
                    return accept(tx);
                  }
                }

                if (timeout > 0 && new Date().getTime() - start > timeout) {
                  return reject(new Error("Transaction " + tx + " wasn't processed in " + (timeout / 1000) + " seconds!"));
                }

                setTimeout(make_attempt, 1000);
              });
            };

            make_attempt();
          };

          args.push(tx_params, callback);
          fn.apply(self, args);
        });
      };
    }
  };

  function instantiate(instance, contract) {
    instance.contract = contract;
    var constructor = instance.constructor;

    // Provision our functions.
    for (var i = 0; i < instance.abi.length; i++) {
      var item = instance.abi[i];
      if (item.type == "function") {
        if (item.constant == true) {
          instance[item.name] = Utils.promisifyFunction(contract[item.name], constructor);
        } else {
          instance[item.name] = Utils.synchronizeFunction(contract[item.name], instance, constructor);
        }

        instance[item.name].call = Utils.promisifyFunction(contract[item.name].call, constructor);
        instance[item.name].sendTransaction = Utils.promisifyFunction(contract[item.name].sendTransaction, constructor);
        instance[item.name].request = contract[item.name].request;
        instance[item.name].estimateGas = Utils.promisifyFunction(contract[item.name].estimateGas, constructor);
      }

      if (item.type == "event") {
        instance[item.name] = contract[item.name];
      }
    }

    instance.allEvents = contract.allEvents;
    instance.address = contract.address;
    instance.transactionHash = contract.transactionHash;
  };

  // Use inheritance to create a clone of this contract,
  // and copy over contract's static functions.
  function mutate(fn) {
    var temp = function Clone() { return fn.apply(this, arguments); };

    Object.keys(fn).forEach(function(key) {
      temp[key] = fn[key];
    });

    temp.prototype = Object.create(fn.prototype);
    bootstrap(temp);
    return temp;
  };

  function bootstrap(fn) {
    fn.web3 = new Web3();
    fn.class_defaults  = fn.prototype.defaults || {};

    // Set the network iniitally to make default data available and re-use code.
    // Then remove the saved network id so the network will be auto-detected on first use.
    fn.setNetwork("default");
    fn.network_id = null;
    return fn;
  };

  // Accepts a contract object created with web3.eth.contract.
  // Optionally, if called without `new`, accepts a network_id and will
  // create a new version of the contract abstraction with that network_id set.
  function Contract() {
    if (this instanceof Contract) {
      instantiate(this, arguments[0]);
    } else {
      var C = mutate(Contract);
      var network_id = arguments.length > 0 ? arguments[0] : "default";
      C.setNetwork(network_id);
      return C;
    }
  };

  Contract.currentProvider = null;

  Contract.setProvider = function(provider) {
    var wrapped = new Provider(provider);
    this.web3.setProvider(wrapped);
    this.currentProvider = provider;
  };

  Contract.new = function() {
    if (this.currentProvider == null) {
      throw new Error("Contract error: Please call setProvider() first before calling new().");
    }

    var args = Array.prototype.slice.call(arguments);

    if (!this.unlinked_binary) {
      throw new Error("Contract error: contract binary not set. Can't deploy new instance.");
    }

    var regex = /__[^_]+_+/g;
    var unlinked_libraries = this.binary.match(regex);

    if (unlinked_libraries != null) {
      unlinked_libraries = unlinked_libraries.map(function(name) {
        // Remove underscores
        return name.replace(/_/g, "");
      }).sort().filter(function(name, index, arr) {
        // Remove duplicates
        if (index + 1 >= arr.length) {
          return true;
        }

        return name != arr[index + 1];
      }).join(", ");

      throw new Error("Contract contains unresolved libraries. You must deploy and link the following libraries before you can deploy a new version of Contract: " + unlinked_libraries);
    }

    var self = this;

    return new Promise(function(accept, reject) {
      var contract_class = self.web3.eth.contract(self.abi);
      var tx_params = {};
      var last_arg = args[args.length - 1];

      // It's only tx_params if it's an object and not a BigNumber.
      if (Utils.is_object(last_arg) && !Utils.is_big_number(last_arg)) {
        tx_params = args.pop();
      }

      tx_params = Utils.merge(self.class_defaults, tx_params);

      if (tx_params.data == null) {
        tx_params.data = self.binary;
      }

      // web3 0.9.0 and above calls new twice this callback twice.
      // Why, I have no idea...
      var intermediary = function(err, web3_instance) {
        if (err != null) {
          reject(err);
          return;
        }

        if (err == null && web3_instance != null && web3_instance.address != null) {
          accept(new self(web3_instance));
        }
      };

      args.push(tx_params, intermediary);
      contract_class.new.apply(contract_class, args);
    });
  };

  Contract.at = function(address) {
    if (address == null || typeof address != "string" || address.length != 42) {
      throw new Error("Invalid address passed to Contract.at(): " + address);
    }

    var contract_class = this.web3.eth.contract(this.abi);
    var contract = contract_class.at(address);

    return new this(contract);
  };

  Contract.deployed = function() {
    if (!this.address) {
      throw new Error("Cannot find deployed address: Contract not deployed or address not set.");
    }

    return this.at(this.address);
  };

  Contract.defaults = function(class_defaults) {
    if (this.class_defaults == null) {
      this.class_defaults = {};
    }

    if (class_defaults == null) {
      class_defaults = {};
    }

    var self = this;
    Object.keys(class_defaults).forEach(function(key) {
      var value = class_defaults[key];
      self.class_defaults[key] = value;
    });

    return this.class_defaults;
  };

  Contract.extend = function() {
    var args = Array.prototype.slice.call(arguments);

    for (var i = 0; i < arguments.length; i++) {
      var object = arguments[i];
      var keys = Object.keys(object);
      for (var j = 0; j < keys.length; j++) {
        var key = keys[j];
        var value = object[key];
        this.prototype[key] = value;
      }
    }
  };

  Contract.all_networks = {
  "default": {
    "abi": [
      {
        "constant": false,
        "inputs": [],
        "name": "leaveZeroStateTable",
        "outputs": [],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [],
        "name": "claimVictory",
        "outputs": [],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {
            "name": "a",
            "type": "uint256"
          }
        ],
        "name": "test",
        "outputs": [
          {
            "name": "",
            "type": "uint256"
          }
        ],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [],
        "name": "punishBadState",
        "outputs": [],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {
            "name": "id",
            "type": "uint256"
          }
        ],
        "name": "joinTable",
        "outputs": [],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [],
        "name": "openTable",
        "outputs": [],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [],
        "name": "requestForfeit",
        "outputs": [],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [],
        "name": "issueChallenge",
        "outputs": [],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [],
        "name": "forceForfeit",
        "outputs": [],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [],
        "name": "forfeit",
        "outputs": [],
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [],
        "name": "leaveUnjoinedTable",
        "outputs": [],
        "type": "function"
      }
    ],
    "unlinked_binary": "0x606060405260ff600060006101000a81548161ffff02191690837e010000000000000000000000000000000000000000000000000000000000009081020402179055506010600060026101000a81548161ffff02191690837e010000000000000000000000000000000000000000000000000000000000009081020402179055506004600060046101000a81548161ffff02191690837e010000000000000000000000000000000000000000000000000000000000009081020402179055506002600060029054906101000a900460010b60010b056002600060009054906101000a900460010b60010160010b0503600060066101000a81548161ffff02191690837e010000000000000000000000000000000000000000000000000000000000009081020402179055506000600060086101000a81548161ffff02191690837e01000000000000000000000000000000000000000000000000000000000000908102040217905550600060049054906101000a900460010b600060009054906101000a900460010b036000600a6101000a81548161ffff02191690837e0100000000000000000000000000000000000000000000000000000000000090810204021790555060056000600c6101000a81548160ff0219169083021790555060026000600d6101000a81548161ffff02191690837e0100000000000000000000000000000000000000000000000000000000000090810204021790555060026000600f6101000a81548161ffff02191690837e0100000000000000000000000000000000000000000000000000000000000090810204021790555060026000600f9054906101000a900460010b60010b056002600060009054906101000a900460010b60010160010b0503600060116101000a81548161ffff02191690837e0100000000000000000000000000000000000000000000000000000000000090810204021790555060026000600d9054906101000a900460010b60010b056002600060009054906101000a900460010b60010160010b0503600060136101000a81548161ffff02191690837e010000000000000000000000000000000000000000000000000000000000009081020402179055506001600060156101000a81548161ffff02191690837e010000000000000000000000000000000000000000000000000000000000009081020402179055506000600060176101000a81548161ffff02191690837e010000000000000000000000000000000000000000000000000000000000009081020402179055506007600060196101000a81548160ff02191690830217905550610b0a806103d56000396000f36060604052361561008d5760e060020a600035046308129cc8811461008f5780631abddf331461008f57806329e99f07146100945780632c32502f1461008f5780633823bb03146100ac57806349d0598114610150578063773aa1d71461008f578063aac1916d1461008f578063ea828a1d1461008f578063f3d86e4a1461008f578063f6ae7c5f146101f1575b005b61008d565b60043560020260408051918252519081900360200190f35b61008d60043561024060405190810160405280600081526020016040604051908101604052806002905b60008152602001906001900390816100d657905050815260200161018060405190810160405280600c905b60008152602001906001900390816101015750508152600060208281018290526040838101839052606093909301829052600160a060020a033316825260039052908120541461029357610002565b61008d61024060405190810160405280600081526020016040604051908101604052806002905b600081526020019060019003908161017757905050815260200161018060405190810160405280600c905b60008152602001906001900390816101a25750508152600060208281018290526040838101839052606093909301829052600160a060020a033316825260039052908120541461053657610002565b61008d61024060405190810160405280600081526020016040604051908101604052806002905b600081526020019060019003908161021857905050815260200161018060405190810160405280600c905b60008152602001906001900390816102435750508152600060208281018290526040838101839052606093909301829052600160a060020a0333168252600390529081205414156108ff57610002565b60008281526002602052604081205414156102ad57610002565b600082815260026020818152604080519381902060c08501825280548552815180830192839052909392850192909160018501919082845b8154600160a060020a03168152600191909101906020018083116102e5575b50505091835250506040805161018081019182905260209290920191906003840190600c90826000855b82829054906101000a900460010b8152602001906002019060208260010104928301926001038202915080841161032e57505050928452505050600482015460ff8181166020848101919091526101009092041660408301526005929092015460609190910152818101510151909150600160a060020a03166000146103b357610002565b6020818101805133600160a060020a03169083018190526000908152600392839052604090819020845181559151849360018401929084019190839082015b828111156104205781548351600160a060020a031990911617825560209290920191600191909101906103f2565b506104469291505b808211156104a5578054600160a060020a0319168155600101610428565b505060408201516003820190600483019082610180820160005b838211156104a957835183826101000a81548161ffff021916908360f060020a9081020402179055509260200192600201602081600101049283019260010302610460565b5090565b80156104d75782816101000a81549061ffff02191690556002016020816001010492830192600103026104a9565b50506104f99291505b808211156104a557805461ffff191681556001016104e0565b5050606082015160048201805460808501516101000260ff199190911690921761ff00191691909117905560a09190910151600591909101555050565b506040805160c08181018352600180548084528451808601865233600160a060020a03168152600060208281018290528681019283528751610180810189528281528254680100000000000000008104870b870b8284015266010000000000008104870b870b828b01819052606083810186905260808481018790526a010000000000000000000084048a0b8a0b60a0868101919091529a85019290925260e08401869052710100000000000000000000000000000000008304890b890b6101008501527301000000000000000000000000000000000000008304890b890b61012085015275010000000000000000000000000000000000000000008304890b890b61014085015277010000000000000000000000000000000000000000000000909204880b880b610160840152898b01929092526007908901528701829052948601819052918252600290935284902083518155915192938493918301916003840191839082015b828111156106cd5781548351600160a060020a0319909116178255602092909201916001919091019061069f565b506106d9929150610428565b505060408201516003820190600483019082610180820160005b8382111561073857835183826101000a81548161ffff021916908360f060020a90810204021790555092602001926002016020816001010492830192600103026106f3565b80156107665782816101000a81549061ffff0219169055600201602081600101049283019260010302610738565b50506107739291506104e0565b5050606082015160048201805460808501516101000260ff199190911690921761ff00191691909117905560a0919091015160059190910155600160a060020a0333166000908152600360208181526040909220835181559183015183929160018301919083019060029083909160200282015b828111156108155781548351600160a060020a031990911617825560209290920191600191909101906107e7565b50610821929150610428565b505060408201516003820190600483019082610180820160005b8382111561088057835183826101000a81548161ffff021916908360f060020a908102040217905550926020019260020160208160010104928301926001030261083b565b80156108ae5782816101000a81549061ffff0219169055600201602081600101049283019260010302610880565b50506108bb9291506104e0565b5050606082015160048201805460808501516101000260ff199190911690921761ff00191691909117905560a0919091015160059190910155600180548101905550565b33600160a060020a0316600090815260036020908152604091829020825160c0810184528154815283518085019485905290939192840191600184019060029082845b8154600160a060020a0316815260019190910190602001808311610942575b50505091835250506040805161018081019182905260209290920191906003840190600c90826000855b82829054906101000a900460010b8152602001906002019060208260010104928301926001038202915080841161098b57505050928452505050600482015460ff8181166020848101919091526101009092041660408301526005929092015460609190910152818101510151909150600160a060020a0316600014610a1057610002565b60026000506000826000015181526020019081526020016000206000600082016000506000905560018201600050600081556001016000905560038201600050600090556004820160006101000a81549060ff02191690556004820160016101000a81549060ff0219169055600582016000506000905550506003600050600033600160a060020a031681526020019081526020016000206000600082016000506000905560018201600050600081556001016000905560038201600050600090556004820160006101000a81549060ff02191690556004820160016101000a81549060ff0219169055600582016000506000905550505056",
    "events": {},
    "updated_at": 1478884089458
  }
};

  Contract.checkNetwork = function(callback) {
    var self = this;

    if (this.network_id != null) {
      return callback();
    }

    this.web3.version.network(function(err, result) {
      if (err) return callback(err);

      var network_id = result.toString();

      // If we have the main network,
      if (network_id == "1") {
        var possible_ids = ["1", "live", "default"];

        for (var i = 0; i < possible_ids.length; i++) {
          var id = possible_ids[i];
          if (Contract.all_networks[id] != null) {
            network_id = id;
            break;
          }
        }
      }

      if (self.all_networks[network_id] == null) {
        return callback(new Error(self.name + " error: Can't find artifacts for network id '" + network_id + "'"));
      }

      self.setNetwork(network_id);
      callback();
    })
  };

  Contract.setNetwork = function(network_id) {
    var network = this.all_networks[network_id] || {};

    this.abi             = this.prototype.abi             = network.abi;
    this.unlinked_binary = this.prototype.unlinked_binary = network.unlinked_binary;
    this.address         = this.prototype.address         = network.address;
    this.updated_at      = this.prototype.updated_at      = network.updated_at;
    this.links           = this.prototype.links           = network.links || {};
    this.events          = this.prototype.events          = network.events || {};

    this.network_id = network_id;
  };

  Contract.networks = function() {
    return Object.keys(this.all_networks);
  };

  Contract.link = function(name, address) {
    if (typeof name == "function") {
      var contract = name;

      if (contract.address == null) {
        throw new Error("Cannot link contract without an address.");
      }

      Contract.link(contract.contract_name, contract.address);

      // Merge events so this contract knows about library's events
      Object.keys(contract.events).forEach(function(topic) {
        Contract.events[topic] = contract.events[topic];
      });

      return;
    }

    if (typeof name == "object") {
      var obj = name;
      Object.keys(obj).forEach(function(name) {
        var a = obj[name];
        Contract.link(name, a);
      });
      return;
    }

    Contract.links[name] = address;
  };

  Contract.contract_name   = Contract.prototype.contract_name   = "Contract";
  Contract.generated_with  = Contract.prototype.generated_with  = "3.2.0";

  // Allow people to opt-in to breaking changes now.
  Contract.next_gen = false;

  var properties = {
    binary: function() {
      var binary = Contract.unlinked_binary;

      Object.keys(Contract.links).forEach(function(library_name) {
        var library_address = Contract.links[library_name];
        var regex = new RegExp("__" + library_name + "_*", "g");

        binary = binary.replace(regex, library_address.replace("0x", ""));
      });

      return binary;
    }
  };

  Object.keys(properties).forEach(function(key) {
    var getter = properties[key];

    var definition = {};
    definition.enumerable = true;
    definition.configurable = false;
    definition.get = getter;

    Object.defineProperty(Contract, key, definition);
    Object.defineProperty(Contract.prototype, key, definition);
  });

  bootstrap(Contract);

  if (typeof module != "undefined" && typeof module.exports != "undefined") {
    module.exports = Contract;
  } else {
    // There will only be one version of this contract in the browser,
    // and we can use that.
    window.Contract = Contract;
  }
})();
