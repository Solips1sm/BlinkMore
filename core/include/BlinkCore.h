#ifndef BLINK_CORE_H
#define BLINK_CORE_H
#include <stdint.h>
typedef struct BMTracker BMTracker;
typedef struct { double x, y; } BMPoint;
typedef struct {
    const BMPoint *left;
    uint32_t left_count;
    const BMPoint *right;
    uint32_t right_count;
    double face_width, face_height, timestamp, confidence, sensitivity;
} BMInput;
typedef struct {
    uint32_t phase, flags, closed_mask;
    double left_openness, right_openness, left_ratio, right_ratio;
    double calibration, open_seconds, tracked_delta, asymmetry;
} BMOutput;
BMTracker *bm_tracker_new(void);
void bm_tracker_free(BMTracker *tracker);
void bm_tracker_reset(BMTracker *tracker);
BMOutput bm_tracker_process(BMTracker *tracker, BMInput input);
#endif
