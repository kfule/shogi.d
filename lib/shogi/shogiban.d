module shogi.shogiban;

import shogi.constants, shogi.bitboard, shogi.move;

class Shogiban {
  //--------------------------------------------------------
  //  盤面表現
  //--------------------------------------------------------
  //各駒の有る位置を表す(指し手生成に利用)
  mixin("Bitboard _bbYYXX;".generateReplace("XX", KOMA_BB).generateReplace("YY", [ "B", "W" ]));
  //成金については金のビットボードに集約する
  mixin("alias _bbYYXX=_bbYYKI;".generateReplace("XX", [ "pFU", "pKY", "pKE", "pGI" ]).generateReplace("YY", [ "B", "W" ]));

  //駒の有る位置を表す(取る手生成、打つ手生成、飛び利きの計算に利用)
  Bitboard _bbOccupyB, _bbOccupyW, _bbOccupy;

  byte[81] _masu;   //マスごとの駒(取る手の更新に使用)
  Teban _teban;     //手番
  Hash _boardHash;  //盤面ハッシュ(持ち駒のハッシュ値は含まない)

  //持ち駒
  Mochigoma _mochigomaB = Mochigoma(0), _mochigomaW = Mochigoma(1);

  //--------------------------------------------------------
  //  構造体定義
  //--------------------------------------------------------
  //盤面ハッシュ
  struct Hash {
    ulong _key;
    alias _key this;

    void update(in uint to, in uint koma) @nogc { _key ^= _zobrist[koma - 4][to]; }

    //乱数テーブル
    static immutable ulong[81][28] _zobrist = {
      import std.random;
      ulong[81][28] z;
      auto gen = Random(77);
      foreach (koma_i; 4..32)
        foreach (square_i; 0..81) { z[koma_i - 4][square_i] = uniform(ulong.min, ulong.max, gen) << 1; }
      return z;
    }();
  };

  //持ち駒
  struct Mochigoma {
    uint _a;
    alias _a this;
    void init(int i) { _a = i; }
    //そのままでもハッシュキーとして使えるように桁数の多い歩の数を上位のビットに
    //そのままでも優劣比較ができるように1bitずつ空ける
    enum idx { FU, KY, KE, GI, KI, KA, HI, OU };
    static immutable int[9] shift = [ 23, 19, 15, 11, 7, 4, 1, 29, 0 ];
    static immutable int[9] mask = [ 31, 7, 7, 7, 7, 3, 3, 3, 0 ];
    mixin(q{
      void addYYXX() @nogc { _a += 1 << shift[idx.XX]; }
      void remYYXX() @nogc { _a -= 1 << shift[idx.XX]; }
      uint numYYXX() @nogc const { return (_a >> shift[idx.XX]) & mask[idx.XX]; }
    }.generateReplace("YY", [ "", "p" ])
              .generateReplace("XX", [ "FU", "KY", "KE", "GI", "KI", "KA", "HI", "OU" ]));
    uint num(in uint i) const { return (_a >> shift[i]) & mask[i]; }
    wstring toString(in uint i, in uint w) const {
      import std.conv, std.format;
      immutable wstring strKoma = "歩香桂銀金角飛玉　　";
      return num(i) ? format(" %s%s%2d %s", w ? "\x1b[31m" : "", strKoma[i], num(i), w ? "\x1b[39m" : "").to !wstring : "      ";
    }
  };

  //-------------------------------------------------------
  //  初期化とか局面のセットとか
  //-------------------------------------------------------

  // SFENの読み込み
  this(in string sfen = "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1") {
    import std.range : split, front, retro;
    import std.algorithm : countUntil, map, reverse, joiner;
    import std.ascii : isDigit;
    immutable PieceToChar = "PpLlNnSsBbRrGgKk";

    //盤面、手番、持ち駒、手数の文字列に分割
    auto list = sfen.split;

    //盤面
    int idx = -1;
    int sq = 0;
    foreach (token; list[0].split('/').map !retro.joiner) {
      if (token.isDigit)
        sq += token - '0';  // sqを進める
      else if (token == '+')
        _masu[sq - 1] += 16;  //直前のsqの駒を成にする
      else if ((idx = cast(int)(PieceToChar.countUntil(token))) != -1)
        setKomaToBoard(komaType.BFU + idx, sq++);
    }

    //手番
    _teban = (list[1].front == 'b' ? Teban.SENTE : Teban.GOTE);

    //持ち駒
    uint num = 1;  //数の指定が無ければ持ち駒は1枚
    uint beforeNum = 0;
    foreach (token; list[2]) {
      if (token.isDigit) {
        num = token - '0' + beforeNum;
        beforeNum = num * 10;
      } else if ((idx = cast(int)(PieceToChar.countUntil(token))) != -1) {
        foreach (_; 0..num) { setKomaToHand(komaType.BFU + idx); }
        num = 1;
        beforeNum = 0;
      }
    }
    // TODO 手数を考慮する必要があるケースがあるかも(256手で引き分けとか)
  }

  //駒の設置。初期化や盤面読み込み用
  void setKomaToBoard(in uint kt, in uint sq) {
    assert(sq < 81);
    assert(kt < 32);
    final switch (cast(komaType) kt) {
      mixin(q{
        case komaType.YYXX:
          _bbOccupy |= _bbOccupyYY |= _bbYYXX |= MASK_SQ[sq];
          _masu[sq] = komaType.YYXX;
          _boardHash.update(sq, komaType.YYXX);
          break;
      }.generateReplace("YY", [ "B", "W" ])
                .generateReplace("XX", KOMA));
      case komaType.none:
        break;
    }
  }
  void setKomaToHand(in uint kt) {
    import std.algorithm : startsWith;
    assert(kt < 20);
    final switch (cast(komaType) kt) {
      mixin(q{
        case komaType.YYXX:
          static if ("XX".startsWith("FU", "KY", "KE", "GI", "KA", "HI", "KI")) {
            _mochigomaYY.addXX;
            break;
          }
          assert(false);
      }.generateReplace("YY", [ "B", "W" ])
                .generateReplace("XX", KOMA));
      case komaType.none:
        break;
    }
  }

  override string toString() const {
    import std.conv, std.format, std.range;
    immutable wstring strKoma = "・Ｘ歩香桂銀角飛金玉と杏圭全馬竜";
    auto app = appender !wstring;
    app.put(format("%s手番\n", "先後"w[_teban & 1]));
    app.put("      ９８７６５４３２１\n");
    foreach (i; 0..9) {
      app.put(_mochigomaW.toString(i, 1));
      foreach (j; 0..9) {
        uint k = _masu[i * 9 + 8 - j];
        app.put(format("%s%s%s", (k & 1) ? "\x1b[31m" : "", strKoma[k >> 1], (k & 1) ? "\x1b[39m" : ""));
      }
      app.put(format("%s%s\n", "一二三四五六七八九"w[i], _mochigomaB.toString(8 - i, 0)));
    }
    app.put(format("\nHashkey(Board): %016x", _boardHash));
    app.put(format("\nHashkey(HandB): %016x", _mochigomaB._a));
    app.put(format("\nHashkey(HandW): %016x", _mochigomaW._a));
    return app.data.to !string;
  }

  //盤面更新の展開
  mixin(import("_domove.d").generateReplace("ACT", [ "do", "undo" ]));
}

//手生成の展開
mixin(import("_movegen.d").generateReplace("YY", "ZZ", [ "B", "W" ]));
