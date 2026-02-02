#include <AppKit/AppKit.h>
#include <QuartzCore/CAMetalLayer.h>

void *dvuiCreateMetalLayer(void *nswindow_ptr) {
    @autoreleasepool {
        NSWindow *window = (__bridge NSWindow *)nswindow_ptr;
        if (!window) return NULL;
        NSView *view = window.contentView;
        if (!view) return NULL;
        [view setWantsLayer:YES];
        CALayer *layer = view.layer;
        if (layer == nil || ![layer isKindOfClass:[CAMetalLayer class]]) {
            CAMetalLayer *metal_layer = [CAMetalLayer layer];
            view.layer = metal_layer;
            layer = metal_layer;
        }
        return (__bridge void *)layer;
    }
}

void dvuiSetMetalLayerSize(void *layer_ptr, double width, double height, double scale) {
    @autoreleasepool {
        CAMetalLayer *layer = (__bridge CAMetalLayer *)layer_ptr;
        if (!layer) return;
        layer.contentsScale = scale > 0.0 ? scale : 1.0;
        layer.drawableSize = CGSizeMake(width, height);
    }
}

