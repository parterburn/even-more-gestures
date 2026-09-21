#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
typedef struct { int32_t id; double x; double y; } EMGContact;
typedef void (*EMGFrameCallback)(uintptr_t device, const EMGContact *contacts, int count, double time, uint64_t generation, double rotation, int pinchFingers, void *context);
int EMGStart(EMGFrameCallback callback, void *context);
void EMGStop(void);
uint64_t EMGGeneration(void);
void EMGReset(double rotation, int pinchFingers);
const char *EMGError(void);
