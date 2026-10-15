# henotoge

Swift (SpriteKit + SwiftUI) で作った横画面の太鼓スタイル音ゲー。曲・譜面・コードはすべて AI 生成。

## 遊べるもの

- **FREE PLAY** … 歌入りのオリジナル15曲(どれも30〜60秒、一部は少女ボイス)。くり返しのサビとドロップ前のスタッターで中毒性重視。難易度は BASIC / EXTREME と、一部の曲に INSANE。レベルは 1〜10。
  魂ゲージを最後に80%以上にできればクリア。
- **段位認定** … 3曲メドレー × 5コース(初段・三段・五段・八段・皆伝)。
  可(GOOD)と不可(MISS)の回数が、コースごとに決められた数「未満」なら合格。皆伝は連打の回数(以上)も条件。残りの回数は太鼓の左右にゲージで出る。
- **設定** … ハイスピード、タイミング調整、太鼓の音量、記録リセット。

音符: ドン(赤・面を叩く) / カッ(青・ふちを叩く) / 大音符 / 連打(黄) / 風船。

判定は 良 ±40ms / 可 ±100ms / 不可 (早すぎ ±120ms・見逃し・色ちがい)。スコアは1曲 1,000,000 点満点。

## ipa の入手

`main` に push すると GitHub Actions が未署名 ipa をビルドして、Releases の **latest** に置く。
iPhone に入れるときは Sideloadly や AltStore で自分の Apple ID で署名する(無料アカウントだと7日で切れる)。

## 構成

```
Henotoge/
  App/        アプリの入口
  Model/      曲データ・判定・記録・設定
  Game/       プレイ画面 (GameScene)
  UI/         SwiftUI の画面
  Resources/  曲(m4a)・叩く音(SE)・library.json  ← tools/generate.py で生成
tools/
  generate.py 曲・譜面・叩く音・段位コースのジェネレーター
project.yml   XcodeGen の設定
```

曲や譜面、段位の条件を変えるときは `tools/generate.py` を直して実行する
(Python 3 + numpy + scipy + ffmpeg と、歌声合成用の Open JTalk / WORLD のビルド一式が必要。tools/singer.py 参照)。

```
python3 tools/generate.py
```
