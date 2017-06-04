// Move doMove(Move m) / void undoMove(Move m)
// doMoveは盤面を戻す情報を含めた指し手を返す
// undoMoveはdoMoveから返された手を用いて指される前の盤面に戻す
auto ACTMove(Move m) @nogc {
  import std.algorithm : startsWith;
  static assert("ACT" == "do" || "ACT" == "undo");
  _teban = ~_teban;
  uint to = m.getTo;
  static if ("ACT" == "undo") _masu[to] = komaType.none;
  if (m.isDrop) {
    //打つ手
    final switch (cast(komaType) m.getDropPiece) {
      mixin(q{
        case komaType.YYXX:
          static if ("XX".startsWith("FU", "KY", "KE", "GI", "KA", "HI", "KI")) {
            static if ("ACT" == "do") _masu[to] = komaType.YYXX;
            static if ("ACT" == "do") _mochigomaYY.remXX;
            static if ("ACT" == "undo") _mochigomaYY.addXX;
            mixin(q{ BB ^= MASK_SQ[to]; }.generateReplace("BB", [ "_bbYYXX", "_bbOccupyYY", "_bbOccupy" ]));
            _boardHash.update(to, komaType.YYXX);
            break;
          }
          assert(false);
      }.generateReplace("YY", [ "B", "W" ])
                .generateReplace("XX", KOMA));
      case komaType.none:
        assert(false);
    }
  } else {
    //移動する手
    uint from = m.getFrom;
    static if ("ACT" == "do") m.setUndoInfo(_masu[from], _masu[to]);
    static if ("ACT" == "do") _masu[from] = komaType.none;

    //成りフラグを含めた駒別の処理
    final switch (cast(komaTypeWP) m.getMovePieceWithIsPromote) {
      mixin(q{
        case komaTypeWP.YYXX:
          static if ("ACT" == "do") _masu[to] = komaType.YYXX;
          static if ("ACT" == "undo") _masu[from] = komaType.YYXX;
          mixin(q{ BB ^= MASK_SQ[from] | MASK_SQ[to]; }.generateReplace("BB", [ "_bbYYXX", "_bbOccupyYY", "_bbOccupy" ]));
          _boardHash.update(from, komaType.YYXX);
          _boardHash.update(to, komaType.YYXX);
          break;
          //成り
          static if ("XX".startsWith("FU", "KY", "KE", "GI", "KA", "HI")) {
            case komaTypeWP.YYXXp:
              static if ("ACT" == "do") _masu[to] = komaType.YYpXX;
              static if ("ACT" == "undo") _masu[from] = komaType.YYXX;
              _bbYYXX ^= MASK_SQ[from];
              _bbYYpXX ^= MASK_SQ[to];
              mixin(q{ BB ^= MASK_SQ[from] | MASK_SQ[to]; }.generateReplace("BB", [ "_bbOccupyYY", "_bbOccupy" ]));
              _boardHash.update(from, komaType.YYXX);
              _boardHash.update(to, komaType.YYpXX);
              break;
          }
      }.generateReplace("YY", [ "B", "W" ])
                .generateReplace("XX", KOMA));
      case komaTypeWP.none:
        assert(false);
    }
  }
  final switch (cast(komaType) m.getCapture) {
    mixin(q{
      case komaType.YYXX:
        static if ("ACT" == "do") _mochigomaZZ.addXX;
        static if ("ACT" == "undo") _mochigomaZZ.remXX;
        static if ("ACT" == "undo") _masu[to] = komaType.YYXX;
        mixin(q{ BB ^= MASK_SQ[to]; }.generateReplace("BB", [ "_bbYYXX", "_bbOccupyYY", "_bbOccupy" ]));
        _boardHash.update(to, komaType.YYXX);
        break;
    }.generateReplace("YY", "ZZ", [ "B", "W" ])
              .generateReplace("XX", KOMA));
    case komaType.none:
      break;
  }
  static if ("ACT" == "do") return m;
}
