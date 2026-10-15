"""
歌声合成 (ボカロ風)。

Open JTalk で歌詞を「しゃべらせ」、音素ごとの時刻を取り出してから、
WORLD (wsing) で各音を楽譜のタイミングと音程に合わせて引き伸ばし・音程変更する。

必要なもの (tools/README_voice.md 参照):
  $HENOTOGE_VOICEBUILD/open_jtalk/src/build/bin/open_jtalk
  $HENOTOGE_VOICEBUILD/open_jtalk_dic_utf_8-1.11/
  $HENOTOGE_VOICEBUILD/wsing
  声: mei_normal.htsvoice / tohoku-f01-happy.htsvoice
"""

import os
import struct
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import resample_poly

VB = os.environ.get("HENOTOGE_VOICEBUILD", "/home/claude/voicebuild")
OPEN_JTALK = os.path.join(VB, "open_jtalk/src/build/bin/open_jtalk")
DIC = os.path.join(VB, "open_jtalk_dic_utf_8-1.11")
WSING = os.path.join(VB, "wsing")

# 声の種類: (HTS ボイス, 声色の倍率, 歌う音域 [低い, 高い] MIDI)
VOICES = {
    "girl": (os.path.join(VB, "htsvoice-tohoku-f01/tohoku-f01-happy.htsvoice"), 1.10, (67, 81)),
    "woman": (os.path.join(VB, "pyopenjtalk/pyopenjtalk/htsvoice/mei_normal.htsvoice"), 1.0, (62, 76)),
    "man": (os.path.join(VB, "pyopenjtalk/pyopenjtalk/htsvoice/mei_normal.htsvoice"), 0.80, (52, 66)),
}

SMALL = set("ゃゅょぁぃぅぇぉャュョァィゥェォ")
VOWELS = set("aiueoAIUEO")
FP = 0.005  # wsing のフレーム間隔


def available():
    return all(os.path.exists(p) for p in (OPEN_JTALK, DIC, WSING))


def to_kata(s):
    return "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in s)


def split_morae(text):
    """かなの歌詞を1音(モーラ)ずつに分ける。空白は無視"""
    out = []
    for c in text:
        if c in " 　、。!！?？":
            continue
        if c in SMALL and out:
            out[-1] += c
        else:
            out.append(c)
    return out


def _read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
    return x, sr


def _speak(kata, voice_path, tmp):
    txt = os.path.join(tmp, "in.txt")
    wav = os.path.join(tmp, "speech.wav")
    trace = os.path.join(tmp, "trace.txt")
    with open(txt, "w", encoding="utf-8") as f:
        f.write(kata + "\n")
    subprocess.run([OPEN_JTALK, "-x", DIC, "-m", voice_path, "-ow", wav, "-ot", trace, txt],
                   check=True, capture_output=True)
    phones = []
    with open(trace, encoding="utf-8") as f:
        in_labels = False
        for line in f:
            if line.startswith("[Output label]"):
                in_labels = True
                continue
            if in_labels:
                parts = line.split()
                if len(parts) < 3:
                    if phones:
                        break
                    continue
                lab = parts[2]
                try:
                    ph = lab.split("-")[1].split("+")[0]
                except IndexError:
                    continue
                phones.append((int(parts[0]) / 1e7, int(parts[1]) / 1e7, ph))
    x, sr = _read_wav(wav)
    return x, sr, phones


def _group(phones):
    """音素を1音ずつにまとめる -> [(子音の開始, 母音の開始, 終わり, 種類)]"""
    groups = []
    cons_start = None
    for s, e, ph in phones:
        if ph in ("sil", "pau"):
            cons_start = None
            continue
        if ph in VOWELS or ph == "N":
            cs = cons_start if cons_start is not None else s
            groups.append((cs, s, e, "v"))
            cons_start = None
        elif ph == "cl":
            groups.append((s, s, e, "cl"))
            cons_start = None
        else:
            if cons_start is None:
                cons_start = s
    return groups


def _silence_time(phones):
    for s, e, ph in phones:
        if ph == "sil":
            return (s + e) / 2
    return 0.0


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def sing_phrase(morae, notes, voice, out_sr=44100):
    """
    morae: ["ど", "ん", ...]、notes: [(開始秒, 長さ秒, MIDI), ...] (同じ数)
    戻り値: (音声, 先頭の時刻)。先頭の時刻は notes[0] より少し前。
    """
    voice_path, formant, _ = VOICES[voice]
    n = min(len(morae), len(notes))
    morae = morae[:n]
    notes = notes[:n]
    with tempfile.TemporaryDirectory() as tmp:
        x, sr, phones = _speak(to_kata("".join(morae)), voice_path, tmp)
        groups = _group(phones)
        if len(groups) != n:
            # 読みがずれたら、1音ずつ読ませる
            groups, x = _speak_each(morae, voice_path, tmp)
            sil_t = 0.0
        else:
            sil_t = _silence_time(phones)
        n = min(n, len(groups))

        t0 = notes[0][0] - 0.15
        t_end = notes[n - 1][0] + notes[n - 1][1] + 0.2
        frames = int((t_end - t0) / FP) + 1
        src = np.full(frames, sil_t)
        f0 = np.zeros(frames)
        gain = np.zeros(frames)

        # 子音の長さ (最大 70ms) と、音の区切り
        cons = []
        for i in range(n):
            cs, vs, ve, kind = groups[i]
            cons.append(min(max(0.0, vs - cs), 0.07) if kind == "v" else 0.0)

        for i in range(n):
            cs, vs, ve, kind = groups[i]
            start, dur, midi = notes[i]
            next_start = notes[i + 1][0] - cons[i + 1] if i + 1 < n else start + dur
            v_end = min(start + dur, next_start)
            if i + 1 < n and next_start - (start + dur) < 0.06:
                v_end = next_start  # ほぼつながっているならレガートに
            if kind == "cl":
                continue
            c = cons[i]
            prev_m = notes[i - 1][2] if i > 0 else midi
            a = int((start - c - t0) / FP)
            b = int((v_end - t0) / FP)
            for k in range(max(0, a), min(frames, b)):
                t = t0 + k * FP
                if t < start:
                    r = (t - (start - c)) / max(c, 1e-4)
                    src[k] = cs + r * (vs - cs)
                else:
                    r = (t - start) / max(v_end - start, 1e-4)
                    # 母音の頭の 40ms はそのまま、残りを引き伸ばす
                    head = min(0.04, (ve - vs) * 0.5)
                    if t - start < head:
                        src[k] = vs + (t - start)
                    else:
                        r2 = (t - start - head) / max(v_end - start - head, 1e-4)
                        src[k] = vs + head + r2 * max(0.0, ve - vs - head - 0.01)
                # 音程: 前の音からすべり込み + ビブラート
                m = midi
                glide = 0.05
                if t < start + glide and i > 0 and notes[i - 1][0] + notes[i - 1][1] >= start - 0.08:
                    rr = max(0.0, (t - (start - 0.02)) / (glide + 0.02))
                    m = prev_m + (midi - prev_m) * min(1.0, rr)
                held = t - start
                if held > 0.22:
                    depth = min(1.0, (held - 0.22) / 0.2) * 0.3
                    m += depth * np.sin(2 * np.pi * 5.6 * held)
                f0[k] = midi_hz(m)
                # 音量: 入りと切れ目をなめらかに
                g = 1.0
                if t < start - c + 0.01:
                    g = 0.5
                if v_end - t < 0.02 and v_end != next_start:
                    g = max(0.0, (v_end - t) / 0.02)
                gain[k] = g

        ctrl = os.path.join(tmp, "ctrl.bin")
        with open(ctrl, "wb") as f:
            f.write(struct.pack("<i", frames))
            f.write(np.stack([src, f0, gain], axis=1).astype("<f8").tobytes())
        src_wav = os.path.join(tmp, "src.wav")
        _write_wav(src_wav, x, sr)
        out = os.path.join(tmp, "sung.wav")
        subprocess.run([WSING, src_wav, ctrl, out, str(formant)], check=True, capture_output=True)
        y, ysr = _read_wav(out)
    if ysr != out_sr:
        from math import gcd
        g = gcd(ysr, out_sr)
        y = resample_poly(y, out_sr // g, ysr // g)
    return y, t0


def _speak_each(morae, voice_path, tmp):
    """1音ずつ読ませてつなげる (うまく区切れなかったとき用)"""
    xs = []
    groups = []
    offset = 0.0
    sr = 48000
    for m in morae:
        x, sr, phones = _speak(to_kata(m), voice_path, tmp)
        g = _group(phones)
        if g:
            cs, vs, ve, kind = g[0]
        else:
            cs, vs, ve, kind = 0.0, 0.0, len(x) / sr, "v"
        groups.append((cs + offset, vs + offset, ve + offset, kind))
        xs.append(x)
        offset += len(x) / sr
    return groups, np.concatenate(xs)


def _write_wav(path, x, sr):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
