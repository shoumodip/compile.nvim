#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#if defined(_WIN32) || defined(_WIN64)
#define WEXITSTATUS(s) (s)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

static double now(void) {
#if defined(_WIN32) || defined(_WIN64)
    LARGE_INTEGER frequency, counter;
    if (!QueryPerformanceFrequency(&frequency)) {
        return 0.0;
    }

    if (!QueryPerformanceCounter(&counter)) {
        return 0.0;
    }
    return (double) counter.QuadPart / frequency.QuadPart;
#else
    struct timespec clock;
    if (clock_gettime(CLOCK_MONOTONIC, &clock) < 0) {
        return 0.0;
    }
    return clock.tv_sec + clock.tv_nsec * 1e-9;
#endif // _WIN32
}

int main(int argc, const char **argv) {
    assert(argc == 2);
    const char *cmd = argv[1];

    fprintf(stderr, "Executing `%s`\n\n", cmd);
    const double start = now();
    const int    code = WEXITSTATUS(system(cmd));
    const double duration = now() - start;

    fprintf(stderr, "\nCompilation ");
    if (code == -1) {
        fprintf(stderr, "exited abnormally");
    } else if (code) {
        fprintf(stderr, "exited abnormally with code %d", code);
    } else {
        fprintf(stderr, "finished");
    }
    fprintf(stderr, " in");

    const size_t hours = floor(duration / 3600);
    const size_t minutes = floor(fmod(duration, 3600) / 60);
    const double seconds = fmod(duration, 60);

    if (hours > 0) {
        fprintf(stderr, " %zuh", hours);
    }

    if (minutes > 0 || (hours > 0 && seconds > 0)) {
        fprintf(stderr, " %zum", minutes);
    }

    if (seconds > 0) {
        fprintf(stderr, " %.2fs", seconds);
    }

    fprintf(stderr, "\n");
    return code;
}
