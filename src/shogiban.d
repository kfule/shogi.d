import std.array;
import std.range;
import std.algorithm;
import std.ascii;
import std.conv;
import std.stdio;
import std.format;
import std.random;

import bitboard;
import move;

enum Teban { SENTE = 0, GOTE = -1 };

//文字列mixinで用いる駒文字列(成り駒は先頭にpをつける)
const string[14] KOMA = [ "FU", "KY", "KE", "GI", "KA", "HI", "KI", "OU", "pFU", "pKY", "pKE", "pGI", "pKA", "pHI" ];
//文字列mixinで用いる成金を除いた駒文字列
const string[10] KOMA_BB = [ "FU", "KY", "KE", "GI", "KA", "HI", "KI", "OU", "pKA", "pHI" ];

// target文字列をlistの各文字列で置換した文字列を返す
string generateReplace(string qs, string target, in string[] list) { return list.map !(a => qs.replace(target, a)).join; }
string generateReplace(string qs, string target1, string target2, in string[2] list) {
  return iota(2).map !(a => qs.replace(target1, list[a]).replace(target2, list[(a + 1) & 1])).join;
}
unittest {
  assert("TestXX".generateReplace("XX", [ "aaa", "bbb", "ccc" ]) == "TestaaaTestbbbTestccc");
  assert("TestYYZZ".generateReplace("YY", "ZZ", [ "B", "W" ]) == "TestBWTestWB");
}

// enum
mixin({
  string s;
  //駒の種類、先手の歩は4、後手は1を足す、成りは16を足す
  s ~= "enum komaType{";
  foreach (i, k; KOMA) {
    s ~= "B" ~k ~"=" ~text(2 * i + 4) ~",";
    s ~= "W" ~k ~"=" ~text(2 * i + 5) ~",";
  }
  s ~= "none=0};";

  //成りフラグつき駒の種類
  s ~= "enum komaTypeWP{";
  foreach (i, k; KOMA) {
    s ~= "B" ~k ~"=" ~text((2 * i + 4) << 1) ~",";
    s ~= "W" ~k ~"=" ~text((2 * i + 5) << 1) ~",";
    if (k.startsWith("FU", "KY", "KE", "GI", "KA", "HI")) {
      s ~= "B" ~k ~"p =" ~text(((2 * i + 4) << 1) + 1) ~",";
      s ~= "W" ~k ~"p =" ~text(((2 * i + 5) << 1) + 1) ~",";
    }
  }
  s ~= "none=0};";

  int[string] numMochi = ["FU":18, "KY":4, "KE":4, "GI":4, "KI":4, "KA":2, "HI":2, "OU":2];
  int[string] numSlide = ["FU":9, "KY":9, "KE":18, "GI":0, "KI":0, "KA":0, "HI":0, "OU":0, "pKA":0, "pHI":0];
  int idx;
  s ~= "enum IndexPP{";
  //持ち駒はゼロ枚目は使わない(のでidx-1)
  foreach (k;["FU", "KY", "KE", "GI", "KI", "KA", "HI", "OU"]) {
    s ~= "B_hand_" ~k ~"=" ~(idx - 1).text ~",\n";
    s ~= "W_hand_" ~k ~"=" ~(idx - 1 + numMochi[k]).text ~",\n";
    idx += 2 * (numMochi[k]);
  }
  s ~= "hand_end=" ~idx.text ~",";
  foreach (k;["FU", "KY", "KE", "GI", "KI", "KA", "HI", "OU", "pKA", "pHI"]) {
    s ~= "B_" ~k ~"=" ~(idx - numSlide[k]).text ~",\n";
    s ~= "W_" ~k ~"=" ~(idx - numSlide[k] + 81).text ~",\n";
    idx += 2 * (81 - numSlide[k]);
  }
  s ~= "end=" ~idx.text ~",";
  foreach (k;["FU", "KY", "KE", "GI"]) {
    s ~= "B_p" ~k ~"=B_KI,\n";
    s ~= "W_p" ~k ~"=W_KI,\n";
  }
  foreach (k;["FU", "KY", "KE", "GI", "KA", "HI"]) {
    s ~= "B_hand_p" ~k ~"=B_hand_" ~k ~",\n";
    s ~= "W_hand_p" ~k ~"=W_hand_" ~k ~",\n";
  }

  s ~= "}";
  return s;
}());

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

  ushort[40] _list40;
  byte[81 + IndexPP.hand_end] _listId;

  //--------------------------------------------------------
  //  構造体定義
  //--------------------------------------------------------
  //盤面ハッシュ
  struct Hash {
    ulong _key;
    alias _key this;

    void update(in uint to, in uint koma) @nogc { _key ^= _zobrist[koma - 4][to]; }

    //乱数テーブル
    static immutable ulong[81][28] _zobrist = initZobrist();  //コンパイル時に初期化される
    static ulong[81][28] initZobrist() {
      ulong[81][28] z;
      auto gen = Random(77);
      foreach (koma_i; 4..32)
        foreach (square_i; 0..81) { z[koma_i - 4][square_i] = uniform(ulong.min, ulong.max, gen) << 1; }
      return z;
    }
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
      bool isYYXX() @nogc const { return cast(bool)(_a & (mask[idx.XX] << shift[idx.XX])); }
    }.generateReplace("YY", [ "", "p" ])
              .generateReplace("XX", [ "FU", "KY", "KE", "GI", "KI", "KA", "HI", "OU" ]));
    uint num(in uint i) const { return (_a >> shift[i]) & mask[i]; }
    wstring toString(in uint i, in uint w) const {
      immutable wstring strKoma = "歩香桂銀金角飛玉　　";
      return num(i) ? format(" %s%s%2d %s", w ? "\x1b[31m" : "", strKoma[i], num(i), w ? "\x1b[39m" : "").to !wstring : "      ";
    }
  };

  //-------------------------------------------------------
  //  初期化とか局面のセットとか
  //-------------------------------------------------------

  void init() { setSFEN("lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1"); }

  void setZero() {
    _boardHash = 0;
    _teban = Teban.SENTE;
    _mochigomaB.init(0);
    _mochigomaW.init(1);

    _bbOccupy = _bbOccupyB = _bbOccupyW = NULLBITBOARD;
    mixin("_bbYYXX = NULLBITBOARD;".generateReplace("XX", KOMA_BB).generateReplace("YY", [ "B", "W" ]));
    _masu[] = komaType.none;
    _listId[] = -1;
  }

  // SFENの読み込み
  void setSFEN(string sfen) {
    setZero();
    immutable string PieceToChar = "____PpLlNnSsBbRrGgKk";
    ubyte id;

    //盤面、手番、持ち駒、手数の文字列に分割
    auto list = sfen.split;

    //盤面
    int idx = -1;
    int sq = 8;       //一段目、９筋からスタート
    int promote = 0;  //成り駒のときは16を足す
    foreach (token; list[0]) {
      if (token.isDigit)
        sq -= token - '0';
      else if (token == '/')
        sq += 18;
      else if (token == '+')
        promote = 16;
      else if ((idx = cast(int)(PieceToChar.countUntil(token))) != -1) {
        _list40[id] = cast(short)setKoma(sq, idx + promote);
        _listId[sq] = id++;
        promote = 0;
        sq--;
      }
    }

    //手番
    _teban = (list[1].front == 'b' ? Teban.SENTE : Teban.GOTE);

    //持ち駒
    uint num = 1;  //数の指定が無ければ持ち駒は1枚
    uint beforeNum = 0;
    foreach (token; list[2]) {
      if (token == '-') break;
      if (token.isDigit) {
        num = token - '0' + beforeNum;
        beforeNum = num * 10;
      } else if ((idx = cast(int)(PieceToChar.countUntil(token))) != -1) {
        foreach (i; 0..num) {
          _list40[id] = cast(short)setKoma(81, idx);
          _listId[_list40[id] + 81] = id++;
        }
        num = 1;
        beforeNum = 0;
      }
    }
    // TODO 手数を考慮する必要があるケースがあるかも(256手で引き分けとか)
  }

  //駒の設置。初期化や盤面読み込み用
  uint setKoma(in uint sq, in uint kt) {
    assert(sq <= 81);
    if (sq == 81) {
      assert(kt < 20);
      //持ち駒への配置
      final switch (cast(komaType) kt) {
        mixin(q{
          case komaType.YYXX:
            static if ("XX".startsWith("FU", "KY", "KE", "GI", "KA", "HI", "KI")) {
              _mochigomaYY.addXX;
              return IndexPP.YY_hand_XX + _mochigomaYY.numXX;
            }
            assert(false);
        }.generateReplace("YY", [ "B", "W" ])
                  .generateReplace("XX", KOMA));
        case komaType.none:
          assert(false);
      }
    } else {
      //盤面への配置
      assert(kt < 32);
      final switch (cast(komaType) kt) {
        mixin(q{
          case komaType.YYXX:
            _bbOccupy |= _bbOccupyYY |= _bbYYXX |= MASK_SQ[sq];
            _masu[sq] = komaType.YYXX;
            _boardHash.update(sq, komaType.YYXX);
            return IndexPP.YY_XX + sq;
        }.generateReplace("YY", [ "B", "W" ])
                  .generateReplace("XX", KOMA));
        case komaType.none:
          assert(false);
      }
    }
  }

  override string toString() const {
    immutable wstring turn = "先後";
    immutable wstring strX = "１２３４５６７８９";
    immutable wstring strY = "一二三四五六七八九";
    immutable wstring strKoma = "・Ｘ歩香桂銀角飛金玉と杏圭全馬竜";

    wstring str;
    str ~= turn[_teban & 1];
    str ~= "手番";
    str ~= "\n      ";
    foreach (j; 0..9) { str ~= strX[8 - j]; }
    str ~= "\n";
    foreach (i; 0..9) {
      str ~= _mochigomaW.toString(i, 1);
      foreach (j; 0..9) {
        uint k = _masu[i * 9 + 8 - j];
        if (k & 1) str ~= "\x1b[31m";  //後手の駒は色を変える
        str ~= strKoma[k >> 1];
        if (k & 1) str ~= "\x1b[39m";  //色を戻す
      }
      str ~= strY[i];
      str ~= _mochigomaB.toString(8 - i, 0);
      str ~= "\n";
    }
    str ~= format("\nHashkey(Board): %016x", _boardHash).to !wstring;
    str ~= format("\nHashkey(HandB): %016x", _mochigomaB._a).to !wstring;
    str ~= format("\nHashkey(HandW): %016x", _mochigomaW._a).to !wstring;
    // stringにして返す. もしかしたら文字化けするかも?
    return str.to !string;
  }

 private
  byte fetchId(in int from) @nogc {
    byte id = _listId[from];
    _listId[from] = -1;
    return id;
  }
 private
  void write40(in byte id, in int to, in int psq) @nogc {
    _list40[id] = cast(short)psq;
    _listId[to] = id;
  }

  //盤面更新の展開
  mixin(import("domove.dd").generateReplace("ACT", [ "do", "undo" ]));
}

//手生成の展開
mixin(import("movegen.dd").generateReplace("YY", "ZZ", [ "B", "W" ]));
