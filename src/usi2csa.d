import std.stdio, std.range, std.algorithm, std.ascii, std.random, std.conv, core.thread, std.string, std.experimental.logger, std.datetime;
import shogi;

//ランダムな英数字文字列を生成する
auto randomStr = (int len) { return iota(len).map !(_ => (letters ~digits)[uniform(0, $)]).array; };
//スリープ関数
alias sleep = core.thread.Thread.sleep;

class USIEngine {
  import std.process;
  ProcessPipes pipes;
  Logger logger;

  this(string cmd, Logger l = new NullLogger) {
    pipes = pipeProcess(cmd.split, Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout);
    pipes.stdin.setvbuf(0, _IONBF);
    logger = l;
  }

  void send(string str) {
    pipes.stdin.writeln(str);
    logger.log("[Engine.send] ", str);
  }
  auto receiveByLine() { return pipes.stdout.byLine.tee !(a => logger.log("[Engine.recv] ", a), No.pipeOnPop); }
  string wait(string str) {
    foreach (a; receiveByLine) {
      if (a.canFind(str)) return cast(string) a;
    }
    assert(false);
  }
}

//簡単なバッファ付きソケットクラス
class CSASocket {
  import std.socket;
  TcpSocket socket;
  char[1024] sockBuffer;                   //ソケット用バッファ
  string readBuffer;                       //読み出し用バッファ
  string lastString;                       //最後にreadlnで取得した文字列
  immutable int startTimeKeepAlive = 600;  //キープアライブ開始までの時間
  immutable int keepAliveInterval = 60;    //キープアライブのインターバル
  Logger logger;                           //ロガー

  this(string addr = "localhost", ushort port = 4081, Logger l = new NullLogger) {
    try {
      logger = l;
      socket = new TcpSocket(new InternetAddress(addr, port));
      socket.blocking(false);
      //長時間通信がない場合にKeepAliveパケットを送るようにする
      socket.setKeepAlive(startTimeKeepAlive, keepAliveInterval);
    } catch (Exception e) {
      e.msg.writeln;
    }
  }

  string readln() {
    //受信して結合
    auto i = socket.receive(sockBuffer);
    if (i != Socket.ERROR) readBuffer ~= sockBuffer[0..i];

    //最初の改行文字の前後で分割
    auto r = readBuffer.findSplitAfter("\n");

    readBuffer = r[1];  //改行文字以降は次回も使う
    auto str = r[0].strip;
    if (str != "") logger.log("[Socket.recv] ", str);
    lastString = str;
    return str;
  };

  void send(string s) {
    logger.log("[Socket.send] ", s);
    socket.send(s ~"\n");
  };
};

immutable string strCaseCSA = q{
  case "connect":  //対局サーバ接続(CSAプロトコルでのshogi-serverへの接続)
    connectCSA();
    break;
};

immutable CSA_KOMA = [ " * ", " * ", "FU", "KY", "KE", "GI", "KA", "HI", "KI", "OU", "TO", "NY", "NK", "NG", "UM", "RY" ];
immutable USI_KOMA = [ "", "", "P", "L", "N", "S", "B", "R", "G", "K", "", "", "", "", "", "" ];

//"+7776FU"などの文字列を手に変換
Move csa2Move(Shogiban s, string te) {
  assert(te.length == 7);
  int f = (te[1] - '1') + 9 * (te[2] - '1');
  int t = (te[3] - '1') + 9 * (te[4] - '1');
  int koma = cast(int) countUntil(CSA_KOMA, te[5..7]);
  if (f == -10) {
    return Move((koma << 1) + ((te[0] == '+') ? 0U : 1U), t);
  } else {
    return Move(f, t, koma != (s._masu[f] >> 1));
  }
}

string csa2usi(Shogiban s, string te) {
  assert(te.length == 7);
  int koma = cast(int) countUntil(CSA_KOMA, te[5..7]);
  bool isDrop = (te[1..3] == "00");

  if (isDrop) {
    assert(koma < 10);
    //打ち(G*5b)
    return format("%s*%s%s", USI_KOMA[koma], te[3], lowercase[te[4] - '1']);
  } else {
    //成
    int f = (te[1] - '1') + 9 * (te[2] - '1');
    auto isPromote = koma != (s._masu[f] >> 1);
    return format("%s%s%s%s%s", te[1], lowercase[te[2] - '1'], te[3], lowercase[te[4] - '1'], isPromote ? "+" : "");
  }
}

string usi2csa(Shogiban s, string te) {
  if (te == "resign") return "%TORYO";

  string teban = (s._teban == Teban.SENTE) ? "+" : "-";
  bool isDrop = te[1] == '*';
  if (isDrop) {
    return format("%s00%s%s%s", teban, te[2], digits[te[3] - 'a' + 1], CSA_KOMA[cast(int) countUntil(USI_KOMA, te[0..1])]);
  } else {
    int f = (te[0] - '1') + 9 * (te[1] - 'a');
    auto isPromote = (te.length > 4) && (te[4] == '+');
    return format("%s%s%s%s%s%s", teban, te[0], digits[te[1] - 'a' + 1], te[2], digits[te[3] - 'a' + 1],
                  CSA_KOMA[(s._masu[f] >> 1) + (isPromote ? 8 : 0)]);
  }
}

void connectCSA() {
  // XXX とりあえずLesserkai
  auto engine = new USIEngine("./Lesserkai", new FileLogger(stdout));
  scope(exit) engine.send("quit");
  engine.send("usi");
  engine.wait("usiok");
  engine.send("setoption name USI_Ponder value true");
  engine.send("isready");
  engine.wait("readyok");
  engine.send("usinewgame");

  //
  //  接続
  //
  auto socket = new CSASocket("localhost", 4081, new FileLogger(stdout));

  //
  //  ログイン
  //
  {
    string username = randomStr(10);
    string password = randomStr(10);
    // socket.send("LOGIN " ~username ~" " ~password);
    socket.send("LOGIN " ~username ~" test-600-10F");
    while (!socket.readln.canFind("LOGIN")) sleep(1000.msecs);

    if (socket.lastString == "LOGIN:incorrect") return writeln("ログイン失敗");
    assert(socket.lastString == "LOGIN:" ~username ~" OK");
  }

  //
  //  対局条件待ち
  //
  while (socket.readln != "BEGIN Game_Summary") sleep(1000.msecs);

  //
  //  対局条件
  //
  Teban myTurn;
  long[Teban] remainTimes;
  long increment;
  auto ban = new Shogiban;
  while (socket.readln != "END Game_Summary") {
    auto s = socket.lastString;
    // if (s.canFind("Your_Turn")) teban = s[10];
    if (s.canFind("Your_Turn")) myTurn = s[10] == '+' ? Teban.SENTE : Teban.GOTE;
    // if (s.canFind("Max_Moves")) s[10.. $].to !int.writeln;
    //時間情報
    if (s.canFind("Total_Time")) {
      long totalTime = s[11.. $].to !int;
      remainTimes = [Teban.SENTE:totalTime, Teban.GOTE:totalTime];
    }
    // if (s.canFind("Byoyomi")) s[8.. $].to !int.writeln;
    if (s.canFind("Increment")) increment = s[10.. $].to !long;

    //局面情報
    // if (s.canFind("To_Move")) startTeban = s[8];
    if (s.canFind("BEGIN Position")) {
      while (socket.readln != "END Position") {
        //事前の指し手
      }
    }
  }

  //対局条件が想定したものでなかった場合、REJECTを送る
  //認識違いがあった場合、ここが人間が介入できる最後のチャンスのはず
  if (false) return socket.send("REJECT");

  //対局条件の合意
  socket.send("AGREE");

  string strMoves = "";
  string strLastMove = "";
  string strPonderMove = "";

  //対局
  while (!socket.readln.startsWith("#WIN", "#LOSE", "#CENSORED", "#CHUDAN")) {
    auto s = socket.lastString;
    if (s == "") {
      sleep(10.msecs);
      continue;
    }

    if (s.startsWith('+', '-', "START")) {
      //指し手が返ってきたなら盤面や残り時間を更新する
      if (s.startsWith('+', '-')) {
        //指し手
        auto lastMove = ban.csa2Move(s[0..7]);
        strLastMove = ban.csa2usi(s[0..7]);
        strMoves ~= " " ~strLastMove;

        //局面と残り時間の更新
        remainTimes[ban._teban] -= s[9.. $].to !int;
        ban.doMove(lastMove);
        remainTimes[ban._teban] += increment;

        ban.writeln;
      }
      writefln("残り時間: %d, 相手残り時間: %d", remainTimes[myTurn], remainTimes[cast(Teban)(~myTurn)]);

      //自分の手番なら思考開始
      if (ban._teban == myTurn) {
        //相手の手が予想手と一致しているか？
        if (strPonderMove != "" && strPonderMove == strLastMove) {
          //予想当たりのとき予想読みを続行する
          engine.send("ponderhit");
        } else {
          if (strPonderMove != "") {
            //予想外れのとき予想読みを止める
            engine.send("stop");
            engine.wait("bestmove");
          }
          //思考開始
          engine.send("position startpos" ~(strMoves == "" ? "" : (" moves" ~strMoves)));
          engine.send("go");
        }
        strPonderMove = "";  // XXX ここで確実にfalseにしておく

        // bestmoveが返るまで待つ
        auto strBestMove = engine.wait("bestmove");
        auto strs = strBestMove.split;

        strLastMove = cast(string) strs[1];
        socket.send(ban.usi2csa(strLastMove));

        //予想手があれば予想読み
        if (strs.length >= 4 && strs[2] == "ponder") {
          strPonderMove = cast(string) strs[3];
          engine.send("position startpos moves" ~strMoves ~" " ~strLastMove ~" " ~strPonderMove);
          engine.send("go ponder");
        }
      }
    }
  }

  //必要に応じて勝敗とかを記録する
  socket.lastString.writeln;
}
