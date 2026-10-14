# henotoge

Swift (SpriteKit + SwiftUI) で作った縦4レーンの iOS 音ゲー。曲・譜面・コードはすべて AI 生成。

## 遊べるもの

- **FREE PLAY** … オリジナル15曲(30〜60秒)。難易度は BASIC / EXTREME と、一部の曲に INSANE。レベルは 1〜10。
- **段位認定** … 3曲メドレー × 5コース(初段・三段・五段・八段・皆伝)。
  コースごとに GREAT / GOOD / MISS の残り回数が決まっていて、0未満になった時点で不合格。
- **設定** … ハイスピード、タイミング調整、記録リセット。

判定は PERFECT ±40ms / GREAT ±80ms / GOOD ±120ms。スコアは1曲 1,000,000 点満点。

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
  Resources/  曲(m4a)と library.json  ← tools/generate.py で生成
tools/
  generate.py 曲・譜面・段位コースのジェネレーター
project.yml   XcodeGen の設定
```

曲や譜面、段位の条件を変えるときは `tools/generate.py` を直して実行する
(Python 3 + numpy + scipy + ffmpeg が必要)。

```
python3 tools/generate.py
```
