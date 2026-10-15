// wsing: 話し声 (Open JTalk の出力) を WORLD で分解して、
// 指定したタイミング・音程・声色で歌わせ直す小さなツール。
//
// 使い方: wsing in.wav ctrl.bin out.wav formant_ratio
//   ctrl.bin = int32 フレーム数 N, そのあと N 個の (double src_time, double f0, double gain)
//   フレーム間隔は 5ms。src_time は元の音声のどの時刻を使うか (秒)。
//   f0 > 0 なら、元が有声のところをその音程にする。gain は音量。
//   formant_ratio > 1 で声色が高く(若く)、< 1 で低く(太く)なる。
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "world/cheaptrick.h"
#include "world/d4c.h"
#include "world/harvest.h"
#include "world/synthesis.h"

static bool read_wav(const char *path, std::vector<double> &x, int &fs) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    std::vector<unsigned char> buf;
    unsigned char tmp[65536];
    size_t n;
    while ((n = fread(tmp, 1, sizeof(tmp), f)) > 0) buf.insert(buf.end(), tmp, tmp + n);
    fclose(f);
    if (buf.size() < 44) return false;
    fs = *(int32_t *)&buf[24];
    size_t pos = 12;
    while (pos + 8 <= buf.size()) {
        uint32_t size = *(uint32_t *)&buf[pos + 4];
        if (memcmp(&buf[pos], "data", 4) == 0) {
            size_t count = size / 2;
            if (pos + 8 + size > buf.size()) count = (buf.size() - pos - 8) / 2;
            x.resize(count);
            const int16_t *p = (const int16_t *)&buf[pos + 8];
            for (size_t i = 0; i < count; i++) x[i] = p[i] / 32768.0;
            return true;
        }
        pos += 8 + size + (size & 1);
    }
    return false;
}

static void write_wav(const char *path, const std::vector<double> &y, int fs) {
    FILE *f = fopen(path, "wb");
    uint32_t data = (uint32_t)y.size() * 2;
    uint32_t riff = 36 + data;
    uint16_t fmt_tag = 1, ch = 1, bits = 16, align = 2;
    uint32_t fmt_size = 16, rate = fs, bps = fs * 2;
    fwrite("RIFF", 1, 4, f);
    fwrite(&riff, 4, 1, f);
    fwrite("WAVEfmt ", 1, 8, f);
    fwrite(&fmt_size, 4, 1, f);
    fwrite(&fmt_tag, 2, 1, f);
    fwrite(&ch, 2, 1, f);
    fwrite(&rate, 4, 1, f);
    fwrite(&bps, 4, 1, f);
    fwrite(&align, 2, 1, f);
    fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f);
    fwrite(&data, 4, 1, f);
    for (double v : y) {
        double c = v < -1 ? -1 : (v > 1 ? 1 : v);
        int16_t s = (int16_t)lrint(c * 32767);
        fwrite(&s, 2, 1, f);
    }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc < 5) {
        fprintf(stderr, "usage: wsing in.wav ctrl.bin out.wav formant_ratio\n");
        return 1;
    }
    std::vector<double> x;
    int fs = 0;
    if (!read_wav(argv[1], x, fs)) {
        fprintf(stderr, "cannot read %s\n", argv[1]);
        return 1;
    }
    double ratio = atof(argv[4]);
    const double fp = 5.0;

    // 解析
    HarvestOption hopt;
    InitializeHarvestOption(&hopt);
    hopt.frame_period = fp;
    hopt.f0_floor = 70.0;
    hopt.f0_ceil = 800.0;
    int src_len = GetSamplesForHarvest(fs, (int)x.size(), fp);
    std::vector<double> tpos(src_len), sf0(src_len);
    Harvest(x.data(), (int)x.size(), fs, &hopt, tpos.data(), sf0.data());

    CheapTrickOption copt;
    InitializeCheapTrickOption(fs, &copt);
    copt.f0_floor = 70.0;
    copt.fft_size = GetFFTSizeForCheapTrick(fs, &copt);
    int fft = copt.fft_size;
    int bins = fft / 2 + 1;
    std::vector<std::vector<double>> sp(src_len, std::vector<double>(bins)), ap(src_len, std::vector<double>(bins));
    std::vector<double *> spp(src_len), app(src_len);
    for (int i = 0; i < src_len; i++) {
        spp[i] = sp[i].data();
        app[i] = ap[i].data();
    }
    CheapTrick(x.data(), (int)x.size(), fs, tpos.data(), sf0.data(), src_len, &copt, spp.data());
    D4COption dopt;
    InitializeD4COption(&dopt);
    D4C(x.data(), (int)x.size(), fs, tpos.data(), sf0.data(), src_len, fft, &dopt, app.data());

    // 制御データ
    FILE *cf = fopen(argv[2], "rb");
    if (!cf) {
        fprintf(stderr, "cannot read %s\n", argv[2]);
        return 1;
    }
    int32_t n_out = 0;
    if (fread(&n_out, 4, 1, cf) != 1 || n_out <= 0) return 1;
    std::vector<double> ctrl((size_t)n_out * 3);
    if (fread(ctrl.data(), 8, ctrl.size(), cf) != ctrl.size()) return 1;
    fclose(cf);

    std::vector<double> of0(n_out);
    std::vector<std::vector<double>> osp(n_out, std::vector<double>(bins)), oap(n_out, std::vector<double>(bins));
    std::vector<double> tmp_sp(bins), tmp_ap(bins);
    for (int k = 0; k < n_out; k++) {
        double st = ctrl[k * 3], f0 = ctrl[k * 3 + 1], gain = ctrl[k * 3 + 2];
        double fi = st / (fp / 1000.0);
        if (fi < 0) fi = 0;
        if (fi > src_len - 1) fi = src_len - 1;
        int i0 = (int)floor(fi);
        int i1 = i0 + 1 < src_len ? i0 + 1 : i0;
        double fr = fi - i0;
        for (int b = 0; b < bins; b++) {
            tmp_sp[b] = sp[i0][b] * (1 - fr) + sp[i1][b] * fr;
            tmp_ap[b] = ap[i0][b] * (1 - fr) + ap[i1][b] * fr;
        }
        bool voiced = (sf0[i0] > 0) || (sf0[i1] > 0 && fr > 0.5);
        of0[k] = (voiced && f0 > 0) ? f0 : 0.0;
        double g2 = gain * gain;
        for (int b = 0; b < bins; b++) {
            double sb = b / ratio;
            int b0 = (int)floor(sb);
            double bf = sb - b0;
            if (b0 >= bins - 1) {
                osp[k][b] = tmp_sp[bins - 1] * g2;
                oap[k][b] = tmp_ap[bins - 1];
            } else {
                osp[k][b] = (tmp_sp[b0] * (1 - bf) + tmp_sp[b0 + 1] * bf) * g2;
                oap[k][b] = tmp_ap[b0] * (1 - bf) + tmp_ap[b0 + 1] * bf;
            }
            if (osp[k][b] < 1e-16) osp[k][b] = 1e-16;
        }
    }

    std::vector<double *> ospp(n_out), oapp(n_out);
    for (int k = 0; k < n_out; k++) {
        ospp[k] = osp[k].data();
        oapp[k] = oap[k].data();
    }
    int y_len = (int)((n_out - 1) * fp / 1000.0 * fs) + 1;
    std::vector<double> y(y_len);
    Synthesis(of0.data(), n_out, ospp.data(), oapp.data(), fft, fp, fs, y_len, y.data());
    write_wav(argv[3], y, fs);
    return 0;
}
