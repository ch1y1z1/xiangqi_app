#include "attacks.h"
#include "position.h"
#include "movegen.h"
#include "engine.h"
#include "uci.h"
#include "score.h"
#include <iostream>
#include <sstream>
#include <thread>
#include <chrono>
#include <atomic>
using namespace Stockfish;
int main(int argc, char** argv) {
  if (argc < 2) return 2;
  Attacks::init(); Position::init();
  Position p; StateInfo st;
  auto err = p.set(StartFEN, &st);
  if (err) { std::cerr << err->what(); return 3; }
  auto count = MoveList<LEGAL>(p).size();
  std::cout << "initial_legal_moves=" << count << std::endl;
  if (count != 44) return 4;
  Position invalid; StateInfo inv;
  err=invalid.set("9/9/9/9/9/9/9/9/9/9 w - - 0 1",&inv);
  std::cout << "empty_board_validation=" << (err ? err->what() : "unexpectedly accepted") << std::endl;
  if (!err) return 5;
  Engine engine;
  engine.get_options().add_info_listener([](auto){});
  engine.set_on_verify_network([](std::string_view s){ std::cout << s << std::endl; });
  engine.set_on_update_no_moves([](const auto&){});
  engine.set_on_iter([](const auto&){});
  engine.set_on_start([](){});
  std::atomic<int> updates{0};
  std::string best; int depth=0;
  engine.set_on_update_full([&](const Engine::InfoFull& info){ updates++; depth=info.depth; });
  engine.set_on_bestmove([&](std::string_view b, std::string_view){ best=std::string(b); });
  auto option=[&](std::string s){std::istringstream is(s);engine.get_options().setoption(is);};
  option(std::string("name EvalFile value ")+argv[1]);
  option("name Threads value 1");option("name Hash value 32");option("name MultiPV value 3");
  if (engine.set_position(StartFEN,{})) return 6;
  Search::LimitsType limits;limits.movetime=250;limits.startTime=now();
  engine.go(limits);engine.wait_for_search_finished();
  std::cout << "timed_search best=" << best << " depth=" << depth << " updates=" << updates << std::endl;
  if (UCIEngine::to_move(p,best)==Move::none() || updates<1) return 7;
  auto invalidMoves=engine.set_position(StartFEN,{"a0a9"});
  std::cout << "illegal_move_validation=" << (invalidMoves ? invalidMoves->what() : "unexpectedly accepted") << std::endl;
  if (!invalidMoves) return 8;
  const std::string endgame="4k4/9/3R5/9/9/9/9/9/9/4K4 w - - 0 1";
  err=engine.set_position(endgame,{});
  std::cout << "facing_kings_validation=" << (err ? err->what() : "accepted") << std::endl;
  if(!err) return 9;
  const std::string validEndgame="3k5/9/4R4/9/9/9/9/9/9/4K4 w - - 0 1";
  err=engine.set_position(validEndgame,{});
  if(err){std::cout << "endgame error=" << err->what() << std::endl;return 10;}
  best.clear();updates=0;limits=Search::LimitsType{};limits.movetime=250;limits.startTime=now();
  engine.go(limits);engine.wait_for_search_finished();
  std::cout << "endgame_search best=" << best << " depth=" << depth << " updates=" << updates << std::endl;
  best.clear();limits=Search::LimitsType{};limits.infinite=1;limits.startTime=now();
  engine.go(limits);std::this_thread::sleep_for(std::chrono::milliseconds(50));
  auto t=std::chrono::steady_clock::now();engine.stop();engine.wait_for_search_finished();
  auto ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-t).count();
  std::cout << "stop_latency_ms=" << ms << " best=" << best << std::endl;
  std::cout << "PROBE_PASSED" << std::endl;
  return 0;
}
