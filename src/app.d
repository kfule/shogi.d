import std.stdio, std.algorithm, std.array, std.conv, std.range, std.string;
import shogiban, testcode, move, usi2csa;

void main() {
  mixin(STR_INIT);

  //コマンド受付
  foreach (args; stdin.byLine.map !(a => a.chain(" (null)").to !string.strip.split))
    switch (args[0])
      mixin(STR_COMMAND);  //コマンドの展開
}

immutable string strInitMain = q{
  std.stdio.stdout.setvbuf(0,_IONBF);
  auto s = new Shogiban;
  s.writeln;
};

immutable string strCaseMain = q{
  case "init", "i":  //盤面の初期化
    s = new Shogiban;
    s.writeln;
    break;
  case "print", "p":  //盤面の表示
    s.writeln;
    break;
  case "quit", "q":  //終了
    return;
  case "help":  //ヘルプ(caseの表示)
  default:
    STR_COMMANDLIST.writeln;
    break;
};

//コンパイル時にファイル内を検索してコマンドっぽい文字列変数を収集して結合する
immutable string STR_COMMAND = mixin(import("releaseBinary.d").strip.split.filter !(a => a.startsWith("strCase")).join("~"));
immutable string STR_COMMANDLIST = STR_COMMAND.split("\n").map !strip.filter !(a => a.startsWith("case")).map !(a => a[5.. $]).join("\n");
// mainの最初に実行するコード断片
immutable string STR_INIT = mixin(import("releaseBinary.d").strip.split.filter !(a => a.startsWith("strInit")).join("~"));
