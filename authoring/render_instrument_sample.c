/* Offline-only SF2 renderer. The game ships WAV files, never this executable.
 * Input rows: filename bank program key velocity note_on_seconds total_seconds.
 * TinySoundFont is supplied by --tsf-header to the Python build script. */
#include <stdio.h>
#include <stdlib.h>
#define TSF_IMPLEMENTATION
#include "tsf.h"

int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: render sf2 plan output_dir\n"); return 2; }
    tsf *font = tsf_load_filename(argv[1]);
    FILE *plan = fopen(argv[2], "r");
    if (!font || !plan) { fprintf(stderr, "Cannot open SoundFont/plan\n"); return 3; }
    char name[128], path[4096];
    int bank, program, key, velocity, count = 0;
    float hold, total;
    while (fscanf(plan, "%127s %d %d %d %d %f %f", name, &bank, &program, &key,
                  &velocity, &hold, &total) == 7) {
        tsf *voice = tsf_copy(font);
        int preset = tsf_get_presetindex(voice, bank, program);
        if (preset < 0) { fprintf(stderr, "Missing preset %d:%d\n", bank, program); return 4; }
        tsf_set_output(voice, TSF_MONO, 44100, 0.0f);
        int frames = (int)(total * 44100), on_frames = (int)(hold * 44100);
        float *pcm = calloc(frames, sizeof(float));
        if (!pcm || !tsf_note_on(voice, preset, key, velocity / 127.0f)) return 5;
        tsf_render_float(voice, pcm, on_frames, 0);
        tsf_note_off(voice, preset, key);
        tsf_render_float(voice, pcm + on_frames, frames - on_frames, 0);
        snprintf(path, sizeof(path), "%s/%s.f32", argv[3], name);
        FILE *output = fopen(path, "wb");
        if (!output || fwrite(pcm, sizeof(float), frames, output) != (size_t)frames) return 6;
        fclose(output);
        free(pcm);
        tsf_close(voice);
        count++;
    }
    fclose(plan);
    tsf_close(font);
    printf("Rendered %d mono samples at 44100 Hz\n", count);
    return 0;
}
