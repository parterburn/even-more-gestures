#include "TouchBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <pthread.h>
#include <string.h>
#include <math.h>

// Reverse-engineered MT contact ABI, isolated here. No framework linked at build time.
// Fixed offsets are validated by layout assertions; invalid coordinates fail closed.
typedef struct {
    int32_t frame; double time;
    int32_t path, state, finger, hand;
    float x, y, vx, vy, pressure;
    int32_t reserved1;
    float angle, major, minor, ax, ay, avx, avy;
    int32_t reserved2, reserved3;
    float density;
} RawContact;
_Static_assert(sizeof(RawContact) == 96, "Unexpected MT contact layout");
_Static_assert(offsetof(RawContact, x) == 32, "Unexpected MT position layout");
typedef const void *Device;
typedef void (*RawCallback)(Device, const RawContact *, size_t, double, size_t);
static CFArrayRef (*createList)(void);
static void (*registerFrame)(Device, RawCallback);
static void (*unregisterFrame)(Device, RawCallback);
static int (*startDevice)(Device, int);
static int (*stopDevice)(Device);
static io_service_t (*getService)(Device);
static bool (*builtIn)(Device);
static int (*dimensions)(Device, int *, int *);
static void *library;
static CFArrayRef deviceList;
static Device devices[16];
static int deviceCount;
static EMGFrameCallback sink;
static void *sinkContext;
static atomic_bool enabled;
static atomic_uint_fast64_t generation = 1;
static _Atomic double step = 30;
static atomic_int pinchCount = 3;
static pthread_mutex_t delivery = PTHREAD_MUTEX_INITIALIZER;
static const char *errorMessage = "Not started";

static void frame(Device device, const RawContact *raw, size_t count, double time, size_t frameNumber) {
    if (!atomic_load(&enabled)) return;
    // The framework does not promise callbacks from different devices are serialized.
    // Serialize the short recognizer path; no heap allocation or AX calls in this block.
    pthread_mutex_lock(&delivery);
    if (!atomic_load(&enabled)) { pthread_mutex_unlock(&delivery); return; }
    EMGContact points[5]; int active = 0;
    if (count > 32 || (count && !raw)) { active = 5; }
    else for (size_t i = 0; i < count; i++) {
        if (raw[i].state != 3 && raw[i].state != 4) continue;
        if (active == 5) break;
        points[active++] = (EMGContact){raw[i].path, raw[i].x, raw[i].y};
    }
    // Five contacts force cancellation. Swift only reads the first four for valid sessions.
    if (active == 5) for (int i=0;i<5;i++) points[i] = (EMGContact){i, 0, 0};
    if (sink) sink((uintptr_t)device, points, active, time, atomic_load(&generation), atomic_load(&step), atomic_load(&pinchCount), sinkContext);
    pthread_mutex_unlock(&delivery);
}
static bool isTrackpad(Device device) {
    if (getService) {
        io_service_t service = getService(device);
        if (service) {
            CFTypeRef value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("Product"), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);
            if (value) {
                bool match = CFGetTypeID(value) == CFStringGetTypeID() && CFStringFind((CFStringRef)value, CFSTR("Trackpad"), kCFCompareCaseInsensitive).location != kCFNotFound;
                CFRelease(value);
                if (match) return true;
            }
        }
    }
    // Internal wide, two-dimensional sensor only; rejects Touch Bar and external unknowns.
    int w=0,h=0;
    return builtIn && builtIn(device) && dimensions && !dimensions(device,&w,&h) && w>0 && h>0 && (double)w/h > 0.8 && (double)w/h < 2.3;
}
int EMGStart(EMGFrameCallback callback, void *context) {
    EMGStop();
    if (!library) library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!library) { errorMessage = "MultitouchSupport could not be loaded on this macOS version."; return -1; }
#define LOAD(var, name) *(void **)(&var) = dlsym(library, name)
    LOAD(createList,"MTDeviceCreateList"); LOAD(registerFrame,"MTRegisterContactFrameCallback");
    LOAD(unregisterFrame,"MTUnregisterContactFrameCallback"); LOAD(startDevice,"MTDeviceStart"); LOAD(stopDevice,"MTDeviceStop");
    LOAD(getService,"MTDeviceGetService"); LOAD(builtIn,"MTDeviceIsBuiltIn"); LOAD(dimensions,"MTDeviceGetSensorSurfaceDimensions");
    if (!createList || !registerFrame || !unregisterFrame || !startDevice || !stopDevice) { errorMessage = "Required multitouch symbols are unavailable."; return -1; }
    sink=callback; sinkContext=context; deviceList=createList();
    if (!deviceList) { errorMessage = "No multitouch devices are available."; return 0; }
    atomic_store(&enabled, true);
    for (CFIndex i=0;i<CFArrayGetCount(deviceList) && deviceCount<16;i++) {
        Device device=CFArrayGetValueAtIndex(deviceList,i);
        if (!isTrackpad(device)) continue;
        registerFrame(device,frame);
        if (startDevice(device,0) == 0) devices[deviceCount++]=device;
        else unregisterFrame(device,frame);
    }
    errorMessage = deviceCount ? "Trackpad connected" : "No supported trackpad found. Connect a built-in or Magic Trackpad.";
    return deviceCount;
}
void EMGStop(void) {
    atomic_store(&enabled,false); atomic_fetch_add(&generation,1);
    for(int i=0;i<deviceCount;i++) { stopDevice(devices[i]); unregisterFrame(devices[i],frame); }
    pthread_mutex_lock(&delivery); sink=NULL; sinkContext=NULL; pthread_mutex_unlock(&delivery);
    deviceCount=0;
    if(deviceList) { CFRelease(deviceList); deviceList=NULL; }
}
uint64_t EMGGeneration(void) { return atomic_load(&generation); }
void EMGReset(double rotation, int pinchFingers) { atomic_store(&step,rotation); atomic_store(&pinchCount,pinchFingers == 2 ? 2 : 3); atomic_fetch_add(&generation,1); }
const char *EMGError(void) { return errorMessage; }
