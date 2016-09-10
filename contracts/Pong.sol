// How does the game start?
// We can create a new contract for each game?
// This contract should be stateless.
// How is a move made?

// For all intents and purposes, I have to treat this like a game intended to only be played on solidity. Which means state updates come from external actors.
// No. Let's just walk through how players will interact with the contract.

// Initial - players discover eachother. This means one opens a game (channel) on a matchmaking contract, then provides connection details.
// Init 2 - The second player registers on the smart contract, then connects to the first player.
// Init 3 - The first player needs to wait until they've received the update that the second player has joined, then accept their connection.

// Game - Both players are connected, and now want to play pong. The initial state is whatever was in the channel initialization:
//  the ball is in the middle and heading right (random? - or straight if we can figure out the semicircle bounce)
//  the paddles are centered
//  the score is 0-0
// Offchain Updates - The players now produce and send each other frame by frame updates.
//  Offchain, there needs to be a function that takes user input + current state and produces a new state.
//  the user input is simply up / down keypress
// Offchain Validation - When a player receives a state, they check to make sure it's valid.
//  they either do this in the client application directly or within an EVM running alongside the client
//  if a bad state is proposed, they can submit it to the blockchain w/ the signature and the previous state
//  if it is a valid state, they will create a new state of their own, sign it, and send it back
// Dispute - If the other player does not respond within some time period, I can go to blockchain and accuse them of stalling
//  to do this, I send the previous state (signed by them) and the new state (signed by me)
//  the contract has to check:
//   the signatures are valid
//   the state is globally valid
//   the update from previous state is valid
//  if all this checks out, the contract will initiate a *waiting period*
//   during this waiting period, the other player can submit a new valid state, which goes through the same checks
//   if the other player submits a new valid state, the waiting period is cancelled, and the game can proceed
//    the game proceeds by both players reconnecting to each other and accepting the blockchain state as valid
//    note - offchain client game start code should take any valid game state as a param
//   if the other player fails to submit a new valid state, they forfeit after the waiting period is over.
//    after waiting period I can hit the chain and claimVictory.
// Happy - if there are no disputes, after some point we return the state of the game to the contract
//  play to a certain number of points - first to 7. This allows the smart contract to know when the game is over
//   anything less than this means the game is not over, and we're in a waiting period
//  smart contract checks that:
//   the signatures are valid
//   the game is over
//  if checks pass, delete the channel and update the leaderboard
//   the chessmaster score thing can be a feature on top
//   that score can be used to power different matchmaking interfaces that match you with various other players

// What is the sum of the functionality?
// Matchmaking (Open Channel, Connect)
// State Validation (Global / Local)
// Disputes / Settlement (Close Channel)

// Each Pong game has to have its own state.

// How to prevent people from just signing that the other player won 7 games without playing them?
//  who cares? let's focus on pong?
//  might mess with any attempts at a leaderboard
//   the leaderboard should be calculated chessmaster style then, not just based on wins?
//   this would address sybil attacks where someone makes a bunch of fake accounts to prop up players
//   actually you could still do this, but you would need to prop up fake accounts w/ fake wins and then use those...
//   if there is some cost with making new accounts, this could mitigate the problem
//  ... TODO ...
//  make a cost, distribute it to the top players (and / or myself?)

// How does the ball speed up?
//  need to track the number of times it has touched a paddle in the current round
//  when do we move the ball? offchain. We have to verify that it have moved the right amount, and in the right direction, and bounced properly...
// ... TODO ...
// start with no updating speed, and then go from there

contract Pong {

  // Global Constants
  uint8 GRID = 255;
  uint8 PADDLE_HEIGHT = 16;
  uint8 PADDLE_WIDTH = 4;
  uint8 PADDLE_START = 128;
  uint8 BALL_HEIGHT = 2;
  uint8 BALL_WIDTH = 2;
  uint8 BALL_START_X = 128;
  uint8 BALL_START_Y = 128;
  uint8 BALL_START_VX = 1;
  uint8 BALL_START_VY = 0;
  uint8 P1X = 0;
  uint8 P2X = 255;

  uint256 gameCounter;

  struct Game {
    uint256 id; // the ID of the game, incremented for each new game
    address p1; // player 1 address
    address p2; // player 2 address
    uint8 p1score; // player 1 score
    uint8 p2score; // player 2 score
    uint8 scoreLimit; // # points to victory
    uint8 p1y; // player 1's paddle y-position
    uint8 p2y; // player 2's paddle y-position
    int8 p1d; // player 1's paddle direction
    int8 p2d; // player 2's paddle direction
    uint8 bx; // ball x-position
    uint8 by; // ball y-position
    int8 bvx; // ball x-velocity
    int8 bvy; // ball y-velocity
    uint256 seqNum; // state channel sequence number
    uint256 paddleHits; // # of paddle hits this round
  }

  // games by ID
  mapping (uint256 => Game) games;

  // games by gamer address
  mapping (address => Game) gamers;

  function openTable() {
    // player shouldn't have open games
    if (gamers[msg.sender] != 0) {
      throw;
    }

    Game memory game = Game(
      gameCounter, // the ID of the game, incremented for each new game
      msg.sender, // player 1 address
      0x0, // player 2 address
      0, // player 1 score
      0, // player 2 score
      1, // # points to victory
      PADDLE_START, // player 1's paddle y-position
      PADDLE_START, // player 2's paddle y-position
      0, // player 1's paddle direction
      0, // player 2's paddle direction
      BALL_START_X, // ball x-position
      BALL_START_Y, // ball y-position
      BALL_START_VX, // ball x-velocity
      BALL_START_VY, // ball y-velocity
      0, // state channel sequence number
      0 // # of paddle hits this round
    );

    games[gameCounter] = game;
    gamers[msg.sender] = game;

    gameCounter++;
  }

  function joinTable(uint256 id) {
    // player shouldn't have open games
    if (gamers[msg.sender] != 0) {
      throw;
    }

    // can't join nonexistent game
    if (games[id] == 0) {
      throw;
    }

    Game memory game = games[id];

    // can't join full game
    if (game.p2 != 0x0) {
      throw;
    }

    game.p2 = msg.sender;
    gamers[msg.sender] = game;
  }

  function leaveUnjoinedTable() {
    // player has no active games
    if (gamers[msg.sender] == 0) {
      throw;
    }

    Game memory game = gamers[msg.sender];

    // can't leave full game
    if (game.p2 != 0x0) {
      throw;
    }

    delete games[game.id];
    delete gamers[msg.sender];
  }

  function isGameOver(Game game) private returns (bool) {
    return (game.p1score == game.scoreLimit || game.p2score == game.scoreLimit);
  }


  // create a new state based on the previous state.
  // does it make sense to pass in a struct? Will the function be internal / private? Yes, that works.
  function getStateUpdate(Game game, uint8 pd, address p) private returns (Game) {

    // no further updates if the game is over
    if (isGameOver(game)) {
      return game;
    }

    // check if ball is in endzone
    if (isP1point(game) || isP2point(game)) {
      if (isP1point(game)) {
        game.p1score++;
      } else {
        game.p2score++;
      }

      if (isGameOver(game)) {
        return game;
      } else {
        // TODO implement reset -- this should move the ball and the paddles to their starting positions, reset paddleHits
        return reset(game);
      }
    }

    // copy game?
    // TODO - figure out if this mutates game
    // does it matter? I don't think it should, actually.

    // update paddle direction -> move the paddle -> move the ball
    Game game2 = moveBall(movePaddles(updatePaddleDir(game, pd, p)));

    // So the loop would be:
    // 1. check if the game is over -- if so, do nothing
    // 2. check if the ball is in the endzone -- if so, reset and exit
    // 3. move the paddle
    // 4. move the ball
    // 5. check if the ball is touching the paddle or wall (or both) -- if so, bounce / adjust its position

    // it is slightly more complicated if I want to prevent the ball from traveling through the edge / endzone / paddle in 1 movement frame
    // instead of moving it the entire X/Y velocity at once, and then checking, I need to move it in steps and check after every step
    // also, a way to ensure the ball paddle / edge bouncing is idempotent is to simply move the ball back within the grid boundaries and change direction
    // this will need to be done for the paddle also, and will be simpler, so let's start there.


    // ball in endzone
    if (game.bx <= 0 || game.bx >= 255) {
      if (game.bx <= 0) {
        game.p1score++;
      } else {
        game.p2score++;
      }

      // game is over
      if (game.p1score == game.scoreLimit || game.p2score == game.scoreLimit) {
        return game;
      }

    // ball touching paddle
    } else if () {

    }

    // what do I do if player 1 scores?
    // - update the score
    // - reset the ball
    // - end the game... (it's only to 1 atm)

    // 1. update the paddle direction
    // 2. move the paddle
    // 3. move the ball
    // 4. check if the ball is touching anything, and respond
    // 4.1 - if ball is touching the endzone, end the round
    // 4.2 - if ball is touching paddle, bounce X
    // 4.3 - if ball is touching edge, bounce Y

    // To test the motion of the ball, I just need to make a sandbox grid with which to test it.
    // Create a 256 x 256, then start the ball at some point, give it a direction and a speed, and calculate each step.
    // The easy way to do this is to hardcode 3 bounce values. The harder way is to actually compute an angle based on the position.
    // The hard way might be impossible because of the lack of floats, and could be expensive if to compensate we're using huge integers.
    // Easier still is to keep the Vx constant and only switch up the Vy based on the paddle contact point.
    // That means regardless of where the ball hits the paddle, it will still return to the other side in the same time.
    // Later, if we speed up the ball, we just multiply both values by the speed. This means Vx is the speed.
    // So at time 0, Vx is 1. If we hit the center of the paddle, Vy remains 0. If we hit edge, Vy would be 2 * Vx = 2.
    // If we hit between center and edge, Vy would be 1. Then the ball would move x + Vx, y + Vy.
  }

  function updatePaddleDir(Game game, uint pd, address p) private returns (Game game) {
    if (p == game.p1) {
      game.p1d = pd;
    } else (p == game.p2) {
      game.p2d = pd;
    }
  }

  function correctPaddle(uint8 py) private returns (uint8 py) {
    if (py < 0) {
      return 0;
    } else if (py > GRID) {
      return GRID;
    } else {
      return py;
    }
  }

  function movePaddles(Game game) private returns (Game game) {
    game.p1y = correctPaddle(game.p1y + (game.p1d * abs(game.bvx)));
    game.p2y = correctPaddle(game.p2y + (game.p2d * abs(game.bvx)));
  }

  function moveBall(Game game) private returns (Game game) {
    // TODO change to stepwise check instead of moving the ball fully
    game.bx = game.bx + game.bvx;
    game.by = game.by + game.bvy;
  }

  // partner is unresponsive, request to close the table, initiating the challenge period
  function requestCloseTable(
    // Previous Game State
    uint256 id_1, // the ID of the game, incremented for each new game
    address p1_1, // player 1 address
    address p2_1, // player 2 address
    uint8 p1score_1, // player 1 score
    uint8 p2score_1, // player 2 score
    uint8 scoreLimit_1, // # points to victory
    uint8 p1y_1, // player 1's paddle y-position
    uint8 p2y_1, // player 2's paddle y-position
    int8 p1d_1, // player 1's paddle direction
    int8 p2d_1, // player 2's paddle direction
    uint8 bx_1, // ball x-position
    uint8 by_1, // ball y-position
    int8 bvx_1, // ball x-velocity
    int8 bvy_1, // ball y-velocity
    uint256 seqNum_1, // state channel sequence number
    uint256 paddleHits_1, // # of paddle hits this round
    // Current Game State
    uint256 id_2, // the ID of the game, incremented for each new game
    address p1_2, // player 1 address
    address p2_2, // player 2 address
    uint8 p1score_2, // player 1 score
    uint8 p2score_2, // player 2 score
    uint8 scoreLimit_2, // # points to victory
    uint8 p1y_2, // player 1's paddle y-position
    uint8 p2y_2, // player 2's paddle y-position
    int8 p1d_2, // player 1's paddle direction
    int8 p2d_2, // player 2's paddle direction
    uint8 bx_2, // ball x-position
    uint8 by_2, // ball y-position
    int8 bvx_2, // ball x-velocity
    int8 bvy_2, // ball y-velocity
    uint256 seqNum_2, // state channel sequence number
    uint256 paddleHits_2, // # of paddle hits this round
    // Signatures (sig1 is counterparty on prev state, sig2 is msg.sender on current)
    bytes sig1,
    bytes sig2
  ) {




    // From here, I think there is an easy way to do this and a hard way.
    // The hard way would be to manually check every set of params and all conditions.
    //  Addresses are the same
    //  scores are the same (unless someone just scored)
    //  the y position of the paddle... whose is supposed to be updated?
    //  ... and so on
    // The easy way would be to reproduce the expected new state based on the user input
    // The user input then becomes explicitely part of the state of the channel
    //  this is even though it doesn't make sense for it be part of the instantaneous snapshot of the game
    // so we would include a "paddle direction" 1,0,-1 for both paddles (optimization, combine them into 1 byte)
    // so each player would be responsible for creating the next state based on the paddle direction of the other player
    // then, we would write that function in solidity, and probably just use the same one...
    // I think this makes sense

    // when I receive a state, it has my previous paddle direction.
    // First, I update my paddle direction. Then I produce a new state. Then I sign it and send.
    // The counterparty has the previous state. They update my paddle direction and see if the state they produce is the same.

    // Updating the state in this case is: Moving both paddles according to their direction, and the ball.
    // What if a player wins?

    // If a player wins, the valid state update would be to incremenet the score, reset the game and keep going.

    // Here we wouldn't do this instantly. We would wait a few seconds before we start up the game again.
    // but we want both the clients to see the point scored. There needs to be a way to sync states without updating them.
    // The client has two sets of functionality:
    //  communicating w/ the peer (of which a subset is exchanging channel messages)
    //  communicating w/ the blockchain to open and close channels
    // so when we win, the client would know that we won, and it would send a different message. It would send the victory state, signed.
    //  and wait for the signature before continuing, or take that state to the blockchain.

  }

  // send me the ID of the game,
  // I'm verifying the state update in the context of an existing channel
  // Why would the user call this function? They are probably trying to`
  function verifyStateUpdate(Game state1, Game state2) {

  }

  function isValidStateUpdate(Game s1, Game s2) {

  }

  function isBallTouchingP1(Game game) private returns (bool) {
    return isBallTouchingPaddle(game.bx, game.by, game.p1x, game.p1y);
  }

  function isBallTouchingP2(Game game) private returns (bool) {
    return isBallTouchingPaddle(game.bx, game.by, game.p2x, game.p2y);
  }

  function isBallTouchingPaddle(bx, by, px, py) private returns (bool) {
    return rectanglesOverlap(
      bx, // l1x
      by + BALL_HEIGHT, // l1y
      px, // l2x
      py + PADDLE_HEIGHT, // l2y
      bx + BALL_WIDTH, // r1x
      by, // r1y
      px + PADDLE_WIDTH, // r2x
      py // r2y
    );
  }


  // Top left corners are L1, L2
  // Bottom right corners are R1, R2
  // L1, L2, R1, R2 are all (x, y) coordinates
  // http://www.geeksforgeeks.org/find-two-rectangles-overlap/
  function rectanglesOverlap(l1x, l1y, l2x, l2y, r1x, r1y, r2x, r2y) private returns (bool) {
    // one rectangle is to the left of the other
    if (l1x > r2x || l2x > r1x) {
      return false;
    }

    // one rectangle is above the other
    if (l1y < r2y || l2y < r1y) {
      return false;
    }

    return true;
  }

  function isBallTouchingP2() {}

  function isBallTouchingEdge(Game game) private returns (Game game) {
    return game.by >= 255 || game.by <= 0;
  }

  function isP1point(Game game) private returns (bool) {
    return game.bx >= 255;
  }

  function isP2point(Game game) private returns (bool) {
    return game.bx <= 0;
  }

  function reset() {

  }


  function abs(int8 a) private returns (uint8 b) {
    return a > 0 ? uint8(a) : uint8(-1 * a);
  }




}




