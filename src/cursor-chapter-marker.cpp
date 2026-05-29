/*
Cursor Chapter Marker -- OBS Studio plugin
Copyright (C) 2026 Juliano Ouvrard

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
*/

#include "cursor-chapter-marker.hpp"
#include <obs.hpp>

#include <QAction>
#include <QMainWindow>
#include <QVBoxLayout>
#include <QGroupBox>
#include <QPushButton>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#endif

#include <string>
#include <cstring>

// --------------------------------------------------------------------------
// Mouse position (virtual desktop coordinates)
// --------------------------------------------------------------------------

struct MousePos {
	int x;
	int y;
};

static MousePos GetMousePos()
{
	MousePos pos = {0, 0};
#ifdef _WIN32
	POINT p;
	if (GetCursorPos(&p)) {
		pos.x = static_cast<int>(p.x);
		pos.y = static_cast<int>(p.y);
	}
#endif
	return pos;
}

// --------------------------------------------------------------------------
// Capture source detection
// --------------------------------------------------------------------------

// Result filled by the scene enumeration callback
struct CaptureOrigin {
	bool     found;
	int      x;      // top-left of captured area in virtual desktop coords
	int      y;
	std::string source_name;
};

#ifdef _WIN32

// Return the top-left corner of monitor number `index` (0-based, same order
// as EnumDisplayMonitors).
static bool MonitorOffsetByIndex(int index, int *ox, int *oy)
{
	struct State {
		int target, current, x, y;
		bool found;
	} s = {index, 0, 0, 0, false};

	EnumDisplayMonitors(
		nullptr, nullptr,
		[](HMONITOR hmon, HDC, LPRECT, LPARAM lp) -> BOOL {
			auto *st = reinterpret_cast<State *>(lp);
			if (st->current == st->target) {
				MONITORINFO mi = {};
				mi.cbSize = sizeof(mi);
				GetMonitorInfo(hmon, &mi);
				st->x = mi.rcMonitor.left;
				st->y = mi.rcMonitor.top;
				st->found = true;
				return FALSE;
			}
			++st->current;
			return TRUE;
		},
		reinterpret_cast<LPARAM>(&s));

	*ox = s.x;
	*oy = s.y;
	return s.found;
}

// OBS window_capture / game_capture store the window as
// "Window Title:Window Class:Executable.exe".
// We find it via EnumWindows matching title + exe name.
struct WindowSearch {
	std::string title;
	std::string exe;
	HWND        hwnd;
};

static BOOL CALLBACK FindWindowCb(HWND hwnd, LPARAM lp)
{
	auto *ws = reinterpret_cast<WindowSearch *>(lp);

	// Skip invisible windows
	if (!IsWindowVisible(hwnd))
		return TRUE;

	// Match title (if we have one)
	if (!ws->title.empty()) {
		char buf[512] = {};
		GetWindowTextA(hwnd, buf, sizeof(buf));
		if (ws->title != buf)
			return TRUE;
	}

	// Match exe (if we have one)
	if (!ws->exe.empty()) {
		DWORD pid = 0;
		GetWindowThreadProcessId(hwnd, &pid);
		HANDLE ph = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
		if (ph) {
			char exePath[512] = {};
			DWORD len = sizeof(exePath);
			QueryFullProcessImageNameA(ph, 0, exePath, &len);
			CloseHandle(ph);
			// Compare only the filename part
			const char *slash = strrchr(exePath, '\\');
			const char *exeName = slash ? slash + 1 : exePath;
			if (_stricmp(ws->exe.c_str(), exeName) != 0)
				return TRUE;
		}
	}

	ws->hwnd = hwnd;
	return FALSE; // stop enumeration
}

// Returns the client-area origin in screen (virtual desktop) coordinates.
static bool WindowClientOrigin(const char *window_setting, int *ox, int *oy)
{
	if (!window_setting || !*window_setting)
		return false;

	// Format: "Title:Class:Exe"
	std::string s(window_setting);
	auto split = [&](std::string &out, size_t &pos) {
		size_t colon = s.find(':', pos);
		out = (colon == std::string::npos) ? s.substr(pos)
		                                   : s.substr(pos, colon - pos);
		pos = (colon == std::string::npos) ? s.size() : colon + 1;
	};
	size_t pos = 0;
	std::string title, cls, exe;
	split(title, pos);
	split(cls,   pos);
	split(exe,   pos);

	WindowSearch ws;
	ws.title = title;
	ws.exe   = exe;
	ws.hwnd  = nullptr;
	EnumWindows(FindWindowCb, reinterpret_cast<LPARAM>(&ws));

	if (!ws.hwnd)
		return false;

	// Use client area origin (excludes window chrome)
	POINT pt = {0, 0};
	ClientToScreen(ws.hwnd, &pt);
	*ox = pt.x;
	*oy = pt.y;
	return true;
}

#endif // _WIN32

// --------------------------------------------------------------------------
// Scene enumeration: find the topmost visible capture source
// --------------------------------------------------------------------------

// Source IDs that represent screen/window captures
static bool IsCaptureSource(const char *id)
{
	return (strcmp(id, "monitor_capture") == 0 ||
	        strcmp(id, "display_capture") == 0 ||
	        strcmp(id, "window_capture")  == 0 ||
	        strcmp(id, "game_capture")    == 0 ||
	        // macOS
	        strcmp(id, "screen_capture")  == 0 ||
	        // Linux
	        strcmp(id, "xshm_input")      == 0 ||
	        strcmp(id, "pipewire-desktop-capture-source") == 0);
}

struct EnumState {
	obs_source_t *best; // topmost visible capture source found so far
};

static bool SceneItemEnumCb(obs_scene_t *, obs_sceneitem_t *item, void *data)
{
	auto *st = reinterpret_cast<EnumState *>(data);

	if (!obs_sceneitem_visible(item))
		return true;

	obs_source_t *src = obs_sceneitem_get_source(item);
	const char   *id  = obs_source_get_id(src);

	if (!IsCaptureSource(id))
		return true;

	// Only consider sources that are actively producing video.
	// A game_capture with no game, or a window_capture of a closed window,
	// returns 0x0 — we skip those.
	if (obs_source_get_width(src) == 0 || obs_source_get_height(src) == 0)
		return true;

	st->best = src; // keep overwriting — last (topmost) wins
	return true;
}

// Return the virtual-desktop origin of the active capture source in the
// current OBS scene.  Returns false if none found or origin cannot be
// determined (caller should fall back to raw coordinates).
static bool GetActiveCaptureOrigin(CaptureOrigin &out)
{
	out = {false, 0, 0, ""};

	OBSSourceAutoRelease sceneSource = obs_frontend_get_current_scene();
	if (!sceneSource)
		return false;

	obs_scene_t *scene = obs_scene_from_source(sceneSource);
	if (!scene)
		return false;

	EnumState st = {nullptr};
	obs_scene_enum_items(scene, SceneItemEnumCb, &st);

	if (!st.best)
		return false;

	const char *id   = obs_source_get_id(st.best);
	const char *name = obs_source_get_name(st.best);
	out.source_name  = name ? name : "";

#ifdef _WIN32
	OBSDataAutoRelease settings = obs_source_get_settings(st.best);

	if (strcmp(id, "monitor_capture") == 0 ||
	    strcmp(id, "display_capture") == 0) {
		// "monitor" key is a 0-based index
		int idx = static_cast<int>(obs_data_get_int(settings, "monitor"));
		if (MonitorOffsetByIndex(idx, &out.x, &out.y)) {
			out.found = true;
		}
	} else if (strcmp(id, "window_capture") == 0 ||
	           strcmp(id, "game_capture")   == 0) {
		const char *win = obs_data_get_string(settings, "window");
		if (WindowClientOrigin(win, &out.x, &out.y))
			out.found = true;
	}
#else
	(void)id;
	// macOS / Linux: fall back to raw coords
#endif

	return out.found;
}

// --------------------------------------------------------------------------
// Format string substitution (%X, %Y)
// --------------------------------------------------------------------------

static std::string FormatMarker(const std::string &fmt, int x, int y)
{
	std::string result;
	result.reserve(fmt.size() + 16);
	for (size_t i = 0; i < fmt.size(); ++i) {
		if (fmt[i] == '%' && i + 1 < fmt.size()) {
			char next = fmt[i + 1];
			if (next == 'X') { result += std::to_string(x); ++i; continue; }
			if (next == 'Y') { result += std::to_string(y); ++i; continue; }
		}
		result += fmt[i];
	}
	return result;
}

// --------------------------------------------------------------------------
// Global state
// --------------------------------------------------------------------------

FormatCache g_formats;
static CursorChapterSettings *settingsDialog = nullptr;
static obs_hotkey_id hotkeyPress   = OBS_INVALID_HOTKEY_ID;
static obs_hotkey_id hotkeyRelease = OBS_INVALID_HOTKEY_ID;

// --------------------------------------------------------------------------
// Hotkey callbacks — read g_formats directly, no Qt cross-thread calls
// --------------------------------------------------------------------------

static void OnHotkeyPress(void *, obs_hotkey_id, obs_hotkey_t *, bool pressed)
{
	if (!pressed)
		return;
	if (!obs_frontend_recording_active())
		return;

	MousePos raw = GetMousePos();

	CaptureOrigin origin;
	int cx = raw.x;
	int cy = raw.y;
	if (GetActiveCaptureOrigin(origin)) {
		cx = raw.x - origin.x;
		cy = raw.y - origin.y;
	}

	std::string marker = FormatMarker(g_formats.getPress(), cx, cy);
	obs_frontend_recording_add_chapter(marker.c_str());
}

static void OnHotkeyRelease(void *, obs_hotkey_id, obs_hotkey_t *, bool pressed)
{
	if (!pressed)
		return;
	if (!obs_frontend_recording_active())
		return;

	std::string marker = FormatMarker(g_formats.getRelease(), 0, 0);
	obs_frontend_recording_add_chapter(marker.c_str());
}

// --------------------------------------------------------------------------
// Settings persistence
// --------------------------------------------------------------------------

static void OnSaveLoad(obs_data_t *save_data, bool saving, void *)
{
	if (saving) {
		OBSDataAutoRelease obj = obs_data_create();
		settingsDialog->SaveSettings(obj);

		OBSDataArrayAutoRelease pressArr = obs_hotkey_save(hotkeyPress);
		obs_data_set_array(obj, "hotkey_press", pressArr);
		OBSDataArrayAutoRelease releaseArr = obs_hotkey_save(hotkeyRelease);
		obs_data_set_array(obj, "hotkey_release", releaseArr);

		obs_data_set_obj(save_data, "cursor_chapter_marker", obj);
	} else {
		OBSDataAutoRelease obj =
			obs_data_get_obj(save_data, "cursor_chapter_marker");
		if (obj) {
			settingsDialog->LoadSettings(obj);

			OBSDataArrayAutoRelease pressArr =
				obs_data_get_array(obj, "hotkey_press");
			obs_hotkey_load(hotkeyPress, pressArr);
			OBSDataArrayAutoRelease releaseArr =
				obs_data_get_array(obj, "hotkey_release");
			obs_hotkey_load(hotkeyRelease, releaseArr);
		}
	}
}

// --------------------------------------------------------------------------
// Entry point
// --------------------------------------------------------------------------

extern "C" void InitCursorChapterMarker()
{
	auto *window =
		static_cast<QMainWindow *>(obs_frontend_get_main_window());

	obs_frontend_push_ui_translation(obs_module_get_string);
	settingsDialog = new CursorChapterSettings(window);
	obs_frontend_pop_ui_translation();

	hotkeyPress = obs_hotkey_register_frontend(
		"cursor_chapter_marker.press",
		obs_module_text("CursorChapterMarker.Hotkey.Press"),
		OnHotkeyPress, nullptr);

	hotkeyRelease = obs_hotkey_register_frontend(
		"cursor_chapter_marker.release",
		obs_module_text("CursorChapterMarker.Hotkey.Release"),
		OnHotkeyRelease, nullptr);

	auto *action = static_cast<QAction *>(obs_frontend_add_tools_menu_qaction(
		obs_module_text("CursorChapterMarker.Menu")));
	QAction::connect(action, &QAction::triggered, settingsDialog,
	                 &CursorChapterSettings::exec);

	obs_frontend_add_save_callback(OnSaveLoad, nullptr);
}

// --------------------------------------------------------------------------
// Settings dialog
// --------------------------------------------------------------------------

CursorChapterSettings::CursorChapterSettings(QWidget *parent)
	: QDialog(parent)
{
	setWindowTitle(obs_module_text("CursorChapterMarker.Settings.Title"));
	setWindowFlags(windowFlags() & ~Qt::WindowContextHelpButtonHint);
	setFixedWidth(480);

	auto *layout = new QVBoxLayout(this);

	auto *pressGroup = new QGroupBox(
		obs_module_text("CursorChapterMarker.Settings.PressGroup"), this);
	auto *pressLayout = new QFormLayout(pressGroup);
	pressFormatEdit = new QLineEdit(DEFAULT_PRESS_FORMAT, this);
	pressLayout->addRow(obs_module_text("CursorChapterMarker.Settings.Format"),
	                    pressFormatEdit);
	auto *hint = new QLabel(obs_module_text("CursorChapterMarker.Settings.Hint"), this);
	hint->setWordWrap(true);
	pressLayout->addRow(hint);
	layout->addWidget(pressGroup);

	auto *releaseGroup = new QGroupBox(
		obs_module_text("CursorChapterMarker.Settings.ReleaseGroup"), this);
	auto *releaseLayout = new QFormLayout(releaseGroup);
	releaseFormatEdit = new QLineEdit(DEFAULT_RELEASE_FORMAT, this);
	releaseLayout->addRow(obs_module_text("CursorChapterMarker.Settings.Format"),
	                      releaseFormatEdit);
	layout->addWidget(releaseGroup);

	auto *buttons = new QDialogButtonBox(
		QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
	connect(buttons, &QDialogButtonBox::accepted, this, &CursorChapterSettings::onAccepted);
	connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
	layout->addWidget(buttons);
}

void CursorChapterSettings::onAccepted()
{
	// Sync the thread-safe cache before closing the dialog
	g_formats.set(pressFormatEdit->text().toStdString(),
	              releaseFormatEdit->text().toStdString());
	accept();
}

void CursorChapterSettings::LoadSettings(obs_data_t *data)
{
	const char *press   = obs_data_get_string(data, "press_format");
	const char *release = obs_data_get_string(data, "release_format");
	if (press   && *press)   pressFormatEdit->setText(QString::fromUtf8(press));
	if (release && *release) releaseFormatEdit->setText(QString::fromUtf8(release));
	g_formats.set(pressFormatEdit->text().toStdString(),
	              releaseFormatEdit->text().toStdString());
}

void CursorChapterSettings::SaveSettings(obs_data_t *data) const
{
	obs_data_set_string(data, "press_format",
	                    pressFormatEdit->text().toUtf8().constData());
	obs_data_set_string(data, "release_format",
	                    releaseFormatEdit->text().toUtf8().constData());
}
