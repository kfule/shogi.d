//指し手の生成
Move* genMovesYY(in Shogiban pos, Move* mlist) @nogc { return pos.genMovesBaseYY(mlist, ~pos._bbOccupyYY); }
Move* genCaptureYY(in Shogiban pos, Move* mlist) @nogc { return pos.genMovesBaseYY(mlist, pos._bbOccupyZZ); }
Move* genNoCaptureYY(in Shogiban pos, Move* mlist) @nogc { return pos.genMovesBaseYY(mlist, ~pos._bbOccupy); }
Move* genMovesBaseYY(bool generateKingMove = true)(in Shogiban pos, Move* mlist, Bitboard target) @nogc {
  import std.algorithm : startsWith;
  static assert("YY" == "B" || "YY" == "W");
  immutable int[2] idx = "YY" == "B" ? [ 0, 1 ] : [ 1, 0 ];
  immutable int[2] offset = "YY" == "B" ? [ 0, 17 ] : [ 17, 0 ];
  mixin(q{
    static if ("YYXX" == "BFU") {
      foreach (to; ((pos._bbYYXX.b[idx[0]] >> 9) & MASK_13.b[idx[0]] & target.b[idx[0]]).BitwiseRange !(ulong, offset[0]))
        *(mlist++) = Move(to + 9, to, true);
      foreach (to; ((pos._bbYYXX.b[idx[1]] >> 9) & MASK_49.b[idx[1]] & target.b[idx[1]]).BitwiseRange !(ulong, offset[1]))
        *(mlist++) = Move(to + 9, to, false);
    }
    static if ("YYXX" == "WFU") {
      foreach (to; ((pos._bbYYXX.b[idx[0]] << 9) & MASK_79.b[idx[0]] & target.b[idx[0]]).BitwiseRange !(ulong, offset[0]))
        *(mlist++) = Move(to - 9, to, true);
      foreach (to; ((pos._bbYYXX.b[idx[1]] << 9) & MASK_16.b[idx[1]] & target.b[idx[1]]).BitwiseRange !(ulong, offset[1]))
        *(mlist++) = Move(to - 9, to, false);
    }
    static if ("XX" == "KE") {
      //桂成(1-5)
      foreach (from; (pos._bbYYXX.b[idx[0]] & MASK_YYXXp.b[idx[0]]).BitwiseRange !(ulong, offset[0]))
        foreach (to; (target.b[idx[0]] & ATTACKS_YYXX[from].b[idx[0]]).BitwiseRange !(ulong, offset[0]))
          *(mlist++) = Move(from, to, true);
      //不成(桂馬のfromは5-9なので片面に収まる)
      foreach (from; (pos._bbYYXX.b[idx[1]] & MASK_YYXX.b[idx[1]]).BitwiseRange !(ulong, offset[1]))
        foreach (to; (target.b[idx[1]] & ATTACKS_YYXX[from].b[idx[1]]).BitwiseRange !(ulong, offset[1]))
          *(mlist++) = Move(from, to, false);
    }
    //銀成(1-4から1-4, fromにもtoにも制限をかける)
    static if ("XX" == "GI") {
      foreach (from; (pos._bbYYXX.b[idx[0]] & MASK_YYXXp.b[idx[0]]).BitwiseRange !(ulong, offset[0]))
        foreach (to; (target.b[idx[0]] & ATTACKS_YYXX[from].b[idx[0]] & MASK_YYXXp.b[idx[0]]).BitwiseRange !(ulong, offset[0]))
          *(mlist++) = Move(from, to, true);
    }
    //短い不成(XXX ここだけはインデックスなど直接指定)
    static if ("XX".startsWith("GI", "KI") || (generateKingMove && "XX" == "OU")) {
      foreach (from; (pos._bbYYXX.b[0] & MASK_16.b[0]).BitwiseRange !(ulong, 0))
        foreach (to; (target.b[0] & ATTACKS_YYXX[from].b[0]).BitwiseRange !(ulong, 0))
          *(mlist++) = Move(from, to, false);
      foreach (from; (pos._bbYYXX.b[1] & MASK_79.b[1]).BitwiseRange !(ulong, 17))
        foreach (to; (target.b[1] & ATTACKS_YYXX[from].b[1]).BitwiseRange !(ulong, 17))
          *(mlist++) = Move(from, to, false);
    }
    //飛び利き
    static if ("XX".startsWith("KY", "KA", "HI", "pKA", "pHI")) {
      // 1-3の(1-9)の成り
      foreach (from; (pos._bbYYXX.b[idx[0]] & MASK_PROMOTE_YY.b[idx[0]]).BitwiseRange !(ulong, offset[0])) {
        Bitboard atk = pos._bbOccupy.ATTACKS_YYXX(from);
        foreach (to; (MASK_PROMOTE_YY.b[idx[0]] & target.b[idx[0]] & atk.b[idx[0]]).BitwiseRange !(ulong, offset[0]))
          *(mlist++) = Move(from, to, ("XX" == "pKA" || "XX" == "pHI") ? false : true);
        //香車は後退できない
        static if ("XX" != "KY") {
          foreach (to; (~MASK_PROMOTE_YY.b[idx[1]] & target.b[idx[1]] & atk.b[idx[1]]).BitwiseRange !(ulong, offset[1]))
            *(mlist++) = Move(from, to, ("XX" == "pKA" || "XX" == "pHI") ? false : true);
        }
      }
      // 4-9で1-3の成, 4-9の不成(香車は３段目の不成も)
      foreach (from; (pos._bbYYXX.b[idx[1]] & ~MASK_PROMOTE_YY.b[idx[1]]).BitwiseRange !(ulong, offset[1])) {
        Bitboard atk = pos._bbOccupy.ATTACKS_YYXX(from);
        foreach (to; (MASK_PROMOTE_YY.b[idx[0]] & target.b[idx[0]] & atk.b[idx[0]]).BitwiseRange !(ulong, offset[0]))
          *(mlist++) = Move(from, to, ("XX" == "pKA" || "XX" == "pHI") ? false : true);
        foreach (to; (MASK_YYXX.b[idx[1]] & target.b[idx[1]] & atk.b[idx[1]]).BitwiseRange !(ulong, offset[1]))
          *(mlist++) = Move(from, to, false);
      }
    }
  }.generateReplace("XX", KOMA_BB));
  return mlist;
}

//打ち手生成
Move* genDropsYY(in Shogiban pos, Move* mlist) @nogc { return (!pos._mochigomaYY) ? mlist : genDropsBaseYY(pos, mlist, ~pos._bbOccupy); }
Move* genDropsBaseYY(in Shogiban pos, Move* mlist, Bitboard target) @nogc {
  import std.algorithm : startsWith;
  static assert("YY" == "B" || "YY" == "W");
  target.b[1] &= 0xFFFF800000000000UL;  //冗長部分を取り除く
  mixin(q{
    if (pos._mochigomaYY.numXX) {
      static if ("XX" == "FU") {
        ulong b2FU = pos._bbYYFU.b[0] | (pos._bbYYFU.b[1] >> 1);
        foreach (i;[4, 2, 1]) { b2FU |= (b2FU << (9 * i)) | (b2FU >> (9 * i)); }
        foreach (to; (target.b[0] & MASK_LEGAL_YYFU.b[0] & ~b2FU).BitwiseRange !ulong)
          *(mlist++) = Move(komaType.YYXX, to);
        foreach (to; (target.b[1] & MASK_LEGAL_YYFU.b[1] & ~(b2FU << 1)).BitwiseRange !(ulong, 17))
          *(mlist++) = Move(komaType.YYXX, to);
      }
      static if ("XX".startsWith("KY", "KE")) {
        foreach (to; (target.b[0] & MASK_LEGAL_YYXX.b[0]).BitwiseRange !ulong) { *(mlist++) = Move(komaType.YYXX, to); }
        foreach (to; (target.b[1] & MASK_LEGAL_YYXX.b[1]).BitwiseRange !(ulong, 17)) { *(mlist++) = Move(komaType.YYXX, to); }
      }
      static if ("XX".startsWith("GI", "KI", "KA", "HI")) {
        foreach (to; target.b[0].BitwiseRange !ulong) { *(mlist++) = Move(komaType.YYXX, to); }
        foreach (to; target.b[1].BitwiseRange !(ulong, 17)) { *(mlist++) = Move(komaType.YYXX, to); }
      }
    }
  }.generateReplace("XX", [ "FU", "KY", "KE", "GI", "KI", "KA", "HI" ]));
  return mlist;
}
