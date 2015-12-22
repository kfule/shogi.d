import std.datetime;
import std.stdio;
import std.conv;
import std.random;

import shogiban;
import move;

immutable string strCaseTest = q{
  case "test1":  //ランダムムーブテスト(doMoveのみ)
    testRandomMove();
    break;
  case "test2":  //ランダムムーブテスト(undo込み)
    testRandomMove !true();
    break;
  case "test3":  //指し手生成の速度測定(初期局面)
    testMovegen("lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1");
    break;
  case "test4":  //指し手生成の速度測定(指し手生成祭り)
    testMovegen("l6nl/5+P1gk/2np1S3/p1p4Pp/3P2Sp1/1PPb2P1P/P5GS1/R8/LN4bKL w GR5pnsg 1");
    break;
};

//ランダムに玉が取られるまで手を進める, を繰り返すテスト
// reverse: trueのとき終局から初期局面まで巻き戻す処理も実施
void testRandomMove(bool reverse = false)() {
  Random gen;
  gen.seed(10);
  auto s = new Shogiban;
  s.init;
  Move[1024] buf;
  Move* mlist;
  Move[] ml;
  Move[] mlback;
  ulong count = 0UL;

  //時間計測開始
  auto sw = new StopWatch(AutoStart.yes);
  foreach (i; 0..100000) {
    if (i % 10000 == 0) i.writeln;
    static if (reverse) mlback = mlback.init;
    static if (!reverse) s.init;
    while (true) {
      //手生成
      mlist = buf.ptr;
      mlist = s.genMovesB(mlist);
      mlist = s.genDropsB(mlist);
      ml = buf.ptr[0..(mlist - buf.ptr)];
      //盤面更新
      static if (reverse) mlback ~= s.doMove(ml[uniform(0, ml.length, gen)]);
      static if (!reverse) s.doMove(ml[uniform(0, ml.length, gen)]);
      count++;
      if (!s._bbWOU) break;

      //手生成
      mlist = buf.ptr;
      mlist = s.genMovesW(mlist);
      mlist = s.genDropsW(mlist);
      ml = buf.ptr[0..(mlist - buf.ptr)];
      //盤面更新
      static if (reverse) mlback ~= s.doMove(ml[uniform(0, ml.length, gen)]);
      static if (!reverse) s.doMove(ml[uniform(0, ml.length, gen)]);
      count++;
      if (!s._bbBOU) break;
    }
    //盤面を初期局面まで戻す
    static if (reverse) foreach_reverse(m; mlback) { s.undoMove(m); }
  }
  //計測終了
  sw.stop();

  s.writeln;
  // static if (reverse) { "初期局面に戻ってるか確認！".writeln; }
  writeln("time : " ~text(sw.peek().msecs / 1000.0));
  writeln("moves: " ~text(count));
  writeln("moves/sec: " ~text(count * 1000 / sw.peek().msecs));
  writeln;
}

///手生成の速度測定
void testMovegen(string sfen) {
  auto s = new Shogiban;
  s.setSFEN(sfen);
  s.writeln;
  Move[1024] buf;
  Move* mlist;
  Move[] ml;
  immutable ulong count = 10_000_000;
  auto sw = new StopWatch(AutoStart.yes);
  foreach (i; 0..count) {
    mlist = buf.ptr;
    mlist = s.genMovesW(mlist);
    mlist = s.genDropsW(mlist);
  }
  sw.stop();
  ml = buf.ptr[0..(mlist - buf.ptr)];
  writeln("moves: ", ml.length);
  writeln("time : " ~text(sw.peek().msecs / 1000.0));
  writeln("execs: " ~text(count));
  writeln("execs/sec: " ~text(count * 1000 / sw.peek().msecs));
  writeln;
}
