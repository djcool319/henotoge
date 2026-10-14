#!/usr/bin/env python3
"""
henotoge 曲・譜面ジェネレーター

15曲のオリジナル曲(シンセで合成)と、その曲のリズムから作る譜面、
段位認定コースをまとめて生成する。

出力:
  Henotoge/Resources/Songs/sXX.m4a   (ffmpeg がない場合は .wav)
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

import numpy as np
from scipy.signal import lfilter

SR = 44100
LANES = 4
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Henotoge", "Resources")
SONG_DIR = os.path.join(OUT_DIR, "Songs")

# ------------------------------------------------------------
# 曲リスト
#   levels: 難易度ごとのレベル。INSANE は一部の曲だけ
#   busy:   メロディの細かさ (0〜1)
#   style:  ドラムの雰囲気
# ------------------------------------------------------------
SONGS = [
    dict(id="s01", title="はじまりのビート", bpm=100, key=60, mode="major", sec=36, busy=0.05, style="four",
         levels={"BASIC": 1, "EXTREME": 4}),
    dict(id="s02", title="Morning Drop", bpm=110, key=62, mode="major", sec=38, busy=0.15, style="four",
         levels={"BASIC": 2, "EXTREME": 5}),
    dict(id="s03", title="ひだまりステップ", bpm=118, key=65, mode="major", sec=40, busy=0.2, style="shuffle",
         levels={"BASIC": 2, "EXTREME": 5}),
    dict(id="s04", title="Neon Puddle", bpm=126, key=57, mode="minor", sec=42, busy=0.3, style="four",
         levels={"BASIC": 2, "EXTREME": 6}),
    dict(id="s05", title="ねこじゃらしファンク", bpm=112, key=64, mode="minor", sec=44, busy=0.4, style="funk",
         levels={"BASIC": 2, "EXTREME": 6}),
    dict(id="s06", title="Glass Signal", bpm=138, key=59, mode="minor", sec=44, busy=0.35, style="four",
         levels={"BASIC": 3, "EXTREME": 7}),
    dict(id="s07", title="夜行列車", bpm=144, key=62, mode="minor", sec=46, busy=0.45, style="break",
         levels={"BASIC": 3, "EXTREME": 7}),
    dict(id="s08", title="Cobalt Runner", bpm=150, key=55, mode="minor", sec=48, busy=0.5, style="four",
         levels={"BASIC": 4, "EXTREME": 7}),
    dict(id="s09", title="雷鳴コード", bpm=156, key=58, mode="minor", sec=48, busy=0.55, style="break",
         levels={"BASIC": 4, "EXTREME": 8, "INSANE": 9}),
    dict(id="s10", title="Paper Satellite", bpm=162, key=61, mode="major", sec=50, busy=0.6, style="four",
         levels={"BASIC": 4, "EXTREME": 8}),
    dict(id="s11", title="紅蓮スパイラル", bpm=168, key=56, mode="minor", sec=50, busy=0.65, style="break",
         levels={"BASIC": 5, "EXTREME": 8}),
    dict(id="s12", title="Overclock Heart", bpm=174, key=60, mode="minor", sec=52, busy=0.7, style="four",
         levels={"BASIC": 5, "EXTREME": 8, "INSANE": 9}),
    dict(id="s13", title="零下の残響", bpm=180, key=57, mode="minor", sec=54, busy=0.75, style="break",
         levels={"BASIC": 5, "EXTREME": 8, "INSANE": 9}),
    dict(id="s14", title="HENOTOGE", bpm=186, key=62, mode="minor", sec=56, busy=0.8, style="four",
         levels={"BASIC": 6, "EXTREME": 9, "INSANE": 10}),
    dict(id="s15", title="終末アルゴリズム", bpm=196, key=59, mode="minor", sec=58, busy=0.9, style="break",
         levels={"BASIC": 6, "EXTREME": 9, "INSANE": 10}),
]

ARTIST = "henotoge sound team"

# ------------------------------------------------------------
# 段位認定 (3曲メドレー)
#   limits: そのコース全体で許される回数。0未満になったら不合格。
#           null は無制限。
# ------------------------------------------------------------
COURSES = [
    dict(id="dan1", name="初段", stages=[("s01", "EXTREME"), ("s02", "EXTREME"), ("s03", "EXTREME")],
         limits={"GREAT": None, "GOOD": 60, "MISS": 30}),
    dict(id="dan2", name="三段", stages=[("s04", "EXTREME"), ("s05", "EXTREME"), ("s06", "EXTREME")],
         limits={"GREAT": None, "GOOD": 45, "MISS": 20}),
    dict(id="dan3", name="五段", stages=[("s07", "EXTREME"), ("s08", "EXTREME"), ("s10", "EXTREME")],
         limits={"GREAT": None, "GOOD": 30, "MISS": 12}),
    dict(id="dan4", name="八段", stages=[("s11", "EXTREME"), ("s09", "INSANE"), ("s12", "INSANE")],
         limits={"GREAT": 200, "GOOD": 25, "MISS": 8}),
    dict(id="dan5", name="皆伝", stages=[("s13", "INSANE"), ("s14", "INSANE"), ("s15", "INSANE")],
         limits={"GREAT": 120, "GOOD": 15, "MISS": 3}),
]

# レベルごとの1秒あたりノーツ数の目安
NPS = {1: 1.3, 2: 1.8, 3: 2.4, 4: 3.0, 5: 3.7, 6: 4.5, 7: 5.4, 8: 6.5, 9: 7.8, 10: 9.6}

LEAD_IN = 2.0  # 曲の頭に入れる無音(秒)。最初のノーツが落ちてくる時間を確保する。

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]

PROGRESSIONS = {
    "major": [[0, 4, 5, 3], [0, 5, 3, 4], [3, 4, 2, 5], [0, 3, 4, 4]],
    "minor": [[0, 5, 2, 6], [0, 3, 6, 4], [5, 6, 0, 0], [0, 6, 5, 4]],
}


def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


# ------------------------------------------------------------
# 音源
# ------------------------------------------------------------
class Mixer:
    def __init__(self, seconds):
        self.buf = np.zeros(int(seconds * SR) + SR, dtype=np.float64)

    def add(self, start, sig, gain=1.0):
        i = int(start * SR)
        if i < 0:
            sig = sig[-i:]
            i = 0
        end = min(len(self.buf), i + len(sig))
        if end > i:
            self.buf[i:end] += sig[: end - i] * gain


def env_ad(n, attack, decay_tau):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / decay_tau)


def env_gate(n, attack, release):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((n / SR - t) / max(release, 1e-4), 0, 1)
    return a * r


def kick(rng):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * np.exp(-t / 0.16)
    click = rng.standard_normal(n) * np.exp(-t / 0.003) * 0.3
    return np.tanh((s + click) * 1.6)


def snare(rng):
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    noise = lfilter([1, -0.6], [1], noise)
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05)
    return (noise * np.exp(-t / 0.07) * 0.6 + body * 0.6)


def hat(rng, open_=False):
    n = int((0.25 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    noise = np.diff(noise, prepend=0)
    noise = np.diff(noise, prepend=0)
    return noise * np.exp(-t / (0.08 if open_ else 0.015)) * 0.25


def crash(rng):
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    noise = np.diff(rng.standard_normal(n), prepend=0)
    return noise * np.exp(-t / 0.45) * 0.3


def tone(freq, dur, harmonics, attack=0.005, release=0.05, decay=None, detune=0.0):
    n = max(1, int(dur * SR))
    t = np.arange(n) / SR
    s = np.zeros(n)
    for k, amp in harmonics:
        fk = freq * k
        if fk > SR / 2.2:
            continue
        s += amp * np.sin(2 * np.pi * fk * t)
        if detune:
            s += amp * 0.6 * np.sin(2 * np.pi * fk * (1 + detune) * t)
    e = env_gate(n, attack, release)
    if decay:
        e = e * np.exp(-t / decay)
    return s * e


SAW = [(k, 1.0 / k) for k in range(1, 9)]
SQUARE = [(k, 1.0 / k) for k in range(1, 12, 2)]
SOFT = [(1, 1.0), (2, 0.25), (3, 0.1)]
BELL = [(1, 1.0), (2, 0.4), (3, 0.2), (4.2, 0.15)]


# ------------------------------------------------------------
# 作曲
# ------------------------------------------------------------
def build_song(spec):
    seed = int(spec["id"][1:]) * 7919 + 13
    rng = np.random.default_rng(seed)
    bpm = spec["bpm"]
    beat = 60.0 / bpm
    step = beat / 4  # 16分
    scale = MAJOR if spec["mode"] == "major" else MINOR
    key = spec["key"]
    busy = spec["busy"]
    style = spec["style"]
    prog = PROGRESSIONS[spec["mode"]][rng.integers(0, 4)]

    total_bars = int(round(spec["sec"] / (beat * 4)))
    total_bars = max(12, total_bars)
    # 構成: イントロ2小節 → 本編(A/B を8小節単位) → アウトロ1小節
    body = total_bars - 3
    sections = ["intro", "intro"]
    names = []
    i = 0
    while len(names) < body:
        block = "A" if (i % 2 == 0) else "B"
        names += [block] * min(8, body - len(names))
        i += 1
    if names and names[-1] == "A" and len(names) >= 8:
        # 最後は盛り上げる
        for j in range(len(names) - 4, len(names)):
            names[j] = "B"
    sections += names + ["outro"]

    seconds = LEAD_IN + len(sections) * 4 * beat + 2.0
    mix = Mixer(seconds)

    # step_index -> {楽器: 強さ}
    events = {}

    def mark(si, inst, val=1.0):
        d = events.setdefault(si, {})
        d[inst] = max(d.get(inst, 0), val)

    def degree_note(deg, octave=0):
        o, d = divmod(deg, 7)
        return key + scale[d] + 12 * (o + octave)

    def chord_tones(bar):
        root_deg = prog[bar % 4]
        return [root_deg, root_deg + 2, root_deg + 4]

    # ---- メロディのモチーフ (2小節 = 32ステップ) ----
    def make_motif(r):
        onsets = []
        for s in range(32):
            pos = s % 4
            if s % 16 == 0:
                p = 0.95
            elif pos == 0:
                p = 0.55 + 0.25 * busy
            elif pos == 2:
                p = 0.25 + 0.45 * busy
            else:
                p = 0.03 + 0.55 * busy ** 1.5
            if r.random() < p:
                onsets.append(s)
        if 0 not in onsets:
            onsets.insert(0, 0)
        degs = []
        cur = 7 + int(r.integers(0, 3))
        for s in onsets:
            if s % 8 == 0:
                # 強拍はコードトーンに寄せる
                cur = cur + int(r.choice([-2, 0, 2]))
            else:
                cur = cur + int(r.choice([-2, -1, -1, 1, 1, 2, 3, -3]))
            cur = int(np.clip(cur, 3, 13))
            degs.append(cur)
        return list(zip(onsets, degs))

    motif_a = make_motif(rng)
    motif_b = make_motif(rng)

    def vary(motif, r, amount):
        out = []
        for s, d in motif:
            if s >= 16 and r.random() < amount:
                d = int(np.clip(d + int(r.choice([-2, -1, 1, 2])), 3, 13))
            out.append((s, d))
        return out

    kick_s = kick(rng)
    snare_s = snare(rng)
    hat_c = hat(rng)
    hat_o = hat(rng, True)
    crash_s = crash(rng)

    lead_wave = SQUARE if spec["mode"] == "minor" else SAW
    lead_detune = 0.004 if busy > 0.5 else 0.0

    for bar, sec in enumerate(sections):
        bar_t = LEAD_IN + bar * 4 * beat
        base = bar * 16
        chord = chord_tones(bar)
        intense = sec == "B"
        prev = sections[bar - 1] if bar > 0 else None

        # クラッシュ (セクションの頭)
        if sec != prev and sec in ("A", "B"):
            mix.add(bar_t, crash_s, 0.5)
            mark(base, "crash", 1.0)

        # パッド
        pad_len = 4 * beat
        for d in chord:
            f = midi_hz(degree_note(d, 0))
            mix.add(bar_t, tone(f, pad_len, SOFT, attack=0.08, release=0.3, detune=0.003), 0.06)

        if sec == "outro":
            mix.add(bar_t, kick_s, 0.9)
            mix.add(bar_t, crash_s, 0.6)
            mark(base, "kick", 1.0)
            mark(base, "crash", 1.0)
            f = midi_hz(degree_note(prog[0], -1))
            mix.add(bar_t, tone(f, 2.5, SAW, release=1.5), 0.18)
            break

        # ---- ドラム ----
        for s in range(16):
            t = bar_t + s * step
            si = base + s
            if sec == "intro":
                if s % 4 == 0:
                    mix.add(t, hat_c, 0.7)
                    mark(si, "hat", 0.5)
                if bar == 1 and s in (8, 12, 14):
                    mix.add(t, snare_s, 0.5)
                    mark(si, "snare", 0.8)
                continue

            k = False
            sn = False
            if style == "four":
                k = s % 4 == 0
                sn = s in (4, 12)
                if intense and s in (14,) and bar % 2 == 1:
                    k = True
            elif style == "break":
                k = s in (0, 6, 10) or (intense and s == 3)
                sn = s in (4, 12) or (intense and s == 15 and bar % 2 == 1)
            elif style == "funk":
                k = s in (0, 3, 6, 10)
                sn = s in (4, 12) or s in (7, 13) and rng.random() < 0.4
            elif style == "shuffle":
                k = s in (0, 8, 10)
                sn = s in (4, 12)

            # 4小節ごとのフィル
            if bar % 4 == 3 and s >= 12:
                if busy > 0.45 or intense:
                    sn = True
                elif s % 2 == 0:
                    sn = True

            if k:
                mix.add(t, kick_s, 0.9)
                mark(si, "kick", 1.0)
            if sn:
                mix.add(t, snare_s, 0.55 if s in (4, 12) else 0.4)
                mark(si, "snare", 1.0 if s in (4, 12) else 0.7)

            hat_every = 1 if (busy > 0.55 or (intense and busy > 0.3)) else 2
            if style == "shuffle":
                if s % 4 in (0, 3):
                    mix.add(t, hat_c, 0.7)
                    mark(si, "hat", 0.4)
            elif s % hat_every == 0:
                if s % 4 == 2 and intense:
                    mix.add(t, hat_o, 0.5)
                else:
                    mix.add(t, hat_c, 0.8 if s % 2 == 0 else 0.5)
                mark(si, "hat", 0.4 if s % 2 == 0 else 0.25)

        if sec == "intro":
            continue

        # ---- ベース ----
        root = degree_note(chord[0], -2)
        if style == "funk":
            bass_steps = [0, 3, 6, 8, 10, 14]
        elif busy > 0.5:
            bass_steps = [0, 2, 4, 6, 8, 10, 12, 14]
        else:
            bass_steps = [0, 6, 8, 12] if style != "four" else [0, 4, 8, 12]
        for s in bass_steps:
            t = bar_t + s * step
            n = root + (12 if (busy > 0.5 and s % 4 == 2) else 0)
            mix.add(t, tone(midi_hz(n), step * 1.8, SAW, release=0.04, decay=0.25), 0.22)
            mark(base + s, "bass", 0.6)

        # ---- アルペジオ (細かい曲のサビ) ----
        if busy >= 0.6 or (intense and busy >= 0.4):
            arp_every = 1 if busy >= 0.7 else 2
            for s in range(0, 16, arp_every):
                d = chord[(s // arp_every) % 3] + (7 if (s // 8) % 2 else 0)
                f = midi_hz(degree_note(d, 1))
                mix.add(bar_t + s * step, tone(f, step * 0.9, BELL, release=0.03, decay=0.12), 0.07)
                mark(base + s, "arp", 0.5)

        # ---- メロディ ----
        phrase_bar = bar % 2
        block_index = (bar - 2) // 2
        motif = motif_b if intense else motif_a
        if block_index % 4 == 3:
            motif = vary(motif, np.random.default_rng(seed + bar), 0.6)
        notes = [(s - 16 * phrase_bar, d) for s, d in motif if 16 * phrase_bar <= s < 16 * (phrase_bar + 1)]
        oct_shift = 1 if intense else 0
        for idx, (s, d) in enumerate(notes):
            nxt = notes[idx + 1][0] if idx + 1 < len(notes) else 16
            length = max(1, nxt - s) * step * 0.95
            # 強拍ではコードトーンに吸着
            if s % 8 == 0:
                d = min(chord + [c + 7 for c in chord], key=lambda c: abs(c - d))
            n = degree_note(d, oct_shift)
            mix.add(bar_t + s * step,
                    tone(midi_hz(n), length, lead_wave, attack=0.004, release=0.04, decay=0.6, detune=lead_detune),
                    0.11)
            mark(base + s, "lead", 1.0)
            events[base + s]["pitch"] = n

    # ---- 仕上げ ----
    buf = mix.buf
    # 軽いリバーブ風ディレイ
    delay = int(beat * 0.75 * SR)
    wet = np.zeros_like(buf)
    wet[delay:] = buf[:-delay] * 0.18
    buf = buf + wet
    buf = np.tanh(buf * 1.3)
    peak = np.max(np.abs(buf)) or 1.0
    buf = buf / peak * 0.89
    end = int((LEAD_IN + len(sections) * 4 * beat + 1.5) * SR)
    buf = buf[:end]
    fade = int(0.5 * SR)
    buf[-fade:] *= np.linspace(1, 0, fade)

    meta = dict(bpm=bpm, step=step, events=events, n_steps=len(sections) * 16, duration=len(buf) / SR,
                sections=sections)
    return buf, meta


# ------------------------------------------------------------
# 譜面
# ------------------------------------------------------------
WEIGHT = {"kick": 3.0, "snare": 3.0, "crash": 2.0, "lead": 2.6, "bass": 1.2, "arp": 1.0, "hat": 0.6}


def make_chart(spec, meta, difficulty, level):
    rng = np.random.default_rng(int(spec["id"][1:]) * 101 + level * 7 + len(difficulty))
    step = meta["step"]
    events = meta["events"]

    # 使っていい細かさ
    if level <= 2:
        allowed = lambda s: s % 4 == 0
    elif level <= 4:
        allowed = lambda s: s % 2 == 0
    elif level <= 6:
        allowed = lambda s: s % 2 == 0 or level >= 6
    else:
        allowed = lambda s: True

    cands = []
    for si, ev in events.items():
        if not allowed(si):
            continue
        w = sum(WEIGHT.get(k, 0) * v for k, v in ev.items() if k in WEIGHT)
        if si % 16 == 0:
            w += 1.5
        elif si % 4 == 0:
            w += 1.0
        elif si % 2 == 0:
            w += 0.4
        else:
            w -= 0.6 if level < 8 else 0.0
        w += rng.random() * 0.8
        cands.append((w, si))
    cands.sort(reverse=True)

    play_sec = meta["n_steps"] * step
    # INSANE は同じレベルでも一段詰める
    target = int(NPS[level] * play_sec * (1.12 if difficulty == "INSANE" else 1.0))

    # 最低間隔(ステップ数)。低レベルは詰めない
    min_gap_sec = {1: 0.55, 2: 0.4, 3: 0.3, 4: 0.22, 5: 0.17, 6: 0.14, 7: 0.11, 8: 0.09, 9: 0.075, 10: 0.06}[level]
    min_gap = max(1, int(math.ceil(min_gap_sec / step - 1e-6)))

    # 同時押しの量
    chord2 = {1: 0, 2: 0, 3: 0.03, 4: 0.06, 5: 0.10, 6: 0.14, 7: 0.18, 8: 0.22, 9: 0.26, 10: 0.30}[level]
    chord3 = {8: 0.03, 9: 0.06, 10: 0.10}.get(level, 0)

    chosen = {}
    taken = set()
    count = 0
    for w, si in cands:
        if count >= target:
            break
        if any((si + d) in taken for d in range(-min_gap + 1, min_gap)):
            continue
        ev = events[si]
        size = 1
        strong = ev.get("crash", 0) > 0 or (ev.get("kick", 0) > 0 and (ev.get("snare", 0) > 0 or ev.get("lead", 0) > 0))
        if strong or si % 16 == 0:
            r = rng.random()
            if r < chord3 * 2.5:
                size = 3
            elif r < chord2 * 2.5:
                size = 2
        elif rng.random() < chord2 * 0.5:
            size = 2
        size = min(size, max(1, target - count))
        chosen[si] = size
        taken.add(si)
        count += size

    # レーン割り当て
    notes = []
    prev_lanes = []
    prev_t = -10.0
    prev_pitch = None
    lane = int(rng.integers(0, LANES))
    for si in sorted(chosen):
        size = chosen[si]
        t = LEAD_IN + si * step
        gap = t - prev_t
        ev = events[si]
        pitch = ev.get("pitch")
        if pitch is not None and prev_pitch is not None:
            diff = pitch - prev_pitch
            if diff > 0:
                lane = lane + (1 if diff <= 3 else 2)
            elif diff < 0:
                lane = lane - (1 if diff >= -3 else 2)
            else:
                lane = lane + int(rng.choice([-1, 1])) if gap < 0.25 else lane
        else:
            lane = lane + int(rng.choice([-2, -1, 1, 2]))
        lane = lane % LANES
        if pitch is not None:
            prev_pitch = pitch

        # 速い連打(同じレーン)を避ける
        if gap < 0.22 and lane in prev_lanes:
            free = [l for l in range(LANES) if l not in prev_lanes]
            if free:
                lane = min(free, key=lambda l: abs(l - lane))
        lanes = [lane]
        if size > 1:
            pool = [l for l in range(LANES) if l != lane and not (gap < 0.16 and l in prev_lanes)]
            if len(pool) < size - 1:
                pool = [l for l in range(LANES) if l != lane]
            # 離れたレーンを優先
            pool.sort(key=lambda l: -abs(l - lane) + rng.random() * 0.5)
            lanes += pool[: size - 1]
        for l in sorted(lanes):
            notes.append([int(round(t * 1000)), int(l)])
        prev_lanes = lanes
        prev_t = t

    notes.sort()
    return notes


def encode(buf, path_base):
    pcm = (buf * 32767).astype(np.int16)
    wav = path_base + ".wav"
    import wave
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    if shutil.which("ffmpeg"):
        m4a = path_base + ".m4a"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "128k", m4a],
                       check=True)
        os.remove(wav)
        return os.path.basename(m4a)
    if shutil.which("afconvert"):
        m4a = path_base + ".m4a"
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "128000", wav, m4a], check=True)
        os.remove(wav)
        return os.path.basename(m4a)
    return os.path.basename(wav)


def main():
    os.makedirs(SONG_DIR, exist_ok=True)
    library = {"version": 1, "leadIn": LEAD_IN, "lanes": LANES, "songs": [], "courses": []}
    report = []
    for spec in SONGS:
        buf, meta = build_song(spec)
        audio = encode(buf, os.path.join(SONG_DIR, spec["id"]))
        charts = []
        for diff in ("BASIC", "EXTREME", "INSANE"):
            if diff not in spec["levels"]:
                continue
            lv = spec["levels"][diff]
            notes = make_chart(spec, meta, diff, lv)
            charts.append({"difficulty": diff, "level": lv, "notes": notes})
            play = meta["n_steps"] * meta["step"]
            report.append(f"{spec['id']} {spec['title']:<16} {diff:<8} Lv{lv:<2} notes={len(notes):4d} "
                          f"nps={len(notes) / play:4.1f}")
        library["songs"].append({
            "id": spec["id"],
            "title": spec["title"],
            "artist": ARTIST,
            "bpm": spec["bpm"],
            "audio": audio,
            "duration": round(meta["duration"], 3),
            "charts": charts,
        })
        print(f"generated {spec['id']} ({meta['duration']:.1f}s)", file=sys.stderr)

    for c in COURSES:
        library["courses"].append({
            "id": c["id"],
            "name": c["name"],
            "stages": [{"song": s, "difficulty": d} for s, d in c["stages"]],
            "limits": c["limits"],
        })

    with open(os.path.join(OUT_DIR, "library.json"), "w", encoding="utf-8") as f:
        json.dump(library, f, ensure_ascii=False, separators=(",", ":"))
    print("\n".join(report))


if __name__ == "__main__":
    main()
