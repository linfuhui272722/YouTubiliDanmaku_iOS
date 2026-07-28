TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = YouTube

ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootful

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouTubiliDanmaku

YouTubiliDanmaku_FILES = \
	Tweak.x \
	DanmakuModel.m \
	BiliAPI.m \
	DanmakuOverlayView.m \
	SettingsManager.m \
	DanmakuControlView.m

YouTubiliDanmaku_CFLAGS = \
	-fobjc-arc \
	-Wno-deprecated-declarations \
	-Wno-unused-variable \
	-Wno-unused-function \
	-Wno-incompatible-pointer-types \
	-Wno-undeclared-selector

YouTubiliDanmaku_FRAMEWORKS = UIKit Foundation AVFoundation
YouTubiliDanmaku_LDFLAGS = -lz

include $(THEOS_MAKE_PATH)/tweak.mk
