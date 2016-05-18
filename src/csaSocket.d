import std.socket, std.stdio, std.range, std.algorithm, std.ascii, std.random, std.conv, core.thread, std.string;

immutable string strCaseCSA = q{
  case "connect":  //対局サーバ接続(CSAプロトコルでのshogi-serverへの接続)
    // while (true) connectCSA();
    connectCSA();
    break;
};

//ランダムな英数字文字列を生成する
auto randomStr = (int len) { return iota(len).map !(_ => (letters ~digits)[uniform(0, $)]).array; };
//スリープ関数
alias sleep = core.thread.Thread.sleep;
// parseをメソッドチェインするためのらっぱー
T parser(T)(string s) { return s.parse !T; }

class CsaSocket {
  char[1024] buffer;
  string str;
  TcpSocket socket;

  this(string addr = "localhost", ushort port = 4081) {
    socket = new TcpSocket(new InternetAddress(addr, port));
    socket.blocking(false);
    //長時間通信がない場合にKeepAliveパケットを送るようにする
    try {
      socket.setKeepAlive(600, 60);
    } catch (SocketFeatureException e) {
      e.msg.writeln;
    }
  }

  string readln() {
    //受信して結合
    auto i = socket.receive(buffer);
    if (i != Socket.ERROR) str ~= buffer[0..i];

    //最初の改行文字の前後で分割
    auto r = str.findSplitAfter("\n");

    str = r[1];  //改行文字以降は次回も使う
    if (r[0] != "") r[0].rightJustifier(128).write;
    return r[0].strip;
  };

  void send(string s) {
    ("                           " ~s).writeln;
    socket.send(s ~"\n");
  };
};

immutable CSA_KOMA = [ " * ", " * ", "FU", "KY", "KE", "GI", "KA", "HI", "KI", "OU", "TO", "NY", "NK", "NG", "UM", "RY" ];

//"+7776FU"などの文字列を手に変換
Move csa2Move(Shogiban s, string te) {
  assert(te.length == 7);
  assert('0' <= te[1] && te[1] <= '9');
  assert('0' <= te[2] && te[2] <= '9');
  assert('0' <= te[3] && te[3] <= '9');
  assert('0' <= te[4] && te[4] <= '9');
  int f = (te[1] - '1') + 9 * (te[2] - '1');
  int t = (te[3] - '1') + 9 * (te[4] - '1');
  string k = te[5..7];
  if (f == -10) {
    return Move((cast(uint) countUntil(CSA_KOMA, k) << 1) + ((te[0] == '+') ? 0U : 1U), t);
  } else {
    return Move(f, t, countUntil(CSA_KOMA, k) != (s._masu[f] >> 1));
  }
}

void connectCSA() {
  auto ban = new Shogiban;
  Move[1024] mlistBase;

  string s;

  //接続
  auto socket = new CsaSocket;

  void sendBestMove(Move m) {
    //移動後の局面を参考にしているので注意(先後がいつもと逆)
    // string str = (ban._teban == Teban.SENTE) ? "+" : "-";
    ban.doMove(m);
    string str = (ban._masu[m.getTo] & 1) ? "-" : "+";
    str ~= m.isDrop ? "00" : (text(m.getFrom % 9 + 1) ~text(m.getFrom / 9 + 1));
    str ~= text(m.getTo % 9 + 1) ~text(m.getTo / 9 + 1) ~CSA_KOMA[ban._masu[m.getTo] >> 1];
    socket.send(str);
  }

  //
  //  ログイン
  //
  string username = randomStr(10);
  string password = randomStr(10);
  socket.send("LOGIN " ~username ~" " ~password);
  while (!(s = socket.readln).canFind("LOGIN")) sleep(100.msecs);

  if (s == "LOGIN:incorrect") return "ログイン失敗".writeln;
  assert(s == "LOGIN:" ~username ~" OK");

  //
  //  対局条件待ち
  //
  while (socket.readln != "BEGIN Game_Summary") sleep(100.msecs);

  //
  //  対局条件
  //
  char teban, startTeban;
  long totalTime;
  long increment;
  while ((s = socket.readln) != "END Game_Summary") {
    if (s.canFind("Your_Turn")) teban = s[10];
    if (s.canFind("To_Move")) startTeban = s[8];
    // if (s.canFind("Max_Moves")) s[10.. $].parser !int.writeln;
    if (s.canFind("Total_Time")) totalTime = s[11.. $].parser !int;
    // if (s.canFind("Byoyomi")) s[8.. $].parser !int.writeln;
    if (s.canFind("Increment")) increment = s[10.. $].parser !long;
    if (s.canFind("BEGIN Position")) {
      //局面情報
      while ((s = socket.readln) != "END Position") {
        //事前の指し手
      }
    }
  }

  //対局条件が想定したものでなかった場合、REJECTを送る
  //認識違いがあった場合、ここが人間が介入できる最後のチャンスのはず
  if (false) return socket.send("REJECT");

  char aite = teban == '+' ? '-' : '+';
  long remainTime = totalTime;
  long opponentRemainTime = totalTime;
  Move bestMove, lastMove, ponderMove;
  bool isPondering;

  //対局条件の合意
  socket.send("AGREE");

  // TODO とりあえずランダムに手を選ぶ
  Move startThinkingXXX() {
    if (s[0] == '+' || (s.startsWith("START") && '-' == startTeban)) {
      auto ml = mlistBase[0..ban.genDropsW(ban.genMovesW(mlistBase.ptr)) - mlistBase.ptr];
      return  ml[uniform(0, $)];
    }
    if (s[0] == '-' || (s.startsWith("START") && '+' == startTeban)) {
      auto ml = mlistBase[0..ban.genDropsB(ban.genMovesB(mlistBase.ptr)) - mlistBase.ptr];
      return ml[uniform(0, $)];
    }
    return Move.NONE;
  }

  //対局
  while (!(s = socket.readln).startsWith("#WIN", "#LOSE", "#CENSORED", "#CHUDAN")) {
    sleep(10.msecs);

    //初手が自分の手番ならすぐに思考開始
    if (s.startsWith("START") && teban == startTeban) goto StartThinking;

    //自分の手が返ってきた場合、消費時間を調整
    if (s.startsWith(teban)) {
      remainTime -= s[9.. $].parser !int;
      opponentRemainTime += increment;
      writefln("残り時間: %d, 相手残り時間: %d", remainTime, opponentRemainTime);
    }

    //相手の手がきた場合、盤面を更新し思考開始
    if (s.startsWith(aite)) {
      opponentRemainTime -= s[9.. $].parser !int;
      remainTime += increment;
      writefln("残り時間: %d, 相手残り時間: %d", remainTime, opponentRemainTime);

      // TODO 時間計測開始

      lastMove = ban.csa2Move(s[0..7]);

      //相手の手が予想手と一致しているか？
      if (isPondering && lastMove == ponderMove) {
        //予想当たり->waitForThinkFinishedまで進める
      } else {
        //予想外れ->undo
        if (isPondering) ban.undoMove(ponderMove);
        //予想外れ or 予想していないケース
        ban.doMove(lastMove);

      StartThinking:
        bestMove = startThinkingXXX();
      }
      isPondering = false;  // XXX ここで確実にfalseにしておく

      // waitForThinkFinished;
      sendBestMove(bestMove);
      ban.writeln;

      //予想手があれば探索
      /*
      if (pv.length > 1 && pv[1] != Move.NONE) {
        isPondering = true;
        ponderMove = pos.doMove(pv[1]);
        // startThinking;
      }
      */
    }
  }

  //必要に応じて勝敗とかを記録する
  s.writeln;
}

