#!/usr/bin/env python3
"""
henotoge 曲・譜面ジェネレーター (太鼓スタイル)

ノリのいいオリジナル曲15曲をシンセで合成し、その曲のリズムから
太鼓型の譜面 (ドン / カッ / 大音符 / 連打 / 風船) と段位認定コースを作る。

出力:
  Henotoge/Resources/Songs/sXX.m4a
  Henotoge/Resources/SE/don.wav, ka.wav
  Henotoge/Resources/library.json

使い方:
  python3 tools/generate.py
"""

import json
import math
import os
import shutil
import subprocess
import sys
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import singer  # noqa: E402

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Henotoge", "Resources")
SONG_DIR = os.path.join(OUT_DIR, "Songs")
SE_DIR = os.path.join(OUT_DIR, "SE")

LEAD_IN = 2.0     # 曲頭の無音(秒)
TAIL = 1.6        # 最後の一撃のあとの余韻(秒)
MIN_SEC = 30.0
MAX_SEC = 60.0

# ------------------------------------------------------------
# 曲リスト
#   bars:  本編の小節数 (イントロ〜アウトロ)。曲の長さはここで決まる
#   style: matsuri / eurobeat / denpa / house / hardcore / dnb / trance
# ------------------------------------------------------------
SONGS = [
    dict(id="s01", title="お祭りドンドン", bpm=128, key=62, mode="major", style="matsuri", bars=20,
         levels={"BASIC": 1, "EXTREME": 4}),
    dict(id="s02", title="Sunny Pop Rush", bpm=134, key=65, mode="major", style="house", bars=21,
         levels={"BASIC": 2, "EXTREME": 5}),
    dict(id="s03", title="ぴょんぴょんパレード", bpm=140, key=67, mode="major", style="denpa", bars=22,
         levels={"BASIC": 2, "EXTREME": 5}),
    dict(id="s04", title="Neon Beat Parade", bpm=128, key=57, mode="minor", style="house", bars=22,
         levels={"BASIC": 2, "EXTREME": 6}),
    dict(id="s05", title="ねこまんまダンス", bpm=146, key=64, mode="major", style="eurobeat", bars=24,
         levels={"BASIC": 2, "EXTREME": 6}),
    dict(id="s06", title="Rocket Candy", bpm=150, key=62, mode="major", style="hardcore", bars=24,
         levels={"BASIC": 3, "EXTREME": 7}),
    dict(id="s07", title="夜祭ハイテンション", bpm=152, key=60, mode="minor", style="matsuri", bars=25,
         levels={"BASIC": 3, "EXTREME": 7}),
    dict(id="s08", title="Turbo Tanuki", bpm=158, key=63, mode="minor", style="eurobeat", bars=26,
         levels={"BASIC": 4, "EXTREME": 7}),
    dict(id="s09", title="雷神ブレイク", bpm=172, key=58, mode="minor", style="dnb", bars=28,
         levels={"BASIC": 4, "EXTREME": 8, "INSANE": 9}),
    dict(id="s10", title="Hyper Lantern", bpm=164, key=66, mode="major", style="trance", bars=28,
         levels={"BASIC": 4, "EXTREME": 8}),
    dict(id="s11", title="紅蓮ビートダッシュ", bpm=176, key=57, mode="minor", style="hardcore", bars=30,
         levels={"BASIC": 5, "EXTREME": 8}),
    dict(id="s12", title="Overdrive Festival", bpm=180, key=60, mode="major", style="denpa", bars=30,
         levels={"BASIC": 5, "EXTREME": 8, "INSANE": 9}),
    dict(id="s13", title="疾風怒濤ドラム", bpm=186, key=62, mode="minor", style="matsuri", bars=32,
         levels={"BASIC": 5, "EXTREME": 8, "INSANE": 10}),
    dict(id="s14", title="HENOTOGE MAX", bpm=192, key=61, mode="minor", style="hardcore", bars=34,
         levels={"BASIC": 6, "EXTREME": 9, "INSANE": 10}),
    # 持ち込み音源のアレンジ (皆伝3曲目)
    dict(id="s15", title="Catastrophe", bpm=150, source="tools/sources/catastrophe.ogg", phase=1.441, src_bars=34,
         sections=["intro"] * 3 + ["chorus"] * 8 + ["verse"] * 5 + ["build"] + ["chorus"] * 14 + ["build"]
         + ["chorus"] * 2 + ["outro"],
         crash_bars=[21, 27], stutter_bars=[32],
         levels={"BASIC": 6, "EXTREME": 9, "INSANE": 10}),
]

ARTIST = "henotoge sound team"

# ------------------------------------------------------------
# 段位認定 (3曲メドレー)
#   conditions: [赤合格, 金合格] の組で書く
#               GAUGE  魂ゲージ (3曲通し) がこの % 以上
#               GOOD / MISS  可・不可が それぞれ この回数「未満」
#               ROLL  曲ごとの連打数がこの回数「以上」 ("auto" は譜面から曲ごとに決める)
# ------------------------------------------------------------
COURSES = [
    dict(id="dan1", name="初段", stages=[("s01", "EXTREME"), ("s02", "EXTREME"), ("s03", "EXTREME")],
         conditions={"GAUGE": [70, 90], "GOOD": [60, 30], "MISS": [25, 10]}),
    dict(id="dan2", name="三段", stages=[("s04", "EXTREME"), ("s05", "EXTREME"), ("s06", "EXTREME")],
         conditions={"GAUGE": [75, 92], "GOOD": [50, 25], "MISS": [20, 8]}),
    dict(id="dan3", name="五段", stages=[("s07", "EXTREME"), ("s08", "EXTREME"), ("s10", "EXTREME")],
         conditions={"GAUGE": [80, 95], "GOOD": [40, 20], "MISS": [15, 6], "ROLL": "auto"}),
    dict(id="dan4", name="八段", stages=[("s11", "EXTREME"), ("s09", "INSANE"), ("s12", "INSANE")],
         conditions={"GAUGE": [90, 98], "GOOD": [30, 15], "MISS": [10, 4], "ROLL": "auto"}),
    dict(id="dan5", name="皆伝", stages=[("s13", "INSANE"), ("s14", "INSANE"), ("s15", "INSANE")],
         conditions={"GAUGE": [100, 100], "GOOD": [20, 10], "MISS": [5, 2], "ROLL": "auto"}),
]

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]
PENTA_MAJOR = [0, 2, 4, 7, 9]
PENTA_MINOR = [0, 3, 5, 7, 10]

# コード進行 (スケールの度数)。王道進行など、ノリやすいものを中心に
PROGRESSIONS = {
    "major": [[3, 4, 2, 5], [0, 4, 5, 3], [5, 3, 0, 4], [3, 4, 0, 0]],
    "minor": [[0, 5, 6, 0], [5, 6, 0, 0], [0, 6, 5, 6], [5, 3, 6, 0]],
}

# メロディのリズム (1小節16分割、x = 発音)
HOOK_RHYTHMS = [
    "x..x..x.x..x.x..",
    "x.x.x..x.x.x..x.",
    "x.xx.x.x.xx.x.x.",
    "x..x.x.xx..x.x.x",
    "xx.x.x.x..x.x...",
    "x.x..x.xx.x..x..",
    "x..xx.x.x..xx.x.",
]
VERSE_RHYTHMS = [
    "x...x.x.x...x...",
    "x..x..x...x.x...",
    "x.x...x.x.x.....",
    "x...x..xx...x...",
]


def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


# ------------------------------------------------------------
# 音を作る部品
# ------------------------------------------------------------
def lowpass(x, cutoff, order=2):
    sos = butter(order, min(cutoff, SR * 0.45), btype="low", fs=SR, output="sos")
    return sosfilt(sos, x)


def highpass(x, cutoff, order=2):
    sos = butter(order, cutoff, btype="high", fs=SR, output="sos")
    return sosfilt(sos, x)


def bandpass(x, lo, hi, order=2):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.05):
    t = np.arange(n) / SR
    dur = n / SR
    env = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = np.clip((dur - t) / max(r, 1e-4), 0, 1)
    return env * rel


def osc_saw(freq, n, phase=0.0):
    t = np.arange(n) / SR
    return 2.0 * ((t * freq + phase) % 1.0) - 1.0


def osc_square(freq, n, phase=0.0, pw=0.5):
    t = np.arange(n) / SR
    return np.where(((t * freq + phase) % 1.0) < pw, 1.0, -1.0)


def supersaw(freq, n, rng, voices=5, spread=0.012):
    out = np.zeros(n)
    for v in range(voices):
        det = 1 + spread * (v - (voices - 1) / 2) / ((voices - 1) / 2 or 1)
        out += osc_saw(freq * det, n, rng.random())
    return out / voices


class Bus:
    def __init__(self, n):
        self.buf = np.zeros(n)

    def add(self, start, sig, gain=1.0):
        i = int(round(start * SR))
        if i >= len(self.buf):
            return
        if i < 0:
            sig = sig[-i:]
            i = 0
        end = min(len(self.buf), i + len(sig))
        self.buf[i:end] += sig[: end - i] * gain


def drum_kick(rng, punch=1.0):
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    f = 48 + 170 * np.exp(-t / 0.03)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.2)
    click = rng.standard_normal(n) * np.exp(-t / 0.002) * 0.5
    return np.tanh((body + click) * (2.0 * punch)) * 0.9


def drum_clap(rng):
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    noise = bandpass(rng.standard_normal(n), 900, 3500)
    env = np.zeros(n)
    for k, off in enumerate((0.0, 0.011, 0.022)):
        env += np.where(t >= off, np.exp(-(t - off) / (0.008 if k < 2 else 0.11)), 0)
    return noise * env * 0.9


def drum_snare(rng):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    noise = bandpass(rng.standard_normal(n), 1500, 8000)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.04)
    return noise * np.exp(-t / 0.08) * 0.7 + tone * 0.6


def drum_hat(rng, open_=False):
    n = int((0.3 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    noise = highpass(rng.standard_normal(n), 7000, 4)
    return noise * np.exp(-t / (0.09 if open_ else 0.012)) * 0.5


def drum_taiko(rng):
    """祭り太鼓っぽい低いドン"""
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = 75 + 45 * np.exp(-t / 0.05)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.28)
    skin = lowpass(rng.standard_normal(n), 600) * np.exp(-t / 0.04) * 0.8
    return np.tanh((body + skin) * 1.5) * 0.8


def drum_rim(rng):
    """ふちを叩くカッ"""
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 1700 * t) * np.exp(-t / 0.012)
    tone2 = np.sin(2 * np.pi * 2900 * t) * np.exp(-t / 0.008)
    noise = bandpass(rng.standard_normal(n), 2000, 6000) * np.exp(-t / 0.01)
    return (tone + tone2 * 0.5 + noise * 0.6) * 0.6


def drum_crash(rng):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    noise = highpass(rng.standard_normal(n), 4000, 2)
    return noise * np.exp(-t / 0.55) * 0.35


def riser(rng, dur):
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    chunks = 24
    size = n // chunks + 1
    for c in range(chunks):
        a, b = c * size, min(n, (c + 1) * size)
        if a >= n:
            break
        cutoff = 400 + (9000 * (c / chunks) ** 2)
        out[a:b] = highpass(noise[a:b], cutoff, 2)
    ramp = np.linspace(0, 1, n) ** 2
    return out * ramp * 0.35


def pluck(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for k in range(1, 12):
        if freq * k > SR / 2.3:
            break
        s += np.sin(2 * np.pi * freq * k * t) / k * np.exp(-t * (4 + k * 3))
    return s * adsr(n, 0.002, 0.2, 0.0, 0.02)


def lead_tone(freq, dur, rng, bright=1.0):
    n = max(1, int(dur * SR))
    t = np.arange(n) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.12) / 0.1, 0, 1)
    ph = np.cumsum(freq * vib) / SR
    saw = 2.0 * ((ph + rng.random()) % 1.0) - 1.0
    sq = np.where(((ph * 1.003 + rng.random()) % 1.0) < 0.5, 1.0, -1.0)
    s = saw * 0.6 + sq * 0.4 * bright
    return s * adsr(n, 0.004, 0.15, 0.75, 0.04)


# ------------------------------------------------------------
# 歌 (声の種類と歌詞)。歌詞は かなで書く (1文字 = 1音、小さい ゃゅょ はまとめて1音)
#   verse: Aメロ (2行ずつ使う)、chorus: サビ (4行をくり返す。1行目と3行目は同じフレーズで中毒性を出す)
# ------------------------------------------------------------
VOCALS = {
    "s01": ("woman",
            ["ちょうちん ゆれる よるの みち", "たいこの おとが よんでいる",
             "ゆかた ひるがえし かけだせば", "きみの えがおが ひかってる"],
            ["どんどこ どんどこ どんどこ どん", "わっしょい わっしょい ヘイ ヘイ ヘイ",
             "どんどこ どんどこ どんどこ どん", "おまつり さわいで ヘイ ヘイ ヘイ"]),
    "s02": ("woman",
            ["あさの ひかりが まどを たたく", "くつひも むすんで とびだそう",
             "あおい そらへ てを のばして", "きのうの なみだは おいてくの"],
            ["サニー サニー ポップ ポップ ラッシュ", "はしれ はしれ もっと はやく",
             "サニー サニー ポップ ポップ ラッシュ", "わらって わらって イェイ イェイ イェイ"]),
    "s03": ("girl",
            ["うさぎの みみが ぴょこんと たって", "あめの あとには にじの はし",
             "ポケット いっぱい キャンディ つめて", "パレード はじまる あいずだよ"],
            ["ぴょんぴょん ぴょんぴょん ぴょんぴょんぴょん", "うさうさ パレード はじまるよ",
             "ぴょんぴょん ぴょんぴょん ぴょんぴょんぴょん", "みみみみ みみみみ ぴょこぴょこりん"]),
    "s04": ("woman",
            ["ネオンの まちに まよいこんで", "よるの かぜが ささやいた",
             "ひかりの なみに とびこめば", "ふたりの ステップ そろってく"],
            ["ネオン ネオン ビート ビート", "ひかれ ひかれ パレード",
             "ネオン ネオン ビート ビート", "おどれ おどれ あさまで"]),
    "s05": ("girl",
            ["ねこまんま たべたら げんき いっぱい", "しっぽを ふりふり おさんぽだ",
             "まどべで ひなたぼっこ したら", "きょうも にゃんだか いいきぶん"],
            ["にゃんにゃん にゃんにゃん にゃんにゃんにゃん", "ねこまんま ダンス くるりんぱ",
             "にゃんにゃん にゃんにゃん にゃんにゃんにゃん", "おなかが ぺこぺこ にゃにゃにゃにゃにゃ"]),
    "s06": ("girl",
            ["ポケットの なかの ちいさな ほし", "なめたら からだが うきあがる",
             "カウントダウンで めを とじて", "ゆめの せかいへ ひとっとび"],
            ["ロケット ロケット キャンディ キャンディ", "はじけて はじけて ポン ポン ポン",
             "ロケット ロケット キャンディ キャンディ", "とんでけ とんでけ スリー ツー ワン"]),
    "s07": ("woman",
            ["やたいの けむりが そらに のぼる", "わたあめ ふたつ てに もって",
             "はなびの あいずが なりひびく", "こころの たいこも うちならせ"],
            ["わっしょい わっしょい よまつりだ", "ハイ ハイ ハイ ハイ テンション あげろ",
             "わっしょい わっしょい よまつりだ", "あさまで さわげ ソイヤ ソイヤ"]),
    "s08": ("man",
            ["やまの おくから やってきた", "はっぱ いちまい あたまに のせ",
             "ばけて ばかして まちを ゆけば", "だれも おいらに おいつけない"],
            ["ぽんぽこ ぽんぽこ ターボ たぬき", "ブン ブン ブン ブン ぶっとばせ",
             "ぽんぽこ ぽんぽこ ターボ たぬき", "だれにも とめられ ないんだぜ"]),
    "s09": ("woman",
            ["くろい くもが うずを まいて", "いなずま はしる よるの そら",
             "たいこを うてば かぜが ふく", "いかずちの おとが ちを ゆらす"],
            ["ゴロゴロ ゴロゴロ らいじんさま", "ドン ドン ドン ドン ブレイク ブレイク",
             "ゴロゴロ ゴロゴロ らいじんさま", "ピカッと ひかって ドドドドン"]),
    "s10": ("girl",
            ["かわもに うかぶ ちいさな あかり", "ねがいを こめて ながしたの",
             "ほしの うみへと ゆれながら", "とおい あしたを てらしてる"],
            ["ランラン ランタン ハイパー ランタン", "きらきら ゆらゆら そらへ とべ",
             "ランラン ランタン ハイパー ランタン", "ねがいを こめて ラララララ"]),
    "s11": ("man",
            ["もえる ほのおを むねに だいて", "スタート ラインに たちあがる",
             "うしろは もう ふりむかない", "まえだけ みつめて かけだせ"],
            ["ダッシュ ダッシュ ぐれん ダッシュ", "もやせ もやせ ハートを もやせ",
             "ダッシュ ダッシュ ぐれん ダッシュ", "ゴール まで ノン ストップ"]),
    "s12": ("girl",
            ["ボリューム いっぱい あげちゃって", "あたまの なかまで おまつりだ",
             "ペンライト ふって さけんだら", "せかいが まるごと まわりだす"],
            ["オーバー オーバー ドライブ ドライブ", "フェス フェス フェス フェス フェスティバル",
             "オーバー オーバー ドライブ ドライブ", "みんなで ジャンプ いち に の さん"]),
    "s13": ("woman",
            ["かぜを きりさき ばちを ふる", "あせが ひかって とびちった",
             "なみの ように せまる おと", "ひとつ のこらず うちぬけ"],
            ["たたけ たたけ しっぷう どとう", "ドドドド カカカカ ドドドドン",
             "たたけ たたけ しっぷう どとう", "こころの ままに うちならせ"]),
    "s14": ("man",
            ["ここまで きたなら もう にげない", "ゆびさき ふるえる げんかいち",
             "ふかく いきを すいこんで", "さいごの ステージ たちむかえ"],
            ["へのとげ へのとげ マックス マックス", "ぶちぬけ ぶちぬけ ゲンカイ こえろ",
             "へのとげ へのとげ マックス マックス", "さいごの さいごまで たたきこめ"]),
    "s15": ("man",
            ["せかいの おわりに ひびく おと", "おおだいこが うなりを あげる",
             "くずれる そらの まんなかで", "さいごの リズムを きざみこめ"],
            ["ドン ドン ドン ドン おおだいこ", "しゅう えん しゅう えん うちならせ",
             "ドン ドン ドン ドン おおだいこ", "せかいの おわりに ひびかせろ"]),
}


def fit_onsets(template, count, grid):
    """リズムの型 (2小節=32ステップ) を、歌詞の音の数に合わせて増やしたり減らしたりする"""
    def prio(x):
        return (x % 8 == 0) * 3 + (x % 4 == 0) * 2 + (x % 2 == 0)

    s = sorted({x for x in template if x % grid == 0 and x <= 28})
    if 0 not in s:
        s.insert(0, 0)
    while len(s) > count:
        cand = [x for x in s if x != 0]
        x = min(cand, key=lambda v: (prio(v), -v))
        s.remove(x)
    while len(s) < count:
        free = [c for c in range(0, 29, grid) if c not in s]
        if not free:
            break
        best = max(free, key=lambda c: (min(abs(c - v) for v in s), prio(c)))
        s.append(best)
        s.sort()
    return s


# ------------------------------------------------------------
# 構成
# ------------------------------------------------------------
def arrangement(bars):
    """小節ごとのセクション名のリスト"""
    body = bars - 1  # 最後の1小節はアウトロ
    if body < 16:
        plan = [("intro", 2), ("verse", 4), ("build", 2), ("chorus", body - 8)]
    elif body < 26:
        c2 = body - 18
        plan = [("intro", 2), ("verse", 4), ("build", 2), ("chorus", 8), ("break", 1), ("build", 1), ("chorus", c2)]
        if c2 < 4:
            plan = [("intro", 2), ("verse", 4), ("build", 2), ("chorus", body - 8)]
    else:
        c2 = body - 22
        plan = [("intro", 2), ("verse", 4), ("build", 2), ("chorus", 8), ("break", 2), ("verse", 2), ("build", 2),
                ("chorus", c2)]
    out = []
    for name, n in plan:
        out += [name] * n
    return out + ["outro"]


# ------------------------------------------------------------
# 作曲
# ------------------------------------------------------------
def build_song(spec):
    seed = int(spec["id"][1:]) * 7919 + 101
    rng = np.random.default_rng(seed)
    bpm = spec["bpm"]
    beat = 60.0 / bpm
    step = beat / 4
    bar_len = beat * 4
    style = spec["style"]
    key = spec["key"]
    minor = spec["mode"] == "minor"
    scale = MINOR if minor else MAJOR
    penta = PENTA_MINOR if minor else PENTA_MAJOR
    prog = PROGRESSIONS[spec["mode"]][int(rng.integers(0, 4))]
    sections = arrangement(spec["bars"])
    n_bars = len(sections)

    seconds = LEAD_IN + n_bars * bar_len + TAIL
    N = int(seconds * SR) + SR
    drums = Bus(N)
    bass = Bus(N)
    chords = Bus(N)
    lead = Bus(N)
    plucks = Bus(N)
    fx = Bus(N)

    events = {}

    def mark(si, inst, v=1.0):
        d = events.setdefault(si, {})
        d[inst] = max(d.get(inst, 0), v)

    def deg_note(deg, octave=0):
        o, d = divmod(deg, 7)
        return key + scale[d] + 12 * (o + octave)

    def chord_notes(bar):
        r = prog[bar % 4]
        return [deg_note(r), deg_note(r + 2), deg_note(r + 4)]

    penta_notes = sorted({key + p + 12 * o for o in range(-1, 3) for p in penta})

    def nearest(pool, x):
        return min(pool, key=lambda p: abs(p - x))

    # ---- メロディのモチーフ ----
    hook_rhythm = HOOK_RHYTHMS[int(rng.integers(0, len(HOOK_RHYTHMS)))]
    hook_rhythm2 = HOOK_RHYTHMS[int(rng.integers(0, len(HOOK_RHYTHMS)))]
    verse_rhythm = VERSE_RHYTHMS[int(rng.integers(0, len(VERSE_RHYTHMS)))]

    def contour(n):
        steps = [0]
        for _ in range(n - 1):
            steps.append(int(rng.choice([-2, -1, -1, 1, 1, 1, 2, 0])))
        return steps

    hook_contour = contour(16)
    hook_contour2 = contour(16)
    verse_contour = contour(16)

    def realize(rhythm, cont, bar, start, lo, hi, end_on_root=False):
        chord = chord_notes(bar)
        chord_pool = [c + 12 * o for c in chord for o in range(-1, 3) if lo <= c + 12 * o <= hi]
        pool = [p for p in penta_notes if lo <= p <= hi]
        onsets = [i for i, ch in enumerate(rhythm) if ch == "x"]
        notes = []
        cur = nearest(chord_pool, start)
        for k, s in enumerate(onsets):
            if k > 0:
                idx = pool.index(nearest(pool, cur)) + cont[k % len(cont)]
                idx = max(0, min(len(pool) - 1, idx))
                cur = pool[idx]
            if s % 4 == 0:
                cur = nearest(chord_pool, cur)
            notes.append([s, cur])
        if end_on_root and notes:
            root = chord[0]
            notes[-1][1] = nearest([root + 12 * o for o in range(-1, 3)], notes[-1][1])
        out = []
        for k, (s, p) in enumerate(notes):
            nxt = notes[k + 1][0] if k + 1 < len(notes) else 16
            out.append((s, p, min(4, nxt - s)))
        return out

    # ---- 音色 ----
    s_kick = drum_kick(rng, 1.2 if style in ("hardcore", "eurobeat") else 1.0)
    s_clap = drum_clap(rng)
    s_snare = drum_snare(rng)
    s_hat = drum_hat(rng)
    s_ohat = drum_hat(rng, True)
    s_taiko = drum_taiko(rng)
    s_rim = drum_rim(rng)
    s_crash = drum_crash(rng)

    kick_times = []
    last_pitch = key + 12
    lead_lo, lead_hi = key + 7, key + 26

    voice, verse_lines, chorus_lines = VOCALS[spec["id"]]
    v_lo, v_hi = singer.VOICES[voice][2]
    vocal_phrases = []  # (歌詞の音, 音符)
    sec_start = 0
    verse_count = -1
    sing_last = (v_lo + v_hi) // 2
    grid = 2 if bpm >= 150 else 1
    chorus_anchor = (v_lo + v_hi) // 2 + 3

    def vocal_phrase(bar, line, line_idx, sec):
        nonlocal sing_last
        morae = singer.split_morae(line)
        if sec == "chorus" and line_idx % 2 == 0:
            # サビの決めフレーズは毎回同じ高さから歌い出す (くり返しで耳に残す)
            sing_last = chorus_anchor
        if sec == "chorus":
            r1, r2 = (hook_rhythm, hook_rhythm2) if line_idx % 2 == 0 else (hook_rhythm2, hook_rhythm)
            cont = hook_contour if line_idx % 2 == 0 else hook_contour2
            lo, hi = v_lo + 3, v_hi
        else:
            r1, r2 = verse_rhythm, verse_rhythm
            cont = verse_contour
            lo, hi = v_lo, v_hi - 4
        template = [i for i, ch in enumerate(r1) if ch == "x"] + [16 + i for i, ch in enumerate(r2) if ch == "x"]
        onsets = fit_onsets(template, len(morae), grid)
        morae = morae[: len(onsets)]
        pool = [p for p in penta_notes + [x + 12 for x in penta_notes] if lo <= p <= hi]
        pool = sorted(set(pool))
        cur = nearest(pool, sing_last)
        notes = []
        for k, st in enumerate(onsets):
            b = bar + st // 16
            ch = chord_notes(b)
            chord_pool = sorted({c + 12 * o for c in ch for o in range(-2, 3) if lo <= c + 12 * o <= hi}) or pool
            if k > 0:
                idx = pool.index(nearest(pool, cur)) + cont[k % len(cont)]
                cur = pool[max(0, min(len(pool) - 1, idx))]
            if st % 8 == 0 or k == len(onsets) - 1:
                cur = nearest(chord_pool, cur)
            nxt_st = onsets[k + 1] if k + 1 < len(onsets) else 30
            t = LEAD_IN + (bar * 16 + st) * step
            notes.append((t, (nxt_st - st) * step, cur))
            mark(bar * 16 + st, "lead", 1.0)
            events[bar * 16 + st]["pitch"] = cur
        if notes:
            sing_last = notes[-1][2]
        vocal_phrases.append((morae, notes))

    for bar, sec in enumerate(sections):
        t0 = LEAD_IN + bar * bar_len
        base = bar * 16
        prev = sections[bar - 1] if bar > 0 else None
        nxt = sections[bar + 1] if bar + 1 < n_bars else None
        chord = chord_notes(bar)

        def hit(s, sound, gain, inst, v=1.0):
            drums.add(t0 + s * step, sound, gain)
            mark(base + s, inst, v)

        # セクションの頭にクラッシュ
        if sec != prev and sec in ("verse", "chorus"):
            drums.add(t0, s_crash, 0.9)
            mark(base, "crash", 1.0)

        if sec == "outro":
            drums.add(t0, s_crash, 1.0)
            drums.add(t0, s_kick, 1.0)
            kick_times.append(t0)
            if style == "matsuri":
                drums.add(t0, s_taiko, 1.0)
            mark(base, "crash", 1.0)
            mark(base, "kick", 1.0)
            mark(base, "finale", 1.0)
            for c in chord_notes(0) + [deg_note(prog[0], -1)]:
                chords.add(t0, supersaw(midi_hz(c), int(2.2 * SR), rng) * adsr(int(2.2 * SR), 0.005, 0.8, 0.0, 0.6),
                           0.3)
            bass.add(t0, osc_saw(midi_hz(deg_note(0, -2)), int(1.5 * SR)) * adsr(int(1.5 * SR), 0.005, 0.5, 0, 0.3), 0.6)
            break

        full = sec == "chorus"
        quiet = sec in ("intro", "break")

        # ---- ドラム ----
        for s in range(16):
            # キック
            k = False
            if sec == "intro":
                k = bar >= 1 and s % 4 == 0
            elif sec == "break":
                k = False
            elif sec == "build":
                last_build = nxt != "build"
                k = s % 4 == 0 and not (last_build and s >= 8)
            elif style == "dnb":
                k = s in (0, 10) or (full and s == 7 and bar % 2 == 1)
            elif style == "matsuri":
                k = s % 4 == 0
            else:
                k = s % 4 == 0
            if k:
                hit(s, s_kick, 1.0, "kick")
                kick_times.append(t0 + s * step)

            # スネア/クラップ
            if sec in ("verse", "chorus"):
                if style == "dnb":
                    if s in (4, 12):
                        hit(s, s_snare, 0.8, "snare")
                        hit(s, s_clap, 0.4, "snare")
                    elif full and s in (14,) and bar % 2 == 0:
                        hit(s, s_snare, 0.4, "snare", 0.6)
                else:
                    if s in (4, 12):
                        hit(s, s_clap, 0.75, "snare")
                        if full:
                            drums.add(t0 + s * step, s_snare, 0.35)
            if sec == "build":
                # スネアロール (だんだん細かく)
                last_build = nxt != "build"
                every = 2 if not last_build else (2 if s < 8 else 1)
                if bar % 2 == 0 and not last_build:
                    every = 4
                if s % every == 0:
                    g = 0.3 + 0.5 * (s / 16)
                    hit(s, s_snare, g, "roll", 0.8)
            if bar % 4 == 3 and sec in ("verse", "chorus") and nxt == sec and s >= 12:
                hit(s, s_snare, 0.5, "snare", 0.8)

            # ハイハット
            if sec in ("verse", "chorus", "intro"):
                if s % 4 == 2:
                    if full or style in ("house", "eurobeat", "hardcore"):
                        hit(s, s_ohat, 0.6, "hat", 0.5)
                    else:
                        hit(s, s_hat, 0.8, "hat", 0.4)
                elif full and s % 2 == 1 and style in ("denpa", "trance", "hardcore", "dnb"):
                    hit(s, s_hat, 0.5, "hat", 0.25)
                elif s % 2 == 0 and not quiet:
                    hit(s, s_hat, 0.4, "hat", 0.2)

            # 祭り太鼓
            if style == "matsuri" and sec in ("verse", "chorus", "break"):
                pat = "x..x..x.x.x.x..." if full else "x.....x.x......."
                if sec == "break":
                    pat = "x..x..x.x..x.x.x"
                if pat[s] == "x":
                    hit(s, s_taiko, 0.8, "taiko")
                if full and s in (6, 14):
                    hit(s, s_rim, 0.5, "rim", 0.7)

        # ---- ベース ----
        root = chord[0] - 24
        if sec in ("verse", "chorus", "build") or (sec == "intro" and bar >= 1):
            for s in range(16):
                play = False
                n = root
                if style in ("eurobeat", "hardcore"):
                    play = s % 2 == 0
                    n = root + (12 if s % 4 == 2 else 0)
                elif style == "house":
                    play = s % 4 == 2 or (full and s % 4 == 3)
                elif style == "dnb":
                    play = s in (0, 6, 10) or (full and s == 14)
                elif style == "matsuri":
                    play = s % 4 == 0 or s % 4 == 3
                    n = root + (12 if s % 8 == 3 else 0)
                else:  # denpa, trance
                    play = s % 2 == 0 and s % 4 != 0 or (full and s % 4 == 0)
                    n = root + (12 if s % 4 == 2 else 0)
                if sec == "build" and nxt != "build" and s >= 8:
                    play = False
                if play:
                    dur = step * (3.5 if style == "dnb" else 1.6)
                    m = int(dur * SR)
                    sig = (osc_saw(midi_hz(n), m) * 0.7 + np.sin(2 * np.pi * midi_hz(n) * np.arange(m) / SR) * 0.6)
                    bass.add(t0 + s * step, sig * adsr(m, 0.003, 0.12, 0.6, 0.03), 0.5)
                    mark(base + s, "bass", 0.5)

        # ---- コード ----
        if sec == "chorus" or sec == "break":
            m = int(bar_len * SR)
            for c in chord:
                chords.add(t0, supersaw(midi_hz(c), m, rng) * adsr(m, 0.01, 0.6, 0.8, 0.05), 0.22)
            chords.add(t0, supersaw(midi_hz(chord[0] - 12), m, rng) * adsr(m, 0.01, 0.6, 0.8, 0.05), 0.15)
        elif sec in ("verse", "intro", "build"):
            stab_steps = [2, 6, 10, 14] if style != "dnb" else [0, 3, 6, 10]
            for s in stab_steps:
                m = int(step * 1.5 * SR)
                for c in chord:
                    chords.add(t0 + s * step, supersaw(midi_hz(c), m, rng, 3) * adsr(m, 0.003, 0.08, 0.3, 0.02), 0.2)

        # ---- アルペジオ ----
        if full and style in ("denpa", "trance", "eurobeat", "hardcore", "matsuri"):
            arp = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[1] + 24]
            for s in range(16):
                p = arp[s % 4]
                plucks.add(t0 + s * step, pluck(midi_hz(p), step * 1.5), 0.18)
                mark(base + s, "arp", 0.4)
        if style == "matsuri" and sec in ("verse", "break"):
            for s in range(0, 16, 2):
                p = nearest(penta_notes, chord[s // 2 % 3] + 12)
                plucks.add(t0 + s * step, pluck(midi_hz(p), step * 2), 0.22)
                mark(base + s, "arp", 0.4)

        # ---- 歌 ----
        if sec != prev:
            sec_start = bar
            if sec == "verse":
                verse_count += 1
        rel = bar - sec_start
        sung = False
        if sec in ("verse", "chorus") and rel % 2 == 0 and nxt == sec:
            k = rel // 2
            if sec == "chorus":
                line = chorus_lines[k % len(chorus_lines)]
                vocal_phrase(bar, line, k, sec)
            else:
                idx = (verse_count * 2 + k) % len(verse_lines)
                vocal_phrase(bar, verse_lines[idx], idx, sec)
            sung = True
        elif sec in ("verse", "chorus") and rel % 2 == 1:
            sung = True  # 2小節フレーズの後半

        # ---- 楽器のメロディ (歌がないところ) ----
        melody = []
        if not sung and sec in ("chorus", "verse"):
            melody = realize(hook_rhythm, hook_contour, bar, last_pitch, lead_lo + 5, lead_hi, end_on_root=True)
        elif sec == "break" and bar % 2 == 0:
            melody = realize(hook_rhythm, hook_contour, bar, last_pitch, lead_lo, lead_hi - 3)
        for s_, p, ln in melody:
            dur = ln * step * 0.9
            lead.add(t0 + s_ * step, lead_tone(midi_hz(p), dur, rng), 0.26)
            mark(base + s_, "lead", 1.0)
            events[base + s_]["pitch"] = p
            last_pitch = p

        # ---- ビルドの盛り上げ ----
        if sec == "build" and nxt != "build":
            fx.add(t0, riser(rng, bar_len), 0.9)

    # ---- 歌を合成 ----
    vocals = Bus(N)
    for morae, notes in vocal_phrases:
        if not notes:
            continue
        y, vt0 = singer.sing_phrase(morae, notes, voice)
        vocals.add(vt0, y, 1.0)
    v = highpass(vocals.buf, 140, 2)
    v = lowpass(v, 10000, 2)
    vp = np.max(np.abs(v)) or 1.0
    v = np.tanh(v / vp * 1.6) / np.tanh(1.6)
    # リバーブ (減衰するノイズで畳み込む)
    ir_len = int(1.1 * SR)
    ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (0.25 * SR))
    ir = lowpass(ir, 5000) * 0.02
    v_wet = fftconvolve(v, ir)[: N]
    vocal_mix = v * 0.55 + v_wet

    # ---- サビ直前のボーカル・スタッター (サビの頭の声を細かく刻んで溜める) ----
    stutter = np.zeros(N)
    for bar, sec in enumerate(sections):
        if sec != "chorus" or bar == 0 or sections[bar - 1] == "chorus":
            continue
        tc = LEAD_IN + bar * bar_len
        a = int((tc - 0.01) * SR)
        b = int((tc + step * 0.9) * SR)
        if b > N or a < 0:
            continue
        chop = vocal_mix[a:b].copy()
        if np.max(np.abs(chop)) < 1e-4:
            continue
        chop *= np.minimum(1, np.linspace(0, 8, len(chop))) * np.minimum(1, np.linspace(8, 0, len(chop)))
        # 1拍前から16分で4回、最後の半拍は32分で4回
        hits = [tc - 8 * step + k * step for k in range(4)] + [tc - 4 * step + k * step / 2 for k in range(8)]
        for k, ht in enumerate(hits):
            i = int(ht * SR)
            seg = chop[: int(step * (0.95 if k < 4 else 0.48) * SR)]
            j = min(N, i + len(seg))
            stutter[i:j] += seg[: j - i] * (0.6 + 0.4 * k / len(hits))
            si = int(round((ht - LEAD_IN) / step))
            if k < 4 or k % 2 == 0:
                mark(si, "vox", 1.0)
    vocal_mix = vocal_mix + stutter

    # ---- ミックス ----
    # キックに合わせて他の音を沈ませる (サイドチェイン)
    duck = np.ones(N)
    rel = int(0.18 * SR)
    shape = 1 - 0.65 * np.exp(-np.arange(rel) / (0.06 * SR))
    for kt in kick_times:
        i = int(kt * SR)
        j = min(N, i + rel)
        duck[i:j] = np.minimum(duck[i:j], shape[: j - i])

    music = (lowpass(bass.buf, 1200) * 0.7
             + lowpass(chords.buf, 6000) * 1.25
             + lowpass(lead.buf, 7500) * 1.8
             + plucks.buf * 1.4) * duck
    inst = drums.buf * 0.8 + music * 0.85 + fx.buf
    # サビの直前は一瞬だけ楽器を止めて、声だけにする (溜め)
    for bar, sec in enumerate(sections):
        if sec == "chorus" and bar > 0 and sections[bar - 1] != "chorus":
            tc = LEAD_IN + bar * bar_len
            a = int((tc - 2 * step) * SR)
            b = int((tc - 0.004) * SR)
            gate = np.linspace(1, 0, min(400, b - a))
            inst[a:a + len(gate)] *= gate
            inst[a + len(gate):b] = 0
    mix = inst + vocal_mix
    # ディレイ
    d = int(beat * 0.75 * SR)
    wet = np.zeros_like(mix)
    wet[d:] = (lead.buf[:-d] + plucks.buf[:-d]) * 0.12
    mix = mix + wet
    mix = np.tanh(mix * 1.15)
    mix = highpass(mix, 25, 2)
    peak = np.max(np.abs(mix)) or 1.0
    mix = mix / peak * 0.92

    end = int((LEAD_IN + n_bars * bar_len + TAIL) * SR)
    end = min(end, int(MAX_SEC * SR))
    mix = mix[:end]
    fade = int(0.6 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade) ** 2

    meta = dict(bpm=bpm, step=step, events=events, n_steps=n_bars * 16, duration=len(mix) / SR,
                sections=sections, bar_len=bar_len)
    return mix, meta


# ------------------------------------------------------------
# 持ち込み音源のアレンジ (皆伝3曲目「Catastrophe」)
#   元の音源のビートに合わせて、ドラムの重ね・フィルター・溜め・スタッター・
#   決めの一撃を足して、ゲーム用に組み直す。譜面の素材も元の音源から拾う。
# ------------------------------------------------------------
def load_source(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.int16).astype(np.float64) / 32768.0


def sweep_filter(x, kind, f_from, f_to, chunks=32):
    """時間とともに周波数が動くフィルター (区切って少しずつ変える)"""
    out = np.zeros_like(x)
    size = len(x) // chunks + 1
    for c in range(chunks):
        a, b = c * size, min(len(x), (c + 1) * size)
        if a >= len(x):
            break
        r = c / max(1, chunks - 1)
        f = f_from * (f_to / f_from) ** r
        pad = min(a, 2048)
        seg = x[a - pad:b]
        y = lowpass(seg, f, 2) if kind == "low" else highpass(seg, f, 2)
        out[a:b] = y[pad:]
    return out


def build_from_source(spec):
    rng = np.random.default_rng(1601)
    bpm = spec["bpm"]
    beat = 60.0 / bpm
    step = beat / 4
    bar_len = beat * 4
    phase = spec["phase"]          # 元音源で最初の小節が始まる時刻
    n_src_bars = spec["src_bars"]  # 使う小節数
    sections = spec["sections"]    # 小節ごとのセクション (最後は outro)
    assert len(sections) == n_src_bars + 1

    src = load_source(os.path.join(ROOT, spec["source"]))
    seconds = LEAD_IN + n_src_bars * bar_len + TAIL + 0.6
    N = int(seconds * SR)
    offset = LEAD_IN - phase          # 元音源の0秒を置く位置
    o = int(round(offset * SR))
    cut = int((phase + n_src_bars * bar_len) * SR)
    body = np.zeros(N)
    seg = src[:cut]
    body[o:o + len(seg)] = seg[: max(0, min(len(seg), N - o))]

    def T(bar, s=0):
        return LEAD_IN + bar * bar_len + s * step

    def idx(t):
        return int(round(t * SR))

    # ---- 元音源の加工 ----
    # イントロ: こもった音から開いていく
    intro_end = sections.index(next(s for s in sections if s != "intro"))
    a, b = idx(T(0)) - int(0.3 * SR), idx(T(intro_end))
    body[a:b] = sweep_filter(body[a:b], "low", 300, 16000)
    # ビルド: 低音を抜いていく
    for bar, sec in enumerate(sections):
        if sec == "build" and (bar == 0 or sections[bar - 1] != "build"):
            end_bar = bar
            while end_bar < len(sections) and sections[end_bar] == "build":
                end_bar += 1
            a, b = idx(T(bar)), idx(T(end_bar))
            body[a:b] = sweep_filter(body[a:b], "high", 60, 1800)

    drums = Bus(N)
    fx = Bus(N)
    events = {}

    def mark(si, inst, v=1.0):
        d = events.setdefault(si, {})
        d[inst] = max(d.get(inst, 0), v)

    s_kick = drum_kick(rng, 1.3)
    s_clap = drum_clap(rng)
    s_snare = drum_snare(rng)
    s_ohat = drum_hat(rng, True)
    s_crash = drum_crash(rng)
    s_taiko = drum_taiko(rng)
    kick_times = []

    for bar, sec in enumerate(sections):
        prev = sections[bar - 1] if bar else None
        nxt = sections[bar + 1] if bar + 1 < len(sections) else None
        base = bar * 16

        def hit(s, sound, gain, inst=None, v=1.0, bus=drums):
            bus.add(T(bar, s), sound, gain)
            if inst:
                mark(base + s, inst, v)

        if (sec != prev and sec in ("verse", "chorus")) or bar in spec.get("crash_bars", []):
            hit(0, s_crash, 1.0, "crash")
        if sec == "outro":
            # 決めの一撃
            hit(0, s_crash, 1.2, "crash")
            hit(0, s_kick, 1.2, "kick")
            hit(0, s_taiko, 1.1, "finale")
            kick_times.append(T(bar))
            break
        for s in range(16):
            if sec == "chorus":
                if s % 4 == 0:
                    hit(s, s_kick, 0.9, "kick")
                    kick_times.append(T(bar, s))
                if s in (4, 12):
                    hit(s, s_clap, 0.7, "snare")
                if s % 4 == 2:
                    hit(s, s_ohat, 0.45, "hat", 0.4)
            elif sec == "verse":
                # 半分の速さに聞こえるビートで落差をつける
                if s in (0, 10):
                    hit(s, s_kick, 0.85, "kick")
                    kick_times.append(T(bar, s))
                if s == 8:
                    hit(s, s_clap, 0.75, "snare")
            elif sec == "build":
                last = nxt != "build"
                every = 4 if not last else (2 if s < 8 else 1)
                if s % every == 0 and not (last and s >= 14):
                    hit(s, s_snare, 0.3 + 0.5 * s / 16, "roll", 0.8)
            elif sec == "intro" and bar == intro_end - 1 and s >= 8 and s % 2 == 0:
                hit(s, s_snare, 0.4, "roll", 0.8)
        if sec == "build" and nxt != "build":
            fx.add(T(bar), riser(rng, bar_len), 1.0)

    # ---- 元音源のリズムを拾う (譜面用) ----
    def band_env(lo, hi):
        sos = butter(4, [lo, hi], btype="band", fs=SR, output="sos")
        return np.abs(sosfilt(sos, body))

    k_env = band_env(40, 130)
    s_env = band_env(1500, 5000)
    m_env = band_env(300, 1500)

    def onset(env, t):
        a, b = idx(t - 0.02), idx(t + 0.025)
        p = idx(t - 0.06)
        return max(0.0, env[a:b].mean() - env[p:a].mean())

    n_steps = n_src_bars * 16
    K = np.array([onset(k_env, T(0, i)) for i in range(n_steps)])
    S = np.array([onset(s_env, T(0, i)) for i in range(n_steps)])
    Mx = np.array([onset(m_env, T(0, i)) for i in range(n_steps)])

    def norm(v):
        top = np.percentile(v, 95) or 1.0
        return np.clip(v / top, 0, 1)

    K, S, Mx = norm(K), norm(S), norm(Mx)
    for i in range(n_steps):
        if K[i] > 0.35:
            mark(i, "kick", float(K[i]))
        if S[i] > 0.35:
            mark(i, "snare", float(S[i]) * 0.9)
        if S[i] > 0.12 or K[i] > 0.12:
            # 細かい刻み (高難度の候補)
            mark(i, "hat", 0.3)
        if Mx[i] > 0.3:
            mark(i, "lead", float(Mx[i]))
            # 色決め用の高さ: 中音域の明るさで代用
            a = idx(T(0, i))
            seg2 = body[a:a + int(0.05 * SR)]
            if len(seg2) > 32:
                spec_ = np.abs(np.fft.rfft(seg2 * np.hanning(len(seg2))))
                f = np.fft.rfftfreq(len(seg2), 1 / SR)
                events[i]["pitch"] = float((spec_ * f).sum() / (spec_.sum() + 1e-9))

    # ---- 溜めとスタッター (サビの頭の音を刻む) ----
    for bar, sec in enumerate(sections):
        if bar == 0 or sec == "outro":
            continue
        prev = sections[bar - 1]
        stutter_here = (sec == "chorus" and prev != "chorus") or bar in spec.get("stutter_bars", [])
        if not stutter_here:
            continue
        tc = T(bar)
        chop = body[idx(tc - 0.005): idx(tc + step * 0.9)].copy()
        chop *= np.minimum(1, np.linspace(0, 10, len(chop))) * np.minimum(1, np.linspace(10, 0, len(chop)))
        # 1拍前から 16分×2、32分×4 で刻んで、最後の16分は無音
        a, b = idx(tc - 4 * step), idx(tc - 0.003)
        body[a:b] = 0
        drums.buf[a:b] *= 0.0
        hits = [tc - 4 * step, tc - 3 * step] + [tc - 2 * step + k * step / 2 for k in range(2)]
        for k, ht in enumerate(hits):
            ln = int(step * (0.95 if k < 2 else 0.48) * SR)
            i0 = idx(ht)
            body[i0:i0 + ln] += chop[:ln] * (0.7 + 0.1 * k)
            mark(int(round((ht - LEAD_IN) / step)), "vox", 1.0)

    # ---- ミックス ----
    duck = np.ones(N)
    rel = int(0.16 * SR)
    shape = 1 - 0.35 * np.exp(-np.arange(rel) / (0.05 * SR))
    for kt in kick_times:
        i = int(kt * SR)
        j = min(N, i + rel)
        duck[i:j] = np.minimum(duck[i:j], shape[: j - i])

    mix = body * duck * 0.95 + drums.buf * 0.55 + fx.buf * 0.8
    mix = np.tanh(mix * 1.2)
    mix = highpass(mix, 25, 2)
    peak = np.max(np.abs(mix)) or 1.0
    mix = mix / peak * 0.93
    end = min(N, int((LEAD_IN + n_src_bars * bar_len + TAIL) * SR))
    mix = mix[:end]
    fade = int(0.8 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade) ** 2

    meta = dict(bpm=bpm, step=step, events=events, n_steps=(n_src_bars + 1) * 16, duration=len(mix) / SR,
                sections=sections, bar_len=bar_len)
    return mix, meta


# ------------------------------------------------------------
# 太鼓譜面
#   k: d=ドン k=カッ D=大ドン K=大カッ r=連打 R=大連打 b=風船
# ------------------------------------------------------------
WEIGHT = {"kick": 3.0, "snare": 3.0, "taiko": 2.5, "rim": 1.5, "crash": 2.0, "lead": 2.4, "bass": 1.0,
          "arp": 0.7, "hat": 0.5, "roll": 1.2, "finale": 9.0, "vox": 1.5}

NPS = {1: 1.2, 2: 1.6, 3: 2.1, 4: 2.7, 5: 3.3, 6: 4.0, 7: 4.8, 8: 5.8, 9: 7.0, 10: 8.8}
MIN_GAP = {1: 0.45, 2: 0.33, 3: 0.25, 4: 0.2, 5: 0.16, 6: 0.13, 7: 0.105, 8: 0.085, 9: 0.072, 10: 0.064}


def make_chart(spec, meta, difficulty, level):
    rng = np.random.default_rng(int(spec["id"][1:]) * 131 + level * 17 + len(difficulty))
    step = meta["step"]
    events = meta["events"]
    sections = meta["sections"]
    insane = difficulty == "INSANE"

    def T(si):
        return LEAD_IN + si * step

    def ms(si):
        return int(round(T(si) * 1000))

    if level <= 1:
        allowed = lambda s: s % 4 == 0
    elif level <= 2:
        allowed = lambda s: s % 2 == 0 and (s % 4 == 0 or s % 16 >= 8)
    elif level <= 5:
        allowed = lambda s: s % 2 == 0
    else:
        allowed = lambda s: True

    notes = []
    blocked = set()

    # ---- 連打・風船 (ビルドの最後の小節) ----
    balloons = 0
    for bar, sec in enumerate(sections):
        if sec != "build":
            continue
        last = bar + 1 >= len(sections) or sections[bar + 1] != "build"
        if not last:
            continue
        use_roll = level <= 7 or insane or rng.random() < 0.35
        if not use_roll:
            continue
        start = bar * 16 + (0 if level <= 4 else 8)
        end = bar * 16 + 14
        if insane and level >= 9:
            # 最高難度: 1回目は割るのが大変な風船、2回目以降は大連打
            start = bar * 16
            if balloons < 1:
                dur = T(end) - T(start)
                notes.append({"k": "b", "t": ms(start), "e": ms(end), "n": max(12, int(dur * 10.5))})
                balloons += 1
            else:
                notes.append({"k": "R", "t": ms(start), "e": ms(end)})
        elif level <= 6 and balloons < 1 and rng.random() < 0.6:
            dur = T(end) - T(start)
            hits = max(4, int(dur * (3.5 + level * 0.7)))
            notes.append({"k": "b", "t": ms(start), "e": ms(end), "n": hits})
            balloons += 1
        else:
            kind = "R" if rng.random() < 0.4 else "r"
            notes.append({"k": kind, "t": ms(start), "e": ms(end)})
        blocked.update(range(start - 2, bar * 16 + 16))

    # ---- 普通の音符の候補 ----
    play_sec = meta["n_steps"] * step
    target = int(NPS[level] * play_sec * (1.2 if insane else 1.0))
    min_gap = max(1, int(math.ceil(MIN_GAP[level] / step - 1e-6)))

    cands = []
    for si, ev in events.items():
        if si in blocked or not allowed(si):
            continue
        w = sum(WEIGHT.get(k, 0) * v for k, v in ev.items() if k in WEIGHT)
        sec = sections[min(si // 16, len(sections) - 1)]
        if sec == "chorus":
            w += 1.2
        elif sec in ("intro", "break"):
            w -= 1.0
        if si % 16 == 0:
            w += 1.5
        elif si % 4 == 0:
            w += 1.0
        elif si % 2 == 0:
            w += 0.4
        else:
            w -= 0.5 if level < 8 else 0.0
        w += rng.random() * 0.7
        cands.append((w, si))
    cands.sort(reverse=True)

    chosen = []
    taken = set()
    for w, si in cands:
        if len(chosen) >= target:
            break
        if any((si + d) in taken for d in range(-min_gap + 1, min_gap)):
            continue
        chosen.append(si)
        taken.add(si)

    # ---- 色 (ドン / カッ) と大音符 ----
    chosen.sort()
    prev_pitch = None
    big_rate = {1: 0.5, 2: 0.4, 3: 0.3, 4: 0.25, 5: 0.2, 6: 0.15, 7: 0.12, 8: 0.1, 9: 0.08, 10: 0.06}[level]
    for idx, si in enumerate(chosen):
        ev = events[si]
        pitch = ev.get("pitch")
        low = ev.get("kick", 0) > 0 or ev.get("taiko", 0) > 0 or ev.get("bass", 0) > 0
        high = ev.get("snare", 0) > 0 or ev.get("rim", 0) > 0 or ev.get("hat", 0) > 0 or ev.get("roll", 0) > 0
        if ev.get("snare", 0) > 0 or ev.get("rim", 0) > 0:
            color = "k"
        elif ev.get("kick", 0) > 0 or ev.get("taiko", 0) > 0:
            color = "d"
        elif pitch is not None and prev_pitch is not None:
            color = "k" if pitch > prev_pitch else "d"
        elif high and not low:
            color = "k"
        else:
            color = "d"
        if ev.get("roll", 0) > 0 and not ev.get("kick"):
            # ビルドのスネアロールは ドンとカッを交互に
            color = "d" if (si // max(1, min_gap)) % 2 == 0 else "k"
        if pitch is not None:
            prev_pitch = pitch

        big = False
        if ev.get("finale", 0) > 0:
            big = True
        elif ev.get("crash", 0) > 0 and rng.random() < 0.8:
            big = True
        elif si % 16 == 0 and sections[si // 16] == "chorus" and rng.random() < big_rate:
            big = True
        elif color == "k" and si % 64 == 60 and sections[si // 16] == "chorus" and rng.random() < big_rate * 3:
            # 4小節フレーズの締めのスネアは大カッ
            big = True
        # 大音符の直前直後が詰まっていたら普通の音符に
        if big and level >= 5:
            near = [c for c in chosen[max(0, idx - 1): idx + 2] if c != si]
            if any(abs(c - si) * step < 0.2 for c in near):
                big = False
        k = color.upper() if big else color
        notes.append({"k": k, "t": ms(si)})

    # ---- 高難度: 24分の高速ロール (左右交互に叩き分ける連続音符) ----
    if level >= 9 and difficulty == "INSANE":
        notes = add_bursts(notes, meta, level, rng)

    notes.sort(key=lambda n: n["t"])
    return notes


BURST_PATTERNS = ["dkdkd", "ddkdd", "kkdkk", "dkkdk", "ddkkd", "dkdkdkd", "ddkddkd", "kdkdkdk", "dddkddd"]


def add_bursts(notes, meta, level, rng):
    """4小節ごとのつなぎ目などに 24分音符の連打を差し込む"""
    step = meta["step"]
    beat = step * 4
    sections = meta["sections"]
    spans = []
    for bar, sec in enumerate(sections):
        if sec not in ("verse", "chorus"):
            continue
        last_of_phrase = bar % 4 == 3
        extra = level >= 10 and sec == "chorus" and bar % 2 == 1
        if not (last_of_phrase or extra):
            continue
        length = 7 if (level >= 10 and last_of_phrase) else 5
        start_beat = 2 if length == 7 else 3
        t_start = LEAD_IN + bar * beat * 4 + start_beat * beat
        pats = [p for p in BURST_PATTERNS if len(p) == length]
        pat = pats[int(rng.integers(0, len(pats)))]
        times = [t_start + k * beat / 6 for k in range(length)]
        spans.append((times[0] - step * 0.9, times[-1] + step * 0.9, times, pat))

    def inside(ms):
        t = ms / 1000
        return any(a <= t <= b for a, b, _, _ in spans)

    def in_roll(n):
        return n["k"] in "rRb" and any(not (n["e"] / 1000 < a or n["t"] / 1000 > b) for a, b, _, _ in spans)

    kept = [n for n in notes if not (n["k"] in "dkDK" and inside(n["t"])) and not in_roll(n)]
    for _, _, times, pat in spans:
        for t, c in zip(times, pat):
            kept.append({"k": c, "t": int(round(t * 1000))})
    return kept


# ------------------------------------------------------------
# 叩いた音
# ------------------------------------------------------------
def write_wav(path, sig):
    pcm = (np.clip(sig, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def make_se():
    os.makedirs(SE_DIR, exist_ok=True)
    rng = np.random.default_rng(7)
    don = drum_taiko(rng)[: int(0.35 * SR)]
    don = don / np.max(np.abs(don)) * 0.9
    ka = drum_rim(rng)
    ka = ka / np.max(np.abs(ka)) * 0.8
    write_wav(os.path.join(SE_DIR, "don.wav"), don)
    write_wav(os.path.join(SE_DIR, "ka.wav"), ka)


def encode(buf, path_base):
    wav = path_base + ".wav"
    write_wav(wav, buf)
    m4a = path_base + ".m4a"
    if shutil.which("ffmpeg"):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "160k", m4a],
                       check=True)
    elif shutil.which("afconvert"):
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "160000", wav, m4a], check=True)
    else:
        return os.path.basename(wav)
    os.remove(wav)
    return os.path.basename(m4a)


def build_courses(library):
    songs_by_id = {x["id"]: x for x in library["songs"]}
    out = []
    for c in COURSES:
        cond = dict(c["conditions"])
        if cond.get("ROLL") == "auto":
            # 曲ごと: 連打は 1秒あたり7回、風船は割るのに必要な回数 を赤合格の目安に。金合格はその1.3倍
            per_stage = []
            for sid, diff in c["stages"]:
                chart = next(ch for ch in songs_by_id[sid]["charts"] if ch["difficulty"] == diff)
                need = 0
                for n in chart["notes"]:
                    if n["k"] in "rR":
                        need += (n["e"] - n["t"]) / 1000 * 7
                    elif n["k"] == "b":
                        need += n["n"]
                red = int(need)
                per_stage.append([red, int(red * 1.3) + 1] if red >= 1 else None)
            cond["ROLL"] = per_stage
        out.append({
            "id": c["id"],
            "name": c["name"],
            "stages": [{"song": s, "difficulty": d} for s, d in c["stages"]],
            "conditions": cond,
        })
    return out


def main():
    os.makedirs(SONG_DIR, exist_ok=True)
    make_se()
    library = {"version": 3, "leadIn": LEAD_IN, "songs": [], "courses": []}
    report = []
    for spec in SONGS:
        buf, meta = build_from_source(spec) if spec.get("source") else build_song(spec)
        dur = meta["duration"]
        assert MIN_SEC <= dur <= MAX_SEC, f"{spec['id']} の長さが範囲外: {dur:.1f}秒"
        audio = encode(buf, os.path.join(SONG_DIR, spec["id"]))
        charts = []
        for diff in ("BASIC", "EXTREME", "INSANE"):
            if diff not in spec["levels"]:
                continue
            lv = spec["levels"][diff]
            notes = make_chart(spec, meta, diff, lv)
            charts.append({"difficulty": diff, "level": lv, "notes": notes})
            normal = [n for n in notes if n["k"] in "dkDK"]
            play = meta["n_steps"] * meta["step"]
            kinds = {k: sum(1 for n in notes if n["k"] == k) for k in "dkDKrRb"}
            report.append(f"{spec['id']} {spec['title']:<14} {diff:<8} Lv{lv:<2} {dur:4.1f}s notes={len(normal):4d} "
                          f"nps={len(normal) / play:4.1f} " + " ".join(f"{k}={v}" for k, v in kinds.items()))
        bars = [int(round((LEAD_IN + b * meta["bar_len"]) * 1000)) for b in range(len(meta["sections"]))]
        library["songs"].append({
            "id": spec["id"],
            "title": spec["title"],
            "artist": ARTIST,
            "bpm": spec["bpm"],
            "audio": audio,
            "duration": round(dur, 3),
            "bars": bars,
            "charts": charts,
        })
        print(f"generated {spec['id']} ({dur:.1f}s)", file=sys.stderr)

    library["courses"] = build_courses(library)

    with open(os.path.join(OUT_DIR, "library.json"), "w", encoding="utf-8") as f:
        json.dump(library, f, ensure_ascii=False, separators=(",", ":"))
    print("\n".join(report))


if __name__ == "__main__":
    main()
