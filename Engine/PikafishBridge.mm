#import "PikafishBridge.h"
#include "attacks.h"
#include "engine.h"
#include "movegen.h"
#include "position.h"
#include "score.h"
#include "uci.h"
#include <atomic>
#include <deque>
#include <mutex>
#include <sstream>

using namespace Stockfish;

static void initializeRules() {
    static std::once_flag once;
    std::call_once(once, [] { Attacks::init(); Position::init(); });
}
static NSString *text(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}
static std::vector<std::string> nativeMoves(NSArray<NSString *> *moves) {
    std::vector<std::string> result;
    for (NSString *move in moves) result.emplace_back(move.UTF8String);
    return result;
}
static std::optional<PositionSetError> loadPosition(Position& position, std::deque<StateInfo>& states,
                                                   NSString *fen, NSArray<NSString *> *moves) {
    states.emplace_back();
    auto error = position.set(fen.UTF8String, &states.back());
    if (error) return error;
    for (NSString *value in moves) {
        Move move = UCIEngine::to_move(position, value.UTF8String);
        if (move == Move::none()) return PositionSetError("Illegal move: " + std::string(value.UTF8String));
        states.emplace_back();
        position.do_move(move, states.back());
    }
    return std::nullopt;
}
struct SearchOutput {
    std::string best, pv, bound;
    int depth = 0, score = 0;
    bool mate = false;
};

@implementation PikafishBridge {
    std::unique_ptr<Engine> _engine;
    std::mutex _control;
    std::atomic<uint64_t> _generation;
}

- (instancetype)init {
    self = [super init];
    if (self) _generation.store(0);
    return self;
}

+ (NSDictionary<NSString *, id> *)inspectFEN:(NSString *)fen moves:(NSArray<NSString *> *)moves hints:(BOOL)hints {
    initializeRules();
    Position position;
    std::deque<StateInfo> states;
    if (auto error = loadPosition(position, states, fen, moves)) return @{@"error": text(error->what())};
    NSMutableArray *legal = [NSMutableArray array];
    for (Move move : MoveList<LEGAL>(position)) [legal addObject:text(UCIEngine::move(move))];
    const bool check = bool(position.checkers());
    Value value = VALUE_ZERO;
    bool ruled = position.rule_judge(value);
    const bool finished = ruled || !legal.count;
    NSString *winner = @"";
    if (finished && !(ruled && value == VALUE_DRAW)) {
        Color color = ruled && value > 0 ? position.side_to_move() : ~position.side_to_move();
        winner = color == WHITE ? @"red" : @"black";
    }
    NSString *outcome = @"";
    if (ruled) outcome = value == VALUE_DRAW ? @"和棋" : value < 0 ? @"当前行棋方判负" : @"当前行棋方胜出";
    else if (!legal.count) outcome = check ? @"将死" : @"困毙";
    NSMutableArray *captures = [NSMutableArray array];
    if (hints) {
        for (Color color : {WHITE, BLACK}) {
            for (Move move : position.safe_captures(color)) {
                [captures addObject:@{@"move": text(UCIEngine::move(move)),
                                      @"side": color == WHITE ? @"red" : @"black"}];
            }
        }
    }
    return @{@"fen": text(position.fen()), @"legalMoves": legal, @"check": @(check),
             @"finished": @(finished), @"winner": winner, @"outcome": outcome, @"captures": captures};
}

- (uint64_t)beginRequest { return ++_generation; }

- (void)stop {
    ++_generation;
    std::lock_guard<std::mutex> lock(_control);
    if (_engine) _engine->stop();
}

- (NSDictionary<NSString *, id> *)searchFEN:(NSString *)fen moves:(NSArray<NSString *> *)moves
                              networkPath:(NSString *)networkPath milliseconds:(NSInteger)milliseconds token:(uint64_t)token {
    @autoreleasepool {
        initializeRules();
        if (token != _generation) return @{@"cancelled": @YES};
        Position validation;
        std::deque<StateInfo> states;
        if (auto error = loadPosition(validation, states, fen, moves)) return @{@"error": text(error->what())};
        if (![[NSFileManager defaultManager] fileExistsAtPath:networkPath])
            return @{@"error": @"离线引擎资源缺失，请重新构建 App。"};
        if (!_engine) {
            // Loading is off-main and outside _control so cancelling cannot block the UI.
            auto engine = std::make_unique<Engine>();
            engine->get_options().add_info_listener([](auto) {});
            engine->set_on_verify_network([](auto) {});
            auto option = [&](std::string value) {
                std::istringstream stream(value); engine->get_options().setoption(stream);
            };
            option("name EvalFile value " + std::string(networkPath.UTF8String));
            option("name Hash value 32");
            option("name Threads value 1");
            option("name MultiPV value 1");
            std::lock_guard<std::mutex> lock(_control);
            _engine = std::move(engine);
        }
        if (token != _generation) return @{@"cancelled": @YES};
        auto output = std::make_shared<SearchOutput>();
        _engine->set_on_update_no_moves([](const auto&) {});
        _engine->set_on_iter([](const auto&) {});
        _engine->set_on_start([] {});
        _engine->set_on_update_full([output](const Engine::InfoFull& info) {
            output->depth = info.depth;
            output->pv = std::string(info.pv);
            output->bound = std::string(info.bound);
            output->mate = info.score.is<Score::Mate>();
            output->score = output->mate ? info.score.get<Score::Mate>().plies : info.score.get<Score::InternalUnits>().value;
        });
        _engine->set_on_bestmove([output](std::string_view move, std::string_view) { output->best = std::string(move); });
        if (auto error = _engine->set_position(fen.UTF8String, nativeMoves(moves)))
            return @{@"error": text(error->what())};
        Search::LimitsType limits;
        limits.movetime = int(milliseconds);
        limits.startTime = now();
        {
            std::lock_guard<std::mutex> lock(_control);
            if (token != _generation) return @{@"cancelled": @YES};
            _engine->go(limits);
        }
        _engine->wait_for_search_finished();
        _engine->set_on_update_full([](const auto&) {});
        _engine->set_on_bestmove([](auto, auto) {});
        if (token != _generation) return @{@"cancelled": @YES};
        return @{@"bestMove": text(output->best), @"pv": text(output->pv), @"depth": @(output->depth),
                 @"score": @(output->score), @"mate": @(output->mate), @"bound": text(output->bound)};
    }
}

- (void)dealloc {
    if (_engine) { _engine->stop(); _engine->wait_for_search_finished(); }
}
@end
