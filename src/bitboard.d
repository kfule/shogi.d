/**
 * ビットボード関連
 */
import std.algorithm, std.compiler, std.conv, std.format, std.range, std.string, core.simd;
version(LDC) {
  import ldc.gccbuiltins_x86, ldc.intrinsics;
  uint bsf(T)(in T src) { return cast(uint) llvm_cttz(src, true); }
  uint popCnt(T)(in T x) { return cast(uint) llvm_ctpop(x); }
}
version(DigitalMars) {
  import core.bitop;
  alias popCnt = _popcnt;  //これだとpopcnt命令を使っててもインライン展開はされないかも
}

// target文字列をlistの各文字列で置換した文字列を返す
string generateReplace(string qs, string target, in string[] list) { return list.map !(a => qs.replace(target, a)).join; }
string generateReplace(string qs, string target1, string target2, in string[2] list) {
  return list.array.permutations.map !(a => qs.replace(target1, a[0]).replace(target2, a[1])).join;
}
unittest {
  assert("TestXX".generateReplace("XX", [ "aaa", "bbb", "ccc" ]) == "TestaaaTestbbbTestccc");
  assert("TestYYZZ".generateReplace("YY", "ZZ", [ "B", "W" ]) == "TestBWTestWB");
}

//ビットボードの片面でforeachを使うためのおまじない
struct BitwiseRange(T, uint offset = 0) {
  T a;
  this(T b) { a = b; }
  bool empty() @property { return !cast(bool)a; }
  uint front() @property { return bsf(a) + offset; }
  void popFront() { a &= a - 1; }
}

///ビットボード
struct Bitboard {
  union {
    ulong[2] b;  //コンパイル時変数の初期化周りのバグの回避のためにulong[2]を先に定義している
    ulong2 a;
  };

  ///コンストラクタ
  this(in Bitboard bb) @nogc { this = bb; }
  /// ditto
  this(in ulong2 b) @nogc { a = b; }
  /// ditto
  this(in ulong b0, in ulong b1) @nogc { b = [ b0, b1 ]; }
  /// ditto
  this(in string str) {
    //アンダースコアは含めて良い, またassertでちょうど81かどうかコンパイル時にも確認可能
    assert(str.replace("_", "").length == 81);
    (s => (s = s.replace("_", "")[17..81]).formattedRead("%b", &b[0]))(str.dup);
    (s => (s = s.replace("_", "")[0_..64]).formattedRead("%b", &b[1]))(str.dup);
  }

  //演算子
  Bitboard opBinary(string op)(in Bitboard bb) @nogc const { return mixin("Bitboard(a" ~op ~"bb.a)"); }
  Bitboard opUnary(string op)() @nogc const if (op == "~") { return Bitboard(~a); }
  ref Bitboard opOpAssign(string op)(in Bitboard bb) @nogc if (op != "=") { return this = opBinary !op(bb); }
  bool opCast(T)() const if (is(T == bool)&&vendor == Vendor.llvm) { return !__builtin_ia32_ptestz128(a, a); }
  bool opCast(T)() const if (is(T == bool)&&vendor != Vendor.llvm) { return cast(bool)(b[0] | b[1]); }
  Bitboard opBin(string op)(in Bitboard bb) @nogc const { return mixin("Bitboard(b[0]" ~op ~"bb.b[0],b[1]" ~op ~"bb.b[1])"); }
  Bitboard opBin(string op)(in int i) @nogc const { return mixin("Bitboard(b[0]" ~op ~"i,b[1]" ~op ~"i)"); }

  ///ビット数を数える
  uint popCnt() @nogc const { return.popCnt(b[0]) +.popCnt(b[1] & ~0x7FFFFFFFFFFFUL); }

  /// 最小位ビットを返す
  uint lsb() @nogc const { return b[0] ? b[0].bsf() : (b[1].bsf() + 17); }

  string toString() const {
    string s;
    foreach (i; 0..9) {
      foreach_reverse(j; 0..10) { s ~= (j < 9) ? ((this & MASK_SQ[i * 9 + j]) ? "●" : "・") : "\n"; }
      foreach_reverse(j; 0..10) { s ~= (j < 9 && i * 9 + j < 64_) ? ((b[0] & MASK_SQ[i * 9 + j].b[0]) ? "●" : "・") : "  "; }
      foreach_reverse(j; 0..10) { s ~= (j < 9 && i * 9 + j >= 17) ? ((b[1] & MASK_SQ[i * 9 + j].b[1]) ? "●" : "・") : "  "; }
    }
    return s;
  }

  /// 飛車角の利き算出用ハッシュ値の計算
  auto computeHash(in Bitboard mask) @nogc const { return ((((b[0] & mask.b[0]) << 4) | (b[1] & mask.b[1])) * 0x102040810204081UL) >> 57; }
  mixin(q{
    Bitboard ATTACKS_XX(in uint sq) @nogc const { return _ATTACKS_XX[(sq << 7) | computeHash(_MASK_XX[sq])]; }
  }.generateReplace("XX", [ "BKY", "WKY", "1199", "9119", "RANK", "FILE" ]));
  Bitboard ATTACKS_HI(in uint sq) @nogc const { return ATTACKS_RANK(sq) | ATTACKS_FILE(sq); }
  Bitboard ATTACKS_KA(in uint sq) @nogc const { return ATTACKS_9119(sq) | ATTACKS_1199(sq); }
  Bitboard ATTACKS_pHI(in uint sq) @nogc const { return ATTACKS_HI(sq) | ATTACKS_OU[sq]; }
  Bitboard ATTACKS_pKA(in uint sq) @nogc const { return ATTACKS_KA(sq) | ATTACKS_OU[sq]; }
  mixin(q{ alias ATTACKS_YYXX = ATTACKS_XX; }.generateReplace("YY", [ "B", "W" ]).generateReplace("XX", [ "KA", "HI", "pKA", "pHI" ]));
}

//空っぽ
immutable NULLBITBOARD = Bitboard(0, 0);

//特定の段のマスク
immutable MASK_1 = Bitboard("000000000_000000000_000000000_000000000_000000000_000000000_000000000_000000000_111111111");
immutable MASK_2 = Bitboard("000000000_000000000_000000000_000000000_000000000_000000000_000000000_111111111_000000000");
immutable MASK_3 = Bitboard("000000000_000000000_000000000_000000000_000000000_000000000_111111111_000000000_000000000");
immutable MASK_4 = Bitboard("000000000_000000000_000000000_000000000_000000000_111111111_000000000_000000000_000000000");
immutable MASK_5 = Bitboard("000000000_000000000_000000000_000000000_111111111_000000000_000000000_000000000_000000000");
immutable MASK_6 = Bitboard("000000000_000000000_000000000_111111111_000000000_000000000_000000000_000000000_000000000");
immutable MASK_7 = Bitboard("000000000_000000000_111111111_000000000_000000000_000000000_000000000_000000000_000000000");
immutable MASK_8 = Bitboard("000000000_111111111_000000000_000000000_000000000_000000000_000000000_000000000_000000000");
immutable MASK_9 = Bitboard("111111111_000000000_000000000_000000000_000000000_000000000_000000000_000000000_000000000");

//特定の段から段までのマスク
immutable MASK_12 = Bitboard("000000000_000000000_000000000_000000000_000000000_000000000_000000000_111111111_111111111");
immutable MASK_13 = Bitboard("000000000_000000000_000000000_000000000_000000000_000000000_111111111_111111111_111111111");
immutable MASK_14 = Bitboard("000000000_000000000_000000000_000000000_000000000_111111111_111111111_111111111_111111111");
immutable MASK_15 = Bitboard("000000000_000000000_000000000_000000000_111111111_111111111_111111111_111111111_111111111");
immutable MASK_16 = Bitboard("000000000_000000000_000000000_111111111_111111111_111111111_111111111_111111111_111111111");
immutable MASK_17 = Bitboard("000000000_000000000_111111111_111111111_111111111_111111111_111111111_111111111_111111111");
immutable MASK_18 = Bitboard("000000000_111111111_111111111_111111111_111111111_111111111_111111111_111111111_111111111");
immutable MASK_19 = Bitboard("111111111_111111111_111111111_111111111_111111111_111111111_111111111_111111111_111111111");
immutable MASK_29 = Bitboard("111111111_111111111_111111111_111111111_111111111_111111111_111111111_111111111_000000000");
immutable MASK_39 = Bitboard("111111111_111111111_111111111_111111111_111111111_111111111_111111111_000000000_000000000");
immutable MASK_49 = Bitboard("111111111_111111111_111111111_111111111_111111111_111111111_000000000_000000000_000000000");
immutable MASK_59 = Bitboard("111111111_111111111_111111111_111111111_111111111_000000000_000000000_000000000_000000000");
immutable MASK_69 = Bitboard("111111111_111111111_111111111_111111111_000000000_000000000_000000000_000000000_000000000");
immutable MASK_79 = Bitboard("111111111_111111111_111111111_000000000_000000000_000000000_000000000_000000000_000000000");
immutable MASK_89 = Bitboard("111111111_111111111_000000000_000000000_000000000_000000000_000000000_000000000_000000000");

//着手禁止点を除いた移動先
alias MASK_LEGAL_BFU = MASK_29;
alias MASK_LEGAL_BKY = MASK_29;
alias MASK_LEGAL_BKE = MASK_39;
alias MASK_LEGAL_WFU = MASK_18;
alias MASK_LEGAL_WKY = MASK_18;
alias MASK_LEGAL_WKE = MASK_17;

alias MASK_PROMOTE_B = MASK_13;
alias MASK_PROMOTE_W = MASK_79;

alias MASK_BKEp = MASK_15;  //桂馬が成れる移動元
alias MASK_WKEp = MASK_59;
alias MASK_BKE = MASK_59;  //桂馬の不成の移動元
alias MASK_WKE = MASK_15;
alias MASK_BGIp = MASK_14;  //銀が成れる移動元/移動先
alias MASK_WGIp = MASK_69;
alias MASK_BKY = MASK_39;  //香車の不成の移動先
alias MASK_WKY = MASK_17;
mixin(q{
  alias MASK_BXX = MASK_49;  //不成の移動先
  alias MASK_WXX = MASK_16;
}.generateReplace("XX", [ "KA", "HI", "pKA", "pHI" ]));

///駒の利きの展開
Bitboard[81] expand(in string str) { return expand(str, (i, j) => 9 * i + j, (i, j) => -j, ulong.max, ulong.max); }
Bitboard[81] expand(in string str, int delegate(int, int) dg1, int delegate(int, int) dg2, const ulong msk_b0, const ulong msk_b1) {
  // 左右にずらした時にビットが折り返されないようにするマスク
  Bitboard[17] _MASK_SHIFT;
  foreach (i; 0..17) { _MASK_SHIFT[i] = Bitboard(replicate("0000000011111111100000000"[16 - i..25 - i], 9)); }
  Bitboard* MASK_SHIFT = &_MASK_SHIFT[8];

  Bitboard[81] list;
  auto SIGNED_LEFT_SHIFT(in Bitboard a, in int shift) { return shift >= 0 ? a.opBin !"<<"(shift) : a.opBin !">>"(-shift); }
  // sq==40(５五)の形を基準に各マスの場合に展開していく
  foreach (i; - 4..5)
    foreach (j; - 4..5)
      list[40 + 9 * i + j] = SIGNED_LEFT_SHIFT(Bitboard(str), dg1(i, j)).opBin !"&"(MASK_SHIFT[dg2(i, j)]);

  //冗長な部分が一致するようにOR代入した上で, 非冗長化などのマスク処理を行う
  foreach (ref a; list) { a = a.opBin !"|"(Bitboard(a.b[1] << 17, a.b[0] >> 17)).opBin !"&"(Bitboard(msk_b0, msk_b1)); }

  return list;
}

immutable Bitboard[81] MASK_SQ = expand("000000000_000000000_000000000_000000000_000010000_000000000_000000000_000000000_000000000");
unittest {
  foreach (i; 0..81) { assert(MASK_SQ[i].popCnt == 1, "MASK_SQ[" ~i.text ~"]: 立っているビットは1つ"); }
  foreach (i; 0..81) { assert(MASK_SQ[i].lsb == i, "MASK_SQ[" ~i.text ~"]: 配列のindexとビットの位置は等しい"); }
  foreach (i; 0..81) { assert(MASK_SQ[i] == Bitboard((1UL << i) & ((i - 64L) >> 63), (1UL << (i - 17)) & ~((i - 17L) >> 63))); }
}

immutable Bitboard[81] _MASK_1199 = expand("100000000_010000000_001000000_000100000_000010000_000001000_000000100_000000010_000000001",
                                           (i, j) => -i + j, (i, j) => i - j, 0xFE7F3F9FC00UL, 0x3F9FCFE0000000UL);
immutable Bitboard[81] _MASK_9119 = expand("000000001_000000010_000000100_000001000_000010000_000100000_001000000_010000000_100000000",
                                           (i, j) => i + j, (i, j) => -i - j, 0xFE7F3F9FC00UL, 0x3F9FCFE0000000UL);
immutable Bitboard[81] _MASK_FILE = expand("000010000_000010000_000010000_000010000_000010000_000010000_000010000_000010000_000010000",
                                           (i, j) => j, (i, j) => 0, 0xFFFFFFE00UL, 0x7FFFFFFFF80000UL);
immutable Bitboard[81] _MASK_RANK = expand("000000000_000000000_000000000_000000000_111111111_000000000_000000000_000000000_000000000",
                                           (i, j) => 9 * i, (i, j) => 0, 0xFE7F3F9FCFEUL, 0x7F3F9FCFE0000000UL);
mixin(q{ alias _MASK_YYKY = _MASK_FILE; }.generateReplace("YY", [ "B", "W" ]));

//駒の利き
immutable Bitboard[81] ATTACKS_BFU = expand("000000000_000000000_000000000_000000000_000000000_000010000_000000000_000000000_000000000");
immutable Bitboard[81] ATTACKS_WFU = expand("000000000_000000000_000000000_000010000_000000000_000000000_000000000_000000000_000000000");
immutable Bitboard[81] ATTACKS_BKE = expand("000000000_000000000_000000000_000000000_000000000_000000000_000101000_000000000_000000000");
immutable Bitboard[81] ATTACKS_WKE = expand("000000000_000000000_000101000_000000000_000000000_000000000_000000000_000000000_000000000");
immutable Bitboard[81] ATTACKS_BGI = expand("000000000_000000000_000000000_000101000_000000000_000111000_000000000_000000000_000000000");
immutable Bitboard[81] ATTACKS_WGI = expand("000000000_000000000_000000000_000111000_000000000_000101000_000000000_000000000_000000000");
immutable Bitboard[81] ATTACKS_BKI = expand("000000000_000000000_000000000_000010000_000101000_000111000_000000000_000000000_000000000");
immutable Bitboard[81] ATTACKS_WKI = expand("000000000_000000000_000000000_000111000_000101000_000010000_000000000_000000000_000000000");
immutable Bitboard[81] ATTACKS_OU = expand("_000000000_000000000_000000000_000111000_000101000_000111000_000000000_000000000_000000000");
mixin(q{ alias ATTACKS_YYOU = ATTACKS_OU; }.generateReplace("YY", [ "B", "W" ]));

//成り駒の定数名は文字列mixinのためにpXXで統一する
mixin(q{ alias ATTACKS_YYpXX = ATTACKS_YYKI; }.generateReplace("XX", [ "FU", "KY", "KE", "GI" ]).generateReplace("YY", [ "B", "W" ]));

//飛び駒の利きリストを生成する
Bitboard[81 * 128] genLongTable(int delegate(int, int) getSq, int delegate(int) getPos, int delegate(int, int) choice, in Bitboard[] MASK) {
  Bitboard[81 * 128] list;

  // occupiedのパターンのとき、pos位置の駒の飛び利きパターンを返す
  int genAttacksLine(in int occupied, in int pos) {
    int a, b;  // 0
    for (int s = pos - 1; s >= 0 && !(a & occupied); s--) a |= 1 << s;
    for (int s = pos + 1; s < 9_ && !(b & occupied); s++) b |= 1 << s;
    return choice(a, b);  //香車以外は return a | b;
  }

  // lineのパターンのビットボードを返す
  Bitboard genBB(in uint line, in uint sq) {
    Bitboard bb = NULLBITBOARD;
    foreach (n; 0..9) {
      if (line & (1 << n)) {
        uint lineSq = getSq(sq, n);  // lineの位置を2次元に
        if (lineSq < 81) bb = bb.opBin !"|"(MASK_SQ[lineSq]);
      }
    }
    return bb;
  }

  //直線上に並ぶ駒の配置(2^7=128パターン)別で飛び利きを初期化
  foreach (occupied; 0..128) {
    foreach (sq; 0..81) {
      //駒の配置パターンをビットボードに落とし込みhashを算出
      int occupied_line = occupied << 1;
      ulong hash = (sq << 7) | genBB(occupied_line, sq).computeHash(MASK[sq]);

      //駒の配置に対する利きを生成
      list[hash] = genBB(genAttacksLine(occupied_line, getPos(sq)), sq);
    }
  }
  return list;
}

//各飛び駒の利きテーブル(インデックスは sq * 128 + pattern)
immutable Bitboard[81 * 128] _ATTACKS_BKY = genLongTable((sq, n) => n * 9 + sq % 9, sq => sq / 9, (a, b) => a, _MASK_FILE);
immutable Bitboard[81 * 128] _ATTACKS_WKY = genLongTable((sq, n) => n * 9 + sq % 9, sq => sq / 9, (a, b) => b, _MASK_FILE);
immutable Bitboard[81 * 128] _ATTACKS_1199 = genLongTable((sq, n) => sq - 10 * (sq % 9 - n), sq => sq % 9, (a, b) => a | b, _MASK_1199);
immutable Bitboard[81 * 128] _ATTACKS_9119 = genLongTable((sq, n) => sq + 8 * (sq % 9 - n), sq => sq % 9, (a, b) => a | b, _MASK_9119);
immutable Bitboard[81 * 128] _ATTACKS_FILE = genLongTable((sq, n) => n * 9 + sq % 9, sq => sq / 9, (a, b) => a | b, _MASK_FILE);
immutable Bitboard[81 * 128] _ATTACKS_RANK = genLongTable((sq, n) => sq / 9 * 9 + n, sq => sq % 9, (a, b) => a | b, _MASK_RANK);
