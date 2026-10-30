ARCHS = arm64
TARGET = iphone:clang:16.5:17.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = YTDiagnostics
YTDiagnostics_FILES = Tweak.xm
YTDiagnostics_CFLAGS = -fobjc-arc
YTDiagnostics_FRAMEWORKS = UIKit Foundation AVFoundation
include $(THEOS_MAKE_PATH)/tweak.mk
